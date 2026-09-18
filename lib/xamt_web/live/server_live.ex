defmodule XamtWeb.ServerLive do
  use XamtWeb, :live_view

  alias Xamt.{Channels, Messages, Servers}
  alias Xamt.Channels.Channel
  alias XamtWeb.Presence

  @message_page_size 50
  @member_page_size 50

  @impl true
  def mount(%{"server_slug" => server_slug} = params, _session, socket) do
    scope = socket.assigns.current_scope
    server = Servers.get_server_by_slug!(server_slug)

    unless Servers.member?(server.id, scope.user.id) do
      {:ok, _} = Servers.join_server(scope, server.id)
    end

    channels = Channels.list_channels(server.id)
    members = Servers.list_members(server.id, limit: @member_page_size, offset: 0)

    channel =
      case Map.get(params, "channel_slug") do
        nil -> List.first(channels)
        slug -> Channels.get_channel_by_slug!(server.id, slug)
      end

    if connected?(socket) do
      Enum.each(channels, &subscribe_channel/1)

      if channel do
        Presence.track_user(self(), channel_topic(channel), scope.user)
      end
    end

    messages =
      if channel do
        Messages.list_messages(channel.id)
      else
        []
      end

    unread_ids = Channels.get_unread_channel_ids(scope.user.id, server.id)
    user_servers = Servers.list_servers_for_user(scope)

    socket =
      socket
      |> assign(:page_title, server.name)
      |> assign(:server, server)
      |> assign(:user_servers, user_servers)
      |> assign(:channels, channels)
      |> assign(:members_offset, @member_page_size)
      |> assign(:has_more_members, length(members) == @member_page_size)
      |> stream(:members, members)
      |> assign(:active_channel, channel)
      |> assign(:online_users, list_online(channel))
      |> assign(:typing_users, %{})
      |> assign(:editing_message_id, nil)
      |> assign(:show_channel_form, false)
      |> assign(:channel_form, to_form(Channels.change_channel(%Channel{}), as: :channel))
      |> assign(:mobile_panel, :messages)
      |> assign(:unread_channels, MapSet.new(unread_ids))
      |> assign_messages(messages)
      |> allow_upload(:media,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 4,
        max_file_size: 10_000_000,
        auto_upload: true
      )

    if channel && is_nil(Map.get(params, "channel_slug")) do
      {:ok, push_navigate(socket, to: ~p"/servers/#{server.slug}/#{channel.slug}")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"channel_slug" => channel_slug} = params, _uri, socket) do
    server = socket.assigns.server
    scope = socket.assigns.current_scope
    old_channel = socket.assigns.active_channel
    channel = Channels.get_channel_by_slug!(server.id, channel_slug)

    socket =
      if (connected?(socket) and old_channel) && old_channel.id != channel.id do
        Presence.untrack_user(self(), channel_topic(old_channel), scope.user)
        Presence.track_user(self(), channel_topic(channel), scope.user)
        socket
      else
        socket
      end

    messages = Messages.list_messages(channel.id)
    latest_msg = List.last(messages)

    unread_channels =
      if latest_msg do
        Channels.mark_channel_as_read(scope.user.id, channel.id, latest_msg.id)
        MapSet.delete(socket.assigns.unread_channels, channel.id)
      else
        MapSet.delete(socket.assigns.unread_channels, channel.id)
      end

    {:noreply,
     socket
     |> assign(:active_channel, channel)
     |> assign(:online_users, list_online(channel))
     |> assign(:typing_users, %{})
     |> assign(:editing_message_id, nil)
     |> assign(:mobile_panel, :messages)
     |> assign(:unread_channels, unread_channels)
     |> assign_messages(messages)
     |> maybe_push_composer_reset(params)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  def handle_event("send_message", params, socket) do
    scope = socket.assigns.current_scope
    channel = socket.assigns.active_channel

    if Enum.any?(socket.assigns.uploads.media.entries, &(not &1.done?)) do
      {:noreply, put_flash(socket, :error, gettext("Please wait for uploads to finish"))}
    else
      media_html = consume_media_html(socket)

      attrs = %{
        "content" => decode_json(params["content_json"]),
        "content_html" => (params["content_html"] || "") <> media_html,
        "content_type" => params["content_type"] || "rich_text"
      }

      case Messages.create_message(scope, channel.id, attrs) do
        {:ok, _message} ->
          {:noreply,
           socket
           |> assign(:editing_message_id, nil)
           |> push_event("composer:clear", %{})}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not send message"))}
      end
    end
  end

  def handle_event("edit_message", %{"id" => id}, socket) do
    message = Messages.get_message!(id)

    if message.user_id == socket.assigns.current_scope.user.id do
      html = message.content_html || ""

      {:noreply,
       socket
       |> assign(:editing_message_id, id)
       |> push_event("composer:load", %{"html" => html})}
    else
      {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("update_message", params, socket) do
    scope = socket.assigns.current_scope
    id = socket.assigns.editing_message_id

    if Enum.any?(socket.assigns.uploads.media.entries, &(not &1.done?)) do
      {:noreply, put_flash(socket, :error, gettext("Please wait for uploads to finish"))}
    else
      media_html = consume_media_html(socket)

      attrs = %{
        "content" => decode_json(params["content_json"]),
        "content_html" => (params["content_html"] || "") <> media_html,
        "content_type" => params["content_type"] || "rich_text"
      }

      case Messages.update_message(scope, id, attrs) do
        {:ok, _message} ->
          {:noreply,
           socket
           |> assign(:editing_message_id, nil)
           |> push_event("composer:clear", %{})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update message"))}
      end
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_message_id, nil)
     |> push_event("composer:clear", %{})}
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    case Messages.soft_delete_message(socket.assigns.current_scope, id) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not delete message"))}
    end
  end

  def handle_event("load_older", _params, socket) do
    channel = socket.assigns.active_channel
    oldest_id = socket.assigns[:oldest_message_id]

    if not socket.assigns.has_more_messages or is_nil(oldest_id) do
      {:noreply, push_event(socket, "infinite_scroll:done", %{})}
    else
      messages = Messages.list_messages(channel.id, before_id: oldest_id)

      socket =
        case messages do
          [first | _] = msgs ->
            socket
            |> assign(:oldest_message_id, first.id)
            |> assign(:has_more_messages, length(msgs) >= @message_page_size)
            |> stream(:messages, msgs, at: 0)
            |> maybe_done_loading(length(msgs) >= @message_page_size)

          [] ->
            socket
            |> assign(:has_more_messages, false)
            |> push_event("infinite_scroll:done", %{})
        end

      {:noreply, socket}
    end
  end

  def handle_event("load_more_members", _params, socket) do
    if socket.assigns.has_more_members do
      server = socket.assigns.server
      offset = socket.assigns.members_offset

      new_members =
        Servers.list_members(server.id, limit: @member_page_size, offset: offset)

      has_more = length(new_members) == @member_page_size

      socket =
        socket
        |> assign(:members_offset, offset + @member_page_size)
        |> assign(:has_more_members, has_more)

      socket =
        Enum.reduce(new_members, socket, fn member, acc ->
          stream_insert(acc, :members, member)
        end)

      socket =
        if has_more do
          socket
        else
          push_event(socket, "infinite_scroll:done", %{})
        end

      {:noreply, socket}
    else
      {:noreply, push_event(socket, "infinite_scroll:done", %{})}
    end
  end

  def handle_event("toggle_channel_form", _params, socket) do
    {:noreply, assign(socket, :show_channel_form, !socket.assigns.show_channel_form)}
  end

  def handle_event("create_channel", %{"channel" => params}, socket) do
    server = socket.assigns.server

    case Channels.create_channel(server, params) do
      {:ok, channel} ->
        channels = Channels.list_channels(server.id)

        if connected?(socket), do: subscribe_channel(channel)

        {:noreply,
         socket
         |> assign(:channels, channels)
         |> assign(:show_channel_form, false)
         |> push_navigate(to: ~p"/servers/#{server.slug}/#{channel.slug}")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, channel_form: to_form(changeset, as: :channel), show_channel_form: true)}
    end
  end

  def handle_event("typing_started", _params, socket) do
    channel = socket.assigns.active_channel
    user = socket.assigns.current_scope.user

    Phoenix.PubSub.broadcast(
      Xamt.PubSub,
      channel_topic(channel),
      {:typing_started, channel.id, user.id, display_name(user)}
    )

    {:noreply, socket}
  end

  def handle_event("typing_stopped", _params, socket) do
    channel = socket.assigns.active_channel
    user = socket.assigns.current_scope.user

    Phoenix.PubSub.broadcast(
      Xamt.PubSub,
      channel_topic(channel),
      {:typing_stopped, channel.id, user.id}
    )

    {:noreply, socket}
  end

  def handle_event("set_mobile_panel", %{"panel" => panel}, socket) do
    panel = String.to_existing_atom(panel)
    {:noreply, assign(socket, :mobile_panel, panel)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    active_channel = socket.assigns.active_channel
    user_id = socket.assigns.current_scope.user.id

    socket =
      cond do
        active_channel && message.channel_id == active_channel.id ->
          Channels.mark_channel_as_read(user_id, active_channel.id, message.id)

          socket
          |> stream_insert(:messages, message)
          |> assign(:oldest_message_id, socket.assigns[:oldest_message_id] || message.id)
          |> push_event("messages:scroll_bottom", %{})

        message.user_id != user_id and server_channel?(socket, message.channel_id) ->
          assign(
            socket,
            :unread_channels,
            MapSet.put(socket.assigns.unread_channels, message.channel_id)
          )

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info({:updated_message, message}, socket) do
    if active_channel_message?(socket, message) do
      {:noreply, stream_insert(socket, :messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted_message, message}, socket) do
    if active_channel_message?(socket, message) do
      {:noreply, stream_delete(socket, :messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:typing_started, channel_id, user_id, name}, socket) do
    active = socket.assigns.active_channel

    cond do
      is_nil(active) or active.id != channel_id ->
        {:noreply, socket}

      user_id == socket.assigns.current_scope.user.id ->
        {:noreply, socket}

      true ->
        typing = Map.put(socket.assigns.typing_users, user_id, name)
        {:noreply, assign(socket, :typing_users, typing)}
    end
  end

  def handle_info({:typing_stopped, channel_id, user_id}, socket) do
    active = socket.assigns.active_channel

    if active && active.id == channel_id do
      {:noreply, assign(socket, :typing_users, Map.delete(socket.assigns.typing_users, user_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff"}, socket) do
    if topic == channel_topic(socket.assigns.active_channel) do
      {:noreply, assign(socket, :online_users, list_online(socket.assigns.active_channel))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={"xamt-app xamt-app--panel-#{@mobile_panel}"} id="xamt-app">
      <Layouts.flash_group flash={@flash} />
      <aside class="xamt-rail xamt-rail--servers">
        <div class="xamt-rail__brand">
          <.link navigate={~p"/"} class="xamt-brand-mark">X</.link>
        </div>
        <.link
          :for={s <- @user_servers}
          navigate={~p"/servers/#{s.slug}"}
          class={"xamt-server-dot #{if s.id == @server.id, do: "is-active"}"}
          title={s.name}
        >
          {server_initial(s.name)}
        </.link>
      </aside>

      <aside class="xamt-rail xamt-rail--channels">
        <header class="xamt-rail__header">
          <h1 class="xamt-rail__title mongol-text">{@server.name}</h1>
          <p class="xamt-rail__sub">/{@server.slug}</p>
        </header>

        <div class="xamt-rail__section">
          <div class="xamt-rail__section-head">
            <span>{gettext("Channels")}</span>
            <button
              type="button"
              class="xamt-icon-btn"
              phx-click="toggle_channel_form"
              title={gettext("New channel")}
            >
              +
            </button>
          </div>

          <form
            :if={@show_channel_form}
            id="create-channel-form"
            phx-submit="create_channel"
            class="xamt-form xamt-form--compact"
          >
            <input
              type="text"
              name="channel[name]"
              id="channel_name"
              required
              placeholder={gettext("Channel name")}
              class="xamt-input mongol-input"
              phx-hook="MongolianIME"
              autocomplete="off"
            />
            <button type="submit" class="xamt-btn xamt-btn--primary xamt-btn--sm">
              {gettext("Add")}
            </button>
          </form>

          <nav class="xamt-channel-nav">
            <.link
              :for={ch <- @channels}
              navigate={~p"/servers/#{@server.slug}/#{ch.slug}"}
              class={[
                "xamt-channel-link",
                @active_channel && ch.id == @active_channel.id && "is-active",
                MapSet.member?(@unread_channels, ch.id) && "has-unread"
              ]}
            >
              <div class="flex items-center justify-between h-full gap-2">
                <div class="flex items-center gap-1.5 min-w-0">
                  <span class="xamt-channel-hash">#</span>
                  <span class={[
                    "mongol-text truncate",
                    MapSet.member?(@unread_channels, ch.id) && "font-bold text-[var(--xamt-text)]"
                  ]}>
                    {ch.name}
                  </span>
                </div>
                <span
                  :if={
                    MapSet.member?(@unread_channels, ch.id) &&
                      !(@active_channel && ch.id == @active_channel.id)
                  }
                  class="w-2 h-2 shrink-0 rounded-full bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.6)]"
                  aria-hidden="true"
                >
                </span>
              </div>
            </.link>
          </nav>
        </div>

        <div class="xamt-rail__footer">
          <.link navigate={~p"/profile/#{@current_scope.user.username}"} class="xamt-user-chip">
            <span class="xamt-avatar">{user_initial(@current_scope.user)}</span>
            <span class="mongol-text">{display_name(@current_scope.user)}</span>
          </.link>
        </div>
      </aside>

      <section class="xamt-main">
        <header class="xamt-main__header">
          <div class="xamt-mobile-nav">
            <button type="button" phx-click="set_mobile_panel" phx-value-panel="servers">☰</button>
            <button type="button" phx-click="set_mobile_panel" phx-value-panel="channels">#</button>
            <button type="button" phx-click="set_mobile_panel" phx-value-panel="messages">💬</button>
            <button type="button" phx-click="set_mobile_panel" phx-value-panel="members">👥</button>
          </div>
          <h2 class="xamt-main__title">
            <span class="xamt-channel-hash">#</span>
            <span class="mongol-text">{@active_channel && @active_channel.name}</span>
          </h2>
        </header>

        <div
          id="message-list"
          class="xamt-messages"
          phx-update="stream"
          phx-hook="MessageList"
        >
          <div
            :if={@has_more_messages}
            id="messages-infinite-scroll"
            phx-hook="InfiniteScroll"
            class="h-2 w-full shrink-0"
          >
          </div>
          <article
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            class="xamt-message"
            data-message-id={message.id}
          >
            <div class="xamt-message__avatar">{user_initial(message.user)}</div>
            <div class="xamt-message__body">
              <header class="xamt-message__meta">
                <strong class="mongol-text">{display_name(message.user)}</strong>
                <time>{format_time(message.inserted_at)}</time>
                <span :if={edited?(message)} class="xamt-message__edited">{gettext("edited")}</span>
              </header>
              <div
                id={"msg-content-#{message.id}"}
                class="xamt-message__content mongol-text"
                phx-hook="MongolianScroll"
              >
                {raw(safe_html(message))}
              </div>
              <div
                :if={message.user_id == @current_scope.user.id}
                class="xamt-message__actions"
              >
                <button type="button" phx-click="edit_message" phx-value-id={message.id}>
                  {gettext("Edit")}
                </button>
                <button
                  type="button"
                  phx-click="delete_message"
                  phx-value-id={message.id}
                  data-confirm={gettext("Delete this message?")}
                >
                  {gettext("Delete")}
                </button>
              </div>
            </div>
          </article>
        </div>

        <div :if={map_size(@typing_users) > 0} class="xamt-typing">
          {typing_label(@typing_users)}
        </div>

        <div
          class="xamt-composer-wrap"
          data-has-uploads={to_string(@uploads.media.entries != [])}
          data-submit-event={if @editing_message_id, do: "update_message", else: "send_message"}
        >
          <section
            :if={@uploads.media.entries != []}
            id="media-upload-preview"
            class="xamt-upload-preview"
          >
            <div
              :for={entry <- @uploads.media.entries}
              class="xamt-upload-preview__item"
            >
              <.live_img_preview entry={entry} class="xamt-upload-preview__img" />
              <div
                :if={entry.progress < 100}
                class="xamt-upload-preview__progress"
                style={"width: #{entry.progress}%"}
              >
              </div>
              <button
                type="button"
                id={"cancel-upload-#{entry.ref}"}
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="xamt-upload-preview__cancel"
                aria-label={gettext("Cancel upload")}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </div>
          </section>

          <%!-- live_file_input must stay outside phx-update="ignore" so LiveView can patch upload state --%>
          <form id="media-upload-form" phx-change="validate_upload" class="hidden">
            <.live_file_input upload={@uploads.media} />
          </form>

          <div
            id="message-composer"
            phx-hook="MessageComposer"
            phx-update="ignore"
          >
            <div class="xamt-composer__editor" id="composer-editor-host"></div>
          </div>

          <div class="xamt-composer__toolbar">
            <label
              for={@uploads.media.ref}
              class="xamt-btn xamt-btn--soft cursor-pointer mr-auto"
              title={gettext("Upload Media")}
            >
              <.icon name="hero-photo" class="size-5" />
            </label>

            <button
              :if={@editing_message_id}
              type="button"
              class="xamt-btn xamt-btn--sm"
              phx-click="cancel_edit"
            >
              {gettext("Cancel")}
            </button>
            <button type="button" class="xamt-btn xamt-btn--primary" data-composer-send>
              {if @editing_message_id, do: gettext("Save"), else: gettext("Send")}
            </button>
          </div>
        </div>
      </section>

      <aside class="xamt-rail xamt-rail--members">
        <h3 class="xamt-rail__section-head">{gettext("Online")}</h3>
        <ul class="xamt-member-list">
          <li :for={user <- @online_users} class="xamt-member">
            <span class="xamt-presence is-online"></span>
            <span class="mongol-text">{user}</span>
          </li>
        </ul>
        <h3 class="xamt-rail__section-head">{gettext("Members")}</h3>
        <ul id="server-members-list" class="xamt-member-list" phx-update="stream">
          <li :for={{dom_id, member} <- @streams.members} id={dom_id} class="xamt-member">
            <span class="xamt-presence"></span>
            <span class="mongol-text">{display_name(member.user)}</span>
            <span class="xamt-role">{member.role}</span>
          </li>

          <li
            :if={@has_more_members}
            id="members-infinite-scroll"
            phx-hook="InfiniteScroll"
            data-event="load_more_members"
            class="h-2 w-full shrink-0"
          >
          </li>
        </ul>
      </aside>
    </div>
    """
  end

  defp assign_messages(socket, messages) do
    oldest_id =
      case messages do
        [first | _] -> first.id
        _ -> nil
      end

    socket
    |> assign(:oldest_message_id, oldest_id)
    |> assign(:has_more_messages, length(messages) >= @message_page_size)
    |> stream(:messages, messages, reset: true)
  end

  defp maybe_done_loading(socket, true), do: socket

  defp maybe_done_loading(socket, false) do
    push_event(socket, "infinite_scroll:done", %{})
  end

  defp maybe_push_composer_reset(socket, _params) do
    push_event(socket, "composer:clear", %{})
  end

  defp subscribe_channel(%Channel{} = channel) do
    Phoenix.PubSub.subscribe(Xamt.PubSub, channel_topic(channel))
  end

  defp server_channel?(socket, channel_id) do
    Enum.any?(socket.assigns.channels, &(&1.id == channel_id))
  end

  defp active_channel_message?(socket, message) do
    active = socket.assigns.active_channel
    active && message.channel_id == active.id
  end

  defp channel_topic(%Channel{id: id}), do: "xamt:channel:#{id}"
  defp channel_topic(nil), do: "xamt:channel:none"

  defp list_online(nil), do: []

  defp list_online(channel) do
    Presence.list(channel_topic(channel))
    |> Enum.map(fn {_id, %{metas: metas}} ->
      List.first(metas)[:display_name] || List.first(metas)[:username]
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}) when is_binary(name), do: name
  defp display_name(%{email: email}), do: email
  defp display_name(_), do: "?"

  defp user_initial(user) do
    display_name(user) |> String.trim() |> String.first() || "?"
  end

  defp server_initial(name) when is_binary(name) do
    name |> String.trim() |> String.first() || "?"
  end

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  defp edited?(%{inserted_at: a, updated_at: b}) when not is_nil(a) and not is_nil(b) do
    DateTime.diff(b, a, :second) > 1
  end

  defp edited?(_), do: false

  defp safe_html(%{content_html: html}) when is_binary(html) and html != "", do: html
  defp safe_html(%{content: %{"html" => html}}) when is_binary(html), do: html

  defp safe_html(%{content: content}) when is_map(content),
    do: Phoenix.HTML.html_escape(inspect(content))

  defp safe_html(_), do: ""

  defp typing_label(typing_users) do
    names = Map.values(typing_users) |> Enum.join(", ")
    gettext("%{names} typing…", names: names)
  end

  defp decode_json(nil), do: %{}
  defp decode_json(""), do: %{}

  defp decode_json(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  defp decode_json(data) when is_map(data), do: data

  defp consume_media_html(socket) do
    socket
    |> consume_uploaded_entries(:media, fn %{path: path}, entry ->
      ext =
        entry.client_name
        |> Path.extname()
        |> String.downcase()

      if ext in ~w(.jpg .jpeg .png .gif .webp) do
        filename = "#{entry.uuid}#{ext}"
        dest = Path.join([:code.priv_dir(:xamt), "static", "uploads", filename])
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/#{filename}"}
      else
        {:ok, nil}
      end
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(fn url -> ~s(<div class="editor-image"><img src="#{url}" /></div>) end)
    |> Enum.join()
  end
end
