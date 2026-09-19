defmodule XamtWeb.ServerLive do
  use XamtWeb, :live_view

  alias Xamt.{Channels, Messages, Servers}
  alias Xamt.Channels.Channel
  alias Xamt.Messages.Reaction
  alias Xamt.Servers.Server
  alias XamtWeb.Presence

  @message_page_size 50
  @member_page_size 50
  @mobile_panels ~w(servers channels messages members)

  @impl true
  def mount(%{"server_slug" => server_slug} = params, _session, socket) do
    scope = socket.assigns.current_scope
    server = Servers.get_server_by_slug!(server_slug)

    cond do
      Servers.member?(server.id, scope.user.id) ->
        mount_member(server, params, socket)

      Server.public?(server) ->
        {:ok,
         socket
         |> assign(:page_title, server.name)
         |> assign(:server, server)
         |> assign(:member?, false)}

      true ->
        {:ok,
         socket
         |> put_flash(:error, gettext("This server is invite only."))
         |> push_navigate(to: ~p"/")}
    end
  end

  defp mount_member(server, params, socket) do
    scope = socket.assigns.current_scope
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
      |> assign(:member?, true)
      |> assign(:user_servers, user_servers)
      |> assign(:channels, channels)
      |> assign(:members_offset, @member_page_size)
      |> assign(:has_more_members, length(members) == @member_page_size)
      |> stream(:members, members)
      |> assign(:active_channel, channel)
      |> assign(:online_users, list_online(channel))
      |> assign(:typing_users, %{})
      |> assign(:editing_message_id, nil)
      |> assign(:replying_to, nil)
      |> assign(:channel_form, to_form(Channels.change_channel(%Channel{}), as: :channel))
      |> assign(:admin?, Servers.admin?(server.id, scope.user.id))
      |> assign(:server_form, to_form(Servers.change_server(server), as: :server))
      |> assign(:invites, Servers.list_invites(server.id))
      |> assign(:editing_channel, nil)
      |> assign(:show_server_menu, false)
      |> assign(:mobile_panel, :messages)
      |> assign(:mobile_search?, false)
      |> assign(:unread_channels, MapSet.new(unread_ids))
      |> assign(:search_q, "")
      |> assign(:search_results, nil)
      |> assign(:highlight_id, Map.get(params, "highlight"))
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
  def handle_params(_params, _uri, %{assigns: %{member?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_params(%{"channel_slug" => channel_slug} = params, _uri, socket) do
    {:noreply,
     socket
     |> maybe_switch_channel(channel_slug, params)
     |> apply_action(socket.assigns.live_action, params)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("join_server", _params, socket) do
    server = socket.assigns.server

    if Server.public?(server) do
      case Servers.join_server(socket.assigns.current_scope, server.id) do
        {:ok, _} ->
          {:noreply, push_navigate(socket, to: ~p"/servers/#{server.slug}")}

        {:error, :already_member} ->
          {:noreply, push_navigate(socket, to: ~p"/servers/#{server.slug}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not join"))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("This server is invite only."))}
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  def handle_event(
        "mark_as_read",
        %{"message_id" => message_id, "inserted_at" => inserted_at},
        socket
      ) do
    user_id = socket.assigns.current_scope.user.id
    channel = socket.assigns.active_channel

    if channel do
      channel_id = channel.id

      # Persist off the LiveView process; UI updates immediately.
      Task.start(fn ->
        Channels.mark_as_read(user_id, channel_id, message_id, inserted_at)
      end)

      {:noreply,
       assign(
         socket,
         :unread_channels,
         MapSet.delete(socket.assigns.unread_channels, channel_id)
       )}
    else
      {:noreply, socket}
    end
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
        "content_type" => params["content_type"] || "rich_text",
        "reply_to_id" => socket.assigns.replying_to && socket.assigns.replying_to.id
      }

      case Messages.create_message(scope, channel.id, attrs) do
        {:ok, _message} ->
          {:noreply,
           socket
           |> assign(:editing_message_id, nil)
           |> assign(:replying_to, nil)
           |> push_event("composer:clear", %{})}

        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, gettext("Messages sent too fast"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Could not send message"))}
      end
    end
  end

  def handle_event("edit_message", %{"id" => id}, socket) do
    message = Messages.get_message!(id)
    previous_id = socket.assigns.editing_message_id

    if own_active_message?(socket, message) and is_nil(message.deleted_at) do
      html = message.content_html || ""

      {:noreply,
       socket
       |> assign(:editing_message_id, id)
       |> assign(:replying_to, nil)
       |> restream_message(previous_id)
       |> stream_insert(:messages, message)
       |> push_event("populate_composer", %{html: html})}
    else
      {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("reply_message", %{"id" => id}, socket) do
    message = Messages.get_message!(id)

    if active_channel_message?(socket, message) do
      {:noreply,
       socket
       |> assign(:replying_to, message)
       |> assign(:editing_message_id, nil)
       |> assign(:mobile_panel, :messages)
       |> push_event("composer:focus", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_reply", _params, socket) do
    {:noreply, assign(socket, :replying_to, nil)}
  end

  def handle_event("toggle_reaction", %{"id" => id, "emoji" => emoji}, socket) do
    case Messages.toggle_reaction(socket.assigns.current_scope, id, emoji) do
      {:ok, _summary} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not react"))}
    end
  end

  def handle_event("update_message", params, socket) do
    scope = socket.assigns.current_scope
    id = socket.assigns.editing_message_id

    cond do
      is_nil(id) ->
        {:noreply, put_flash(socket, :error, gettext("Could not update message"))}

      Enum.any?(socket.assigns.uploads.media.entries, &(not &1.done?)) ->
        {:noreply, put_flash(socket, :error, gettext("Please wait for uploads to finish"))}

      true ->
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
    previous_id = socket.assigns.editing_message_id

    {:noreply,
     socket
     |> assign(:editing_message_id, nil)
     |> assign(:replying_to, nil)
     |> restream_message(previous_id)
     |> push_event("composer:clear", %{})}
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    case Messages.delete_message(socket.assigns.current_scope, id) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not delete message"))}
    end
  end

  def handle_event("load_older", _params, socket) do
    channel = socket.assigns.active_channel
    oldest_id = socket.assigns[:oldest_message_id]

    if not socket.assigns.has_more_messages or is_nil(oldest_id) do
      {:noreply, done_loading(socket, "load_older")}
    else
      messages = Messages.list_messages(channel.id, before_id: oldest_id)

      socket =
        case messages do
          [first | _] = msgs ->
            socket
            |> assign(:oldest_message_id, first.id)
            |> assign(:has_more_messages, length(msgs) >= @message_page_size)
            |> merge_reactions(msgs)
            |> stream(:messages, msgs, at: 0)
            |> maybe_done_loading("load_older", length(msgs) >= @message_page_size)

          [] ->
            socket
            |> assign(:has_more_messages, false)
            |> done_loading("load_older")
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
          done_loading(socket, "load_more_members")
        end

      {:noreply, socket}
    else
      {:noreply, done_loading(socket, "load_more_members")}
    end
  end

  def handle_event("toggle_server_menu", _params, socket) do
    if socket.assigns.admin? do
      {:noreply, assign(socket, :show_server_menu, !socket.assigns.show_server_menu)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_server_menu", _params, socket) do
    {:noreply, assign(socket, :show_server_menu, false)}
  end

  def handle_event("save_channel", %{"channel" => params}, socket) do
    save_channel(socket, socket.assigns.live_action, params)
  end

  def handle_event("save_channel", params, socket) when is_map(params) do
    save_channel(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete_channel", %{"id" => id}, socket) do
    active = socket.assigns.active_channel

    case Channels.delete_channel(socket.assigns.current_scope, id) do
      {:ok, _channel} ->
        socket = refresh_channels(socket)

        if active && active.id == id do
          case List.first(socket.assigns.channels) do
            nil -> {:noreply, socket}
            next -> {:noreply, push_navigate(socket, to: channel_path(socket, next))}
          end
        else
          {:noreply, socket}
        end

      {:error, :last_channel} ->
        {:noreply, put_flash(socket, :error, gettext("A server needs at least one channel"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("move_channel", %{"id" => id, "direction" => direction}, socket) do
    direction = if direction == "up", do: :up, else: :down

    case Channels.move_channel(socket.assigns.current_scope, id, direction) do
      {:ok, _} -> {:noreply, refresh_channels(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("save_server", %{"server" => params}, socket) do
    case Servers.update_server(socket.assigns.current_scope, socket.assigns.server.id, params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> assign(:server, server)
         |> assign(:server_form, to_form(Servers.change_server(server), as: :server))
         |> put_flash(:info, gettext("Server updated"))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :server_form, to_form(changeset, as: :server))}
    end
  end

  def handle_event("create_invite", _params, socket) do
    case Servers.create_invite(socket.assigns.current_scope, socket.assigns.server.id) do
      {:ok, _invite} ->
        {:noreply, assign(socket, :invites, Servers.list_invites(socket.assigns.server.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("delete_invite", %{"id" => id}, socket) do
    case Servers.delete_invite(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply, assign(socket, :invites, Servers.list_invites(socket.assigns.server.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("kick_member", %{"user-id" => user_id}, socket) do
    server = socket.assigns.server

    case Servers.kick_member(socket.assigns.current_scope, server.id, user_id) do
      {:ok, member} ->
        {:noreply, stream_delete(socket, :members, member)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("set_member_role", %{"user-id" => user_id, "role" => role}, socket) do
    server = socket.assigns.server

    case Servers.change_role(socket.assigns.current_scope, server.id, user_id, role) do
      {:ok, member} ->
        {:noreply, stream_insert(socket, :members, Xamt.Repo.preload(member, :user))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
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

  def handle_event("mention_search", params, socket) do
    q = params["q"] || params[:q] || ""

    members =
      if socket.assigns[:member?] && socket.assigns[:server] do
        Servers.search_members(socket.assigns.server.id, q, limit: 8)
      else
        []
      end

    online_names =
      socket.assigns
      |> Map.get(:online_users, [])
      |> Enum.map(& &1.username)
      |> MapSet.new()

    rows =
      members
      |> Enum.sort_by(fn member ->
        if MapSet.member?(online_names, member.user.username), do: 0, else: 1
      end)
      |> Enum.map(&mention_search_row/1)

    {:reply, %{members: rows}, socket}
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

  def handle_event("set_mobile_panel", %{"panel" => panel}, socket)
      when panel in @mobile_panels do
    requested = String.to_existing_atom(panel)

    next =
      if socket.assigns.mobile_panel == requested do
        :messages
      else
        requested
      end

    {:noreply, assign(socket, :mobile_panel, next)}
  end

  def handle_event("set_mobile_panel", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_mobile_search", _params, socket) do
    {:noreply, assign(socket, :mobile_search?, !socket.assigns.mobile_search?)}
  end

  def handle_event("search", %{"q" => q}, socket) do
    q = String.trim(q)

    results =
      if q == "" do
        nil
      else
        Messages.search_messages(Enum.map(socket.assigns.channels, & &1.id), q)
      end

    {:noreply,
     assign(socket,
       search_q: q,
       search_results: results,
       mobile_search?: q != "" or socket.assigns.mobile_search?
     )}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_q: "", search_results: nil, mobile_search?: false)}
  end

  def handle_event("open_search_result", %{"id" => id} = params, socket) do
    channel_id = params["channel-id"] || params["channel_id"]
    active = socket.assigns.active_channel

    socket =
      socket
      |> assign(:search_results, nil)
      |> assign(:search_q, "")
      |> assign(:mobile_search?, false)

    cond do
      is_nil(channel_id) or (active && active.id == channel_id) ->
        {:noreply, push_event(socket, "messages:scroll_to", %{id: id})}

      true ->
        case Enum.find(socket.assigns.channels, &(&1.id == channel_id)) do
          nil ->
            {:noreply, socket}

          channel ->
            {:noreply,
             push_patch(socket,
               to: ~p"/servers/#{socket.assigns.server.slug}/#{channel.slug}?highlight=#{id}"
             )}
        end
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    active_channel = socket.assigns.active_channel
    user_id = socket.assigns.current_scope.user.id

    socket =
      cond do
        active_channel && message.channel_id == active_channel.id ->
          # Stay in the stream; IntersectionObserver advances the watermark
          # only when the message actually enters the viewport.
          socket
          |> stream_insert(:messages, message)
          |> assign(:messages_empty?, false)
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

  def handle_info({:reaction_changed, message, summary}, socket) do
    if active_channel_message?(socket, message) do
      # The stream item has to be re-inserted for the new summary to render
      {:noreply,
       socket
       |> assign(:reactions, Map.put(socket.assigns.reactions, message.id, summary))
       |> stream_insert(:messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted_message, message}, socket) do
    if active_channel_message?(socket, message) do
      {:noreply,
       socket
       |> maybe_cancel_edit(message.id)
       |> stream_insert(:messages, message)}
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
  def render(%{member?: false} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="xamt-stack" id="server-preview">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Public server")}</p>
        </div>

        <.header>
          <span class="mongol-text">{@server.name}</span>
          <:subtitle>
            <span>/{@server.slug}</span>
          </:subtitle>
        </.header>

        <p :if={@server.description} class="xamt-profile__bio mongol-text">
          {@server.description}
        </p>

        <button
          type="button"
          id="join-server"
          class="xamt-btn xamt-btn--primary mongol-text"
          phx-click="join_server"
        >
          {gettext("Join server")}
        </button>

        <.link navigate={~p"/"} id="preview-back" class="xamt-btn mongol-text">
          {gettext("Back")}
        </.link>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="xamt-chat" id="xamt-app" phx-hook="MobileDrawer">
      <Layouts.flash_group flash={@flash} current_scope={@current_scope} />

      <div class={"xamt-app xamt-app--panel-#{@mobile_panel}"}>
        <button
          :if={@mobile_panel != :messages}
          type="button"
          id="drawer-backdrop"
          class="xamt-drawer-backdrop"
          phx-click="set_mobile_panel"
          phx-value-panel="messages"
          aria-label={gettext("Close panel")}
        >
        </button>
        <aside class="xamt-rail xamt-rail--servers">
          <.link navigate={~p"/"} class="xamt-brand-mark" title="Xamt">X</.link>
          <.link
            :for={s <- @user_servers}
            navigate={~p"/servers/#{s.slug}"}
            class={"xamt-server-dot #{if s.id == @server.id, do: "is-active"}"}
            title={s.name}
          >
            {server_initial(s.name)}
          </.link>
          <.link
            navigate={~p"/profile/#{@current_scope.user.username}"}
            id="current-user-chip"
            class="xamt-user-chip xamt-user-chip--rail"
            title={display_name(@current_scope.user)}
          >
            <.avatar user={@current_scope.user} />
            <span class="mongol-text">{display_name(@current_scope.user)}</span>
          </.link>
        </aside>

        <aside class="xamt-rail xamt-rail--channels">
          <div class="xamt-rail__pane xamt-rail__pane--top">
            <header class="xamt-rail__header">
              <button
                :if={@admin?}
                type="button"
                id="server-menu"
                class="xamt-server-menu__summary"
                phx-click="toggle_server_menu"
                aria-label={gettext("Server menu")}
                aria-expanded={@show_server_menu}
                aria-haspopup="dialog"
              >
                <h1 class="xamt-rail__title mongol-text">{@server.name}</h1>
                <.icon name="hero-chevron-down" class="size-3" />
              </button>
              <h1 :if={not @admin?} class="xamt-rail__title mongol-text">{@server.name}</h1>
              <p class="xamt-rail__sub">/{@server.slug}</p>
            </header>

            <div class="xamt-rail__section">
              <div class="xamt-rail__section-head">
                <span class="mongol-text">{gettext("Channels")}</span>
                <.link
                  :if={@admin? and @active_channel}
                  id="toggle-channel-form"
                  patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/new"}
                  class="xamt-icon-btn"
                  aria-label={gettext("Create channel")}
                >
                  +
                </.link>
              </div>

              <nav class="xamt-channel-nav">
                <div :for={ch <- @channels} class="xamt-channel-item">
                  <.link
                    patch={~p"/servers/#{@server.slug}/#{ch.slug}"}
                    id={"channel-link-#{ch.slug}"}
                    class={[
                      "xamt-channel-link",
                      @active_channel && ch.id == @active_channel.id && "is-active",
                      MapSet.member?(@unread_channels, ch.id) && "has-unread"
                    ]}
                  >
                    <span class="xamt-channel-hash">#</span>
                    <span class={[
                      "mongol-text",
                      MapSet.member?(@unread_channels, ch.id) && "font-bold text-[var(--xamt-text)]"
                    ]}>
                      {ch.name}
                    </span>
                    <span
                      :if={
                        MapSet.member?(@unread_channels, ch.id) &&
                          !(@active_channel && ch.id == @active_channel.id)
                      }
                      class="xamt-unread-dot"
                      aria-hidden="true"
                    >
                    </span>
                  </.link>

                  <.action_menu
                    :if={@admin?}
                    id={"channel-menu-#{ch.id}"}
                    label={gettext("Channel actions")}
                  >
                    <button
                      type="button"
                      class="xamt-icon-btn"
                      phx-click="move_channel"
                      phx-value-id={ch.id}
                      phx-value-direction="up"
                      aria-label={gettext("Move earlier")}
                    >
                      <.icon name="hero-chevron-up" class="size-3" />
                    </button>
                    <button
                      type="button"
                      class="xamt-icon-btn"
                      phx-click="move_channel"
                      phx-value-id={ch.id}
                      phx-value-direction="down"
                      aria-label={gettext("Move later")}
                    >
                      <.icon name="hero-chevron-down" class="size-3" />
                    </button>
                    <.link
                      :if={@active_channel}
                      patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/edit/#{ch.slug}"}
                      id={"edit-channel-#{ch.id}"}
                      class="xamt-icon-btn"
                      aria-label={gettext("Rename channel")}
                    >
                      <.icon name="hero-pencil" class="size-3" />
                    </.link>
                    <button
                      type="button"
                      class="xamt-icon-btn"
                      phx-click="delete_channel"
                      phx-value-id={ch.id}
                      data-confirm={gettext("Delete this channel and all its messages?")}
                      aria-label={gettext("Delete channel")}
                    >
                      <.icon name="hero-trash" class="size-3" />
                    </button>
                  </.action_menu>
                </div>
              </nav>
            </div>
          </div>

          <div class="xamt-rail__pane xamt-rail__pane--members">
            <div class="xamt-rail__section">
              <h3 class="xamt-rail__section-head mongol-text">{gettext("Online")}</h3>
              <ul class="xamt-member-list">
                <li :for={user <- @online_users} class="xamt-member">
                  <.avatar user={user} class="xamt-avatar xamt-avatar--sm" />
                  <span class="xamt-presence is-online"></span>
                  <span class="mongol-text">{user.display_name}</span>
                </li>
              </ul>

              <h3 class="xamt-rail__section-head mongol-text">{gettext("Members")}</h3>
              <ul id="server-members-list" class="xamt-member-list" phx-update="stream">
                <li :for={{dom_id, member} <- @streams.members} id={dom_id} class="xamt-member">
                  <.avatar user={member.user} class="xamt-avatar xamt-avatar--sm" />
                  <span class="xamt-presence"></span>
                  <span class="mongol-text">{display_name(member.user)}</span>
                  <span :if={member.role != "member"} class="xamt-role">
                    {member.role}
                  </span>

                  <.action_menu
                    :if={
                      @admin? and member.role != "owner" and member.user_id != @current_scope.user.id
                    }
                    id={"member-menu-#{member.user_id}"}
                    label={gettext("Member actions")}
                  >
                    <button
                      type="button"
                      class="xamt-icon-btn"
                      phx-click="set_member_role"
                      phx-value-user-id={member.user_id}
                      phx-value-role={if member.role == "admin", do: "member", else: "admin"}
                      aria-label={gettext("Change role")}
                    >
                      <.icon
                        name={if member.role == "admin", do: "hero-arrow-down", else: "hero-arrow-up"}
                        class="size-3"
                      />
                    </button>
                    <button
                      type="button"
                      class="xamt-icon-btn"
                      phx-click="kick_member"
                      phx-value-user-id={member.user_id}
                      data-confirm={gettext("Remove this member?")}
                      aria-label={gettext("Remove member")}
                    >
                      <.icon name="hero-user-minus" class="size-3" />
                    </button>
                  </.action_menu>
                </li>
                <li
                  :if={@has_more_members}
                  id="members-infinite-scroll"
                  phx-hook="InfiniteScroll"
                  data-event="load_more_members"
                  class="xamt-scroll-sentinel"
                >
                </li>
              </ul>
            </div>
          </div>
        </aside>

        <section class="xamt-main">
          <header class="xamt-main__header xamt-mobile-toolbar">
            <button
              type="button"
              id="mobile-nav-menu"
              class="xamt-mobile-nav__btn xamt-mobile-nav__menu"
              phx-click="set_mobile_panel"
              phx-value-panel="channels"
              aria-label={gettext("Servers and channels")}
              aria-expanded={@mobile_panel in [:channels, :servers]}
            >
              <.icon name="hero-bars-3" class="size-5" />
            </button>
            <h2 class="xamt-main__title">
              <span class="xamt-channel-hash">#</span>
              <span class="mongol-text">{@active_channel && @active_channel.name}</span>
            </h2>
            <form
              id="channel-search"
              phx-change="search"
              phx-submit="search"
              class={["xamt-search", @mobile_search? && "is-open"]}
            >
              <button
                type="button"
                id="mobile-nav-search"
                class="xamt-icon-btn xamt-search__toggle"
                phx-click="toggle_mobile_search"
                aria-label={gettext("Search")}
                aria-expanded={@mobile_search?}
              >
                <.icon name="hero-magnifying-glass" class="size-5" />
              </button>
              <label class="xamt-search__field">
                <span class="sr-only">{gettext("Search")}</span>
                <input
                  type="search"
                  name="q"
                  id="channel-search-q"
                  value={@search_q}
                  placeholder={gettext("Search")}
                  class="xamt-input mongol-input"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                />
              </label>
              <button
                :if={@search_results}
                type="button"
                id="clear-search"
                class="xamt-icon-btn"
                phx-click="clear_search"
                aria-label={gettext("Clear search")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </form>
            <button
              type="button"
              id="mobile-nav-members"
              class="xamt-mobile-nav__btn xamt-mobile-nav__members"
              phx-click="set_mobile_panel"
              phx-value-panel="members"
              aria-label={gettext("Members")}
              aria-expanded={@mobile_panel == :members}
            >
              <.icon name="hero-users" class="size-5" />
            </button>
          </header>

          <div class="xamt-chat-window">
            <div class="xamt-messages-region">
              <div :if={@search_results} id="search-results" class="xamt-search-results">
                <p class="xamt-search-results__head mongol-text">
                  {gettext("Search results")}
                </p>
                <p :if={@search_results == []} class="xamt-empty mongol-text">
                  {gettext("No matches.")}
                </p>
                <button
                  :for={message <- @search_results}
                  type="button"
                  id={"search-hit-#{message.id}"}
                  class="xamt-search-hit"
                  phx-click="open_search_result"
                  phx-value-id={message.id}
                  phx-value-channel-id={message.channel_id}
                >
                  <span class="xamt-quote__author mongol-text">{display_name(message.user)}</span>
                  <span :if={message.channel} class="xamt-search-hit__channel mongol-text">
                    <span class="xamt-channel-hash">#</span>
                    {message.channel.name}
                  </span>
                  <span class="xamt-quote__text mongol-text">{Messages.excerpt(message)}</span>
                </button>
              </div>
              <div
                :if={@messages_empty?}
                id="messages-empty"
                class="xamt-empty xamt-empty--messages"
              >
                <span class="xamt-ornament" aria-hidden="true"></span>
                <p class="mongol-text">{gettext("No messages yet. Write the first one.")}</p>
              </div>

              <div
                id="message-list"
                class="xamt-messages"
                phx-update="stream"
                phx-hook="MessageList"
                data-highlight={@highlight_id}
                data-channel-id={@active_channel && @active_channel.id}
              >
                <div
                  :if={@has_more_messages}
                  id="messages-infinite-scroll"
                  phx-hook="InfiniteScroll"
                  data-event="load_older"
                  class="xamt-scroll-sentinel"
                >
                </div>

                <article
                  :for={{dom_id, message} <- @streams.messages}
                  id={dom_id}
                  class={[
                    "xamt-message group",
                    mentioned?(message, @current_scope.user) && "xamt-message--mentioned",
                    @editing_message_id == message.id && "xamt-message--editing",
                    deleted?(message) && "xamt-message--deleted"
                  ]}
                  data-message-id={message.id}
                  data-inserted-at={DateTime.to_iso8601(message.inserted_at)}
                >
                  <.avatar user={message.user} class="xamt-message__avatar" />
                  <%= if deleted?(message) do %>
                    <div class="xamt-message__body">
                      <header class="xamt-message__meta">
                        <strong class="mongol-text">{display_name(message.user)}</strong>
                        <time class="xamt-message__time">{format_time(message.inserted_at)}</time>
                      </header>
                      <div
                        id={"msg-tombstone-#{message.id}"}
                        class="xamt-message__tombstone mongol-text"
                      >
                        <.icon name="hero-trash" class="size-4" />
                        {gettext("This message was deleted")}
                      </div>
                    </div>
                  <% else %>
                    <div class="xamt-message__body">
                      <button
                        :if={message.reply_to}
                        type="button"
                        class="xamt-quote"
                        phx-click={
                          JS.dispatch("xamt:highlight",
                            detail: %{target_id: "messages-#{message.reply_to_id}"}
                          )
                        }
                        title={gettext("Jump to the quoted message")}
                      >
                        <span class="xamt-quote__mark" aria-hidden="true">↳</span>
                        <span class="xamt-quote__author mongol-text">
                          {display_name(message.reply_to.user)}
                        </span>
                        <span class="xamt-quote__text mongol-text">
                          <%= if deleted?(message.reply_to) do %>
                            {gettext("This message was deleted")}
                          <% else %>
                            {Messages.excerpt(message.reply_to)}
                          <% end %>
                        </span>
                      </button>
                      <header class="xamt-message__meta">
                        <strong class="mongol-text">{display_name(message.user)}</strong>
                        <span :if={edited?(message)} class="xamt-message__edited">
                          {gettext("edited")}
                        </span>
                        <time class="xamt-message__time">{format_time(message.inserted_at)}</time>
                      </header>
                      <div
                        id={"msg-content-#{message.id}"}
                        class="xamt-message__content mongol-text"
                      >
                        {raw(safe_html(message, @current_scope.user.id))}
                        <%= if preview = link_preview(message) do %>
                          <a
                            id={"msg-preview-#{message.id}"}
                            href={preview["url"]}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="xamt-link-preview"
                          >
                            <img
                              :if={preview["image"]}
                              src={preview["image"]}
                              alt={preview["title"] || ""}
                              class="xamt-link-preview__img"
                              loading="lazy"
                              referrerpolicy="no-referrer"
                            />
                            <div class="xamt-link-preview__body">
                              <strong
                                :if={preview["title"]}
                                class="xamt-link-preview__title mongol-text"
                              >
                                {preview["title"]}
                              </strong>
                              <p
                                :if={preview["description"]}
                                class="xamt-link-preview__desc mongol-text"
                              >
                                {preview["description"]}
                              </p>
                            </div>
                          </a>
                        <% end %>
                      </div>
                      <div class="xamt-reactions">
                        <button
                          :for={{emoji, user_ids} <- reactions_for(@reactions, message.id)}
                          type="button"
                          class={[
                            "xamt-reaction",
                            @current_scope.user.id in user_ids && "is-mine"
                          ]}
                          phx-click="toggle_reaction"
                          phx-value-id={message.id}
                          phx-value-emoji={emoji}
                        >
                          <span class="xamt-reaction__emoji">{emoji}</span>
                          <span class="xamt-reaction__count">{length(user_ids)}</span>
                        </button>

                        <div class="xamt-reaction-picker">
                          <button
                            :for={emoji <- Reaction.emojis()}
                            type="button"
                            class="xamt-reaction xamt-reaction--add"
                            phx-click="toggle_reaction"
                            phx-value-id={message.id}
                            phx-value-emoji={emoji}
                            aria-label={emoji}
                          >
                            {emoji}
                          </button>
                        </div>
                      </div>

                      <div class="xamt-message__actions">
                        <button
                          type="button"
                          id={"reply-message-#{message.id}"}
                          phx-click="reply_message"
                          phx-value-id={message.id}
                        >
                          {gettext("Reply")}
                        </button>
                        <button
                          :if={message.user_id == @current_scope.user.id}
                          type="button"
                          id={"edit-message-#{message.id}"}
                          phx-click="edit_message"
                          phx-value-id={message.id}
                        >
                          <.icon name="hero-pencil" class="size-4" />
                          {gettext("Edit")}
                        </button>
                        <button
                          :if={message.user_id == @current_scope.user.id}
                          type="button"
                          id={"delete-message-#{message.id}"}
                          phx-click="delete_message"
                          phx-value-id={message.id}
                          data-confirm={gettext("Delete this message?")}
                        >
                          <.icon name="hero-trash" class="size-4" />
                          {gettext("Delete")}
                        </button>
                      </div>
                    </div>
                  <% end %>
                </article>
              </div>

              <%!-- Toggled by the MessageList hook; kept out of LiveView patches --%>
              <button
                type="button"
                id="jump-latest"
                class="xamt-jump-latest mongol-text"
                phx-update="ignore"
              >
                {gettext("New messages")}
              </button>
            </div>

            <div :if={map_size(@typing_users) > 0} class="xamt-typing">
              {typing_label(@typing_users)}
            </div>

            <div
              id="message-composer-wrap"
              class="xamt-composer-wrap"
              phx-drop-target={@uploads.media.ref}
              data-has-uploads={to_string(@uploads.media.entries != [])}
              data-submit-event={if @editing_message_id, do: "update_message", else: "send_message"}
              data-editing-id={@editing_message_id}
              data-channel-id={@active_channel && @active_channel.id}
              data-reply-to-id={@replying_to && @replying_to.id}
            >
              <div :if={@replying_to} id="reply-preview" class="xamt-reply-bar">
                <span class="xamt-quote__mark" aria-hidden="true">↳</span>
                <span class="xamt-quote__author mongol-text">
                  {display_name(@replying_to.user)}
                </span>
                <span class="xamt-quote__text mongol-text">{Messages.excerpt(@replying_to, 40)}</span>
                <button
                  type="button"
                  id="cancel-reply"
                  class="xamt-icon-btn"
                  phx-click="cancel_reply"
                  aria-label={gettext("Cancel reply")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
              <section
                :if={@uploads.media.entries != []}
                id="media-upload-preview"
                class="xamt-upload-preview"
              >
                <div :for={entry <- @uploads.media.entries} class="xamt-upload-preview__item">
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

              <div id="message-composer" phx-hook="MessageComposer" phx-update="ignore">
                <div class="xamt-composer__editor" id="composer-editor-host"></div>
              </div>

              <div id="composer-toolbar" class="xamt-composer__toolbar">
                <label
                  for={@uploads.media.ref}
                  class="xamt-btn xamt-btn--soft"
                  title={gettext("Upload Media")}
                >
                  <.icon name="hero-photo" class="size-5" />
                </label>
                <button
                  :if={@editing_message_id}
                  type="button"
                  id="composer-cancel-edit"
                  class="xamt-btn xamt-btn--sm"
                  phx-click="cancel_edit"
                >
                  {gettext("Cancel")}
                </button>
                <button
                  type="button"
                  id="composer-send"
                  class="xamt-btn xamt-btn--primary mongol-text"
                  data-composer-send
                >
                  {if @editing_message_id, do: gettext("Save"), else: gettext("Send")}
                </button>
              </div>
            </div>
          </div>
        </section>
      </div>

      <.server_menu_overlay
        :if={@show_server_menu && @active_channel}
        server={@server}
        active_channel={@active_channel}
      />

      <.server_overlay
        :if={@admin? and @active_channel}
        live_action={@live_action}
        server={@server}
        active_channel={@active_channel}
        channel_form={@channel_form}
        editing_channel={@editing_channel}
        server_form={@server_form}
        invites={@invites}
      />
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
    |> assign(:messages_empty?, messages == [])
    |> assign(:reactions, Messages.reaction_summary(Enum.map(messages, & &1.id)))
    |> stream(:messages, messages, reset: true)
  end

  defp merge_reactions(socket, messages) do
    summary = Messages.reaction_summary(Enum.map(messages, & &1.id))
    assign(socket, :reactions, Map.merge(socket.assigns.reactions, summary))
  end

  defp reactions_for(reactions, message_id) do
    reactions
    |> Map.get(message_id, %{})
    |> Enum.sort_by(fn {emoji, _users} -> Enum.find_index(Reaction.emojis(), &(&1 == emoji)) end)
  end

  defp maybe_done_loading(socket, _event, true), do: socket

  defp maybe_done_loading(socket, event, false) do
    done_loading(socket, event)
  end

  defp done_loading(socket, event) do
    push_event(socket, "infinite_scroll:done", %{event: event})
  end

  defp maybe_scroll_to_highlight(socket, %{"highlight" => id})
       when is_binary(id) and id != "" do
    push_event(socket, "messages:scroll_to", %{id: id})
  end

  defp maybe_scroll_to_highlight(socket, _), do: socket

  defp maybe_push_composer_reset(socket, _params) do
    push_event(socket, "composer:clear", %{})
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp action_menu(assigns) do
    ~H"""
    <details id={@id} class="xamt-menu">
      <summary class="xamt-icon-btn" aria-label={@label}>
        <.icon name="hero-ellipsis-vertical" class="size-4" />
      </summary>
      <div class="xamt-menu__list">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :server, :map, required: true
  attr :active_channel, :map, required: true

  defp server_menu_overlay(assigns) do
    ~H"""
    <.drawer
      id="server-menu-drawer"
      class="xamt-sheet--menu"
      show
      on_cancel={JS.push("close_server_menu")}
    >
      <div class="xamt-sheet-form xamt-server-menu-sheet">
        <h2 id="server-menu-title" class="xamt-section-title mongol-text">{@server.name}</h2>
        <nav class="xamt-server-menu-sheet__nav" aria-labelledby="server-menu-title">
          <.link
            id="server-menu-new-channel"
            patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/new"}
            class="xamt-btn xamt-btn--soft mongol-text"
          >
            {gettext("Create channel")}
          </.link>
          <.link
            id="server-menu-settings"
            patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/settings"}
            class="xamt-btn mongol-text"
          >
            {gettext("Server settings")}
          </.link>
        </nav>
      </div>
    </.drawer>
    """
  end

  attr :live_action, :atom, required: true
  attr :server, :map, required: true
  attr :active_channel, :map, required: true
  attr :channel_form, :map, required: true
  attr :editing_channel, :map
  attr :server_form, :map, required: true
  attr :invites, :list, required: true

  defp server_overlay(assigns) do
    ~H"""
    <.drawer
      :if={@live_action in [:new_channel, :edit_channel, :edit_server]}
      id="server-drawer"
      show
      on_cancel={JS.patch(~p"/servers/#{@server.slug}/#{@active_channel.slug}")}
    >
      <.channel_sheet
        :if={@live_action == :new_channel}
        id="create-channel-form"
        form={@channel_form}
        title={gettext("Create channel")}
        submit_label={gettext("Create")}
        return_to={~p"/servers/#{@server.slug}/#{@active_channel.slug}"}
      />
      <.channel_sheet
        :if={@live_action == :edit_channel and @editing_channel}
        id="edit-channel-form"
        form={@channel_form}
        title={gettext("Rename channel")}
        submit_label={gettext("Save")}
        name_id="edit-channel-name"
        return_to={~p"/servers/#{@server.slug}/#{@active_channel.slug}"}
      />
      <.server_settings
        :if={@live_action == :edit_server}
        server={@server}
        form={@server_form}
        invites={@invites}
      />
    </.drawer>
    """
  end

  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :title, :string, required: true
  attr :submit_label, :string, required: true
  attr :return_to, :string, required: true
  attr :name_id, :string, default: "channel_name"

  defp channel_sheet(assigns) do
    ~H"""
    <div class="xamt-sheet-form">
      <h2 id={"#{@id}-title"} class="xamt-section-title mongol-text">{@title}</h2>
      <.form
        for={@form}
        id={@id}
        phx-submit="save_channel"
        novalidate
        class="xamt-form xamt-form--vertical"
      >
        <.input
          field={@form[:name]}
          id={@name_id}
          label={gettext("Channel name")}
          phx-hook="MongolianIME"
          class="xamt-input mongol-input"
          autocomplete="off"
        />
        <div class="xamt-form__actions">
          <button
            type="submit"
            id={"#{@id}-submit"}
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            {@submit_label}
          </button>
          <.link patch={@return_to} id={"#{@id}-cancel"} class="xamt-btn mongol-text">
            {gettext("Cancel")}
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  attr :server, :map, required: true
  attr :form, :map, required: true
  attr :invites, :list, required: true

  defp server_settings(assigns) do
    ~H"""
    <div id="server-settings" class="xamt-sheet-form">
      <h2 class="xamt-section-title mongol-text">{gettext("Server settings")}</h2>

      <.form
        for={@form}
        id="server-settings-form"
        phx-submit="save_server"
        class="xamt-form xamt-form--vertical"
      >
        <.input
          field={@form[:name]}
          id="server-settings-name"
          label={gettext("Name")}
          phx-hook="MongolianIME"
          class="xamt-input mongol-input"
          autocomplete="off"
        />
        <.input
          field={@form[:description]}
          id="server-settings-description"
          type="textarea"
          label={gettext("Description")}
          phx-hook="MongolianIME"
          class="xamt-textarea mongol-input"
        />
        <div class="xamt-field">
          <label>
            <span class="xamt-field__label mongol-text">{gettext("Visibility")}</span>
            <select name={@form[:visibility].name} id="server-settings-visibility" class="xamt-select">
              <option value="private" selected={@server.visibility == "private"}>
                {gettext("Private — invite only")}
              </option>
              <option value="public" selected={@server.visibility == "public"}>
                {gettext("Public — anyone can find and join")}
              </option>
            </select>
          </label>
        </div>
        <div class="xamt-form__actions">
          <button
            type="submit"
            id="server-settings-save"
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            {gettext("Save")}
          </button>
        </div>
      </.form>

      <div class="xamt-rail__section-head">
        <span class="mongol-text">{gettext("Invites")}</span>
        <button
          type="button"
          id="create-invite"
          class="xamt-icon-btn"
          phx-click="create_invite"
          aria-label={gettext("Create invite")}
        >
          +
        </button>
      </div>

      <ul class="xamt-invite-list">
        <li :for={invite <- @invites} class="xamt-invite">
          <code>/invite/{invite.code}</code>
          <span :if={invite.max_uses} class="xamt-invite__uses">{invite.uses}/{invite.max_uses}</span>
          <button
            type="button"
            id={"copy-invite-#{invite.id}"}
            class="xamt-icon-btn"
            phx-click={JS.dispatch("xamt:copy")}
            data-copy={url(~p"/invite/#{invite.code}")}
            data-copied={gettext("Copied")}
            data-copy-failed={gettext("Could not copy")}
            aria-label={gettext("Copy invite link")}
          >
            <.icon name="hero-clipboard" class="size-3" />
          </button>
          <button
            type="button"
            class="xamt-icon-btn"
            phx-click="delete_invite"
            phx-value-id={invite.id}
            aria-label={gettext("Delete invite")}
          >
            <.icon name="hero-x-mark" class="size-3" />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp refresh_channels(socket) do
    assign(socket, :channels, Channels.list_channels(socket.assigns.server.id))
  end

  defp overlay_return_path(socket) do
    case socket.assigns.active_channel do
      %{slug: slug} -> ~p"/servers/#{socket.assigns.server.slug}/#{slug}"
      _ -> ~p"/servers/#{socket.assigns.server.slug}"
    end
  end

  defp channel_path(socket, channel) do
    ~p"/servers/#{socket.assigns.server.slug}/#{channel.slug}"
  end

  defp maybe_switch_channel(socket, channel_slug, params) do
    current = socket.assigns.active_channel

    socket =
      if current && current.slug == channel_slug do
        socket
        |> assign(:highlight_id, Map.get(params, "highlight"))
        |> maybe_scroll_to_highlight(params)
      else
        switch_channel(socket, channel_slug, params)
      end

    assign(socket, :mobile_panel, :messages)
  end

  defp switch_channel(socket, channel_slug, params) do
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

    socket
    |> assign(:active_channel, channel)
    |> assign(:online_users, list_online(channel))
    |> assign(:typing_users, %{})
    |> assign(:editing_message_id, nil)
    |> assign(:replying_to, nil)
    |> assign(:mobile_panel, :messages)
    |> assign(:search_q, "")
    |> assign(:search_results, nil)
    |> assign(:highlight_id, Map.get(params, "highlight"))
    |> assign_messages(messages)
    |> maybe_push_composer_reset(params)
    |> maybe_scroll_to_highlight(params)
  end

  defp apply_action(socket, :new_channel, _params) do
    if socket.assigns.admin? do
      assign(socket,
        show_server_menu: false,
        editing_channel: nil,
        channel_form: to_form(Channels.change_channel(%Channel{}), as: :channel)
      )
    else
      deny_overlay(socket)
    end
  end

  defp apply_action(socket, :edit_channel, %{"edit_slug" => slug}) do
    channel = Enum.find(socket.assigns.channels, &(&1.slug == slug))

    cond do
      not socket.assigns.admin? ->
        deny_overlay(socket)

      is_nil(channel) ->
        socket
        |> put_flash(:error, gettext("Channel not found"))
        |> push_patch(to: overlay_return_path(socket))

      true ->
        assign(socket,
          show_server_menu: false,
          editing_channel: channel,
          channel_form: to_form(Channels.change_channel(channel), as: :channel)
        )
    end
  end

  defp apply_action(socket, :edit_server, _params) do
    if socket.assigns.admin? do
      socket
      |> assign(:show_server_menu, false)
      |> assign(:server_form, to_form(Servers.change_server(socket.assigns.server), as: :server))
    else
      deny_overlay(socket)
    end
  end

  defp apply_action(socket, :show, _params) do
    assign(socket, :editing_channel, nil)
  end

  defp apply_action(socket, _action, _params), do: socket

  defp deny_overlay(socket) do
    socket
    |> put_flash(:error, gettext("Unauthorized"))
    |> push_patch(to: overlay_return_path(socket))
  end

  defp save_channel(socket, :new_channel, params) do
    server = socket.assigns.server

    case Channels.create_channel(socket.assigns.current_scope, server, params) do
      {:ok, channel} ->
        if connected?(socket), do: subscribe_channel(channel)

        {:noreply,
         socket
         |> assign(:channels, Channels.list_channels(server.id))
         |> put_flash(:info, gettext("Channel created"))
         |> push_patch(to: ~p"/servers/#{server.slug}/#{channel.slug}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :channel_form, to_form(changeset, as: :channel))}
    end
  end

  defp save_channel(socket, :edit_channel, params) do
    channel = socket.assigns.editing_channel

    if is_nil(channel) do
      {:noreply, socket}
    else
      case Channels.update_channel(socket.assigns.current_scope, channel.id, params) do
        {:ok, updated} ->
          socket =
            socket
            |> refresh_channels()
            |> maybe_replace_active_channel(updated)

          {:noreply, push_patch(socket, to: overlay_return_path(socket))}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

        {:error, changeset} ->
          {:noreply, assign(socket, :channel_form, to_form(changeset, as: :channel))}
      end
    end
  end

  defp save_channel(socket, _action, _params), do: {:noreply, socket}

  defp maybe_replace_active_channel(socket, channel) do
    active = socket.assigns.active_channel

    if active && active.id == channel.id do
      assign(socket, :active_channel, channel)
    else
      socket
    end
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

  defp own_active_message?(socket, message) do
    message.user_id == socket.assigns.current_scope.user.id and
      active_channel_message?(socket, message)
  end

  defp restream_message(socket, id) when is_binary(id) do
    stream_insert(socket, :messages, Messages.get_message!(id))
  rescue
    Ecto.NoResultsError -> socket
  end

  defp restream_message(socket, _), do: socket

  defp maybe_cancel_edit(socket, message_id) do
    if socket.assigns.editing_message_id == message_id do
      socket
      |> assign(:editing_message_id, nil)
      |> push_event("composer:clear", %{})
    else
      socket
    end
  end

  defp deleted?(%{deleted_at: %DateTime{}}), do: true
  defp deleted?(_), do: false

  defp channel_topic(%Channel{id: id}), do: "xamt:channel:#{id}"
  defp channel_topic(nil), do: "xamt:channel:none"

  defp list_online(nil), do: []

  defp list_online(channel) do
    Presence.list(channel_topic(channel))
    |> Enum.map(fn {_id, %{metas: metas}} ->
      meta = List.first(metas) || %{}

      %{
        display_name: presence_meta(meta, :display_name) || presence_meta(meta, :username) || "?",
        username: presence_meta(meta, :username),
        avatar: presence_meta(meta, :avatar)
      }
    end)
  end

  defp presence_meta(meta, key) when is_atom(key) do
    Map.get(meta, key) || Map.get(meta, Atom.to_string(key))
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}) when is_binary(name), do: name
  defp display_name(%{email: email}), do: email
  defp display_name(_), do: "?"

  defp server_initial(name) when is_binary(name) do
    name |> String.trim() |> String.first() || "?"
  end

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  defp edited?(%{inserted_at: a, updated_at: b}) when not is_nil(a) and not is_nil(b) do
    DateTime.compare(b, a) == :gt
  end

  defp edited?(_), do: false

  defp mentioned?(%{mentioned_user_ids: ids}, %{id: user_id})
       when is_list(ids) and is_binary(user_id),
       do: user_id in ids

  defp mentioned?(_, _), do: false

  defp link_preview(%{link_preview: preview})
       when is_map(preview) and map_size(preview) > 0,
       do: preview

  defp link_preview(_), do: nil

  defp mention_search_row(%{user: user}) do
    %{
      id: user.id,
      username: user.username,
      display_name: display_name(user),
      avatar: user.avatar
    }
  end

  defp safe_html(message, current_user_id)

  defp safe_html(%{content_html: html}, current_user_id)
       when is_binary(html) and html != "",
       do: decorate_own_mentions(html, current_user_id)

  defp safe_html(%{content: %{"html" => html}}, current_user_id) when is_binary(html),
    do: decorate_own_mentions(html, current_user_id)

  defp safe_html(%{content: content}, _current_user_id) when is_map(content),
    do: Phoenix.HTML.html_escape(inspect(content))

  defp safe_html(_, _), do: ""

  defp decorate_own_mentions(html, user_id) when is_binary(html) and is_binary(user_id) do
    String.replace(
      html,
      ~s(data-mention-id="#{user_id}"),
      ~s(data-mention-id="#{user_id}" data-you="true")
    )
  end

  defp decorate_own_mentions(html, _), do: html

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
    |> XamtWeb.Uploads.consume_images(:media)
    |> Enum.map(fn url -> ~s(<div class="editor-image"><img src="#{url}" /></div>) end)
    |> Enum.join()
  end
end
