defmodule XamtWeb.ServerLive do
  use XamtWeb, :live_view

  alias Xamt.{Accounts, Channels, Messages, Servers}
  alias Xamt.Channels.Channel
  alias Xamt.Servers.Permissions
  alias Xamt.Servers.Server
  alias XamtWeb.Presence
  alias XamtWeb.TypingTracker

  import XamtWeb.ServerLive.Components
  import XamtWeb.ServerLive.Helpers
  alias XamtWeb.ServerLive.Helpers

  @message_page_size 50
  @member_page_size 50
  @mobile_panels ~w(servers channels messages members)

  @impl true
  def mount(%{"server_slug" => server_slug} = params, _session, socket) do
    socket = assign(socket, :timezone_offset, connect_timezone_offset(socket))
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

    current_member = Servers.get_member(server.id, scope.user.id)
    can_view? = can_view_channel?(current_member)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Xamt.PubSub, Servers.server_topic(server.id))

      if can_view? do
        Enum.each(channels, &subscribe_channel/1)

        if channel do
          Presence.track_user(self(), channel_topic(channel), scope.user)
          subscribe_typing(channel)
        end
      end
    end

    messages = visible_messages(scope, channel)

    unread_ids = Channels.get_unread_channel_ids(scope.user.id, server.id)

    socket =
      socket
      |> assign(:page_title, server.name)
      |> assign(:server, server)
      |> assign(:member?, true)
      |> assign(:current_member, current_member)
      |> assign(:channels, channels)
      |> assign(:members_offset, @member_page_size)
      |> assign(:has_more_members, length(members) == @member_page_size)
      |> stream(:members, members)
      |> assign(:active_channel, channel)
      |> assign(:online_users, list_online(channel))
      |> assign(:typing_users, list_typists(channel, scope.user.id))
      |> assign(:editing_message_id, nil)
      |> assign(:replying_to, nil)
      |> assign(:deleting_message, nil)
      |> assign(:composer_mode, :text)
      |> assign(:poll_form, empty_poll_form())
      |> assign(:poll_details, nil)
      |> assign(:channel_form, to_form(Channels.change_channel(%Channel{}), as: :channel))
      |> assign_member_permissions(current_member)
      |> assign(:editing_channel, nil)
      |> assign(:show_server_menu, false)
      |> assign(:show_status_picker, false)
      |> assign(:show_pinned_drawer, false)
      |> assign(:pinned_messages, [])
      |> assign(:mobile_panel, :messages)
      |> assign(:mobile_search?, false)
      |> assign(:unread_channels, MapSet.new(unread_ids))
      |> assign(:search_q, "")
      |> assign(:search_results, nil)
      |> assign(:highlight_id, Map.get(params, "highlight"))
      |> assign(:lightbox_images, nil)
      |> assign(:lightbox_index, 0)
      |> assign_messages(messages)
      |> allow_upload(:media,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 10,
        max_file_size: 10_000_000,
        auto_upload: true
      )
      |> allow_upload(:audio,
        accept: ~w(audio/* video/webm video/mp4),
        max_entries: 1,
        max_file_size: 10_485_760,
        # Remote nginx → Tailscale hops need longer than the 10s default
        # or a stalled chunk leaves entries in-progress and crashes on consume.
        auto_upload: true,
        chunk_timeout: 60_000
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

  def handle_event(_event, _params, %{assigns: %{member?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_audio", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("send_audio", _params, socket) do
    channel = socket.assigns.active_channel

    cond do
      is_nil(channel) ->
        voice_failed(socket, gettext("Could not send voice message"))

      not socket.assigns.can_send_messages? ->
        voice_failed(socket, gettext("Unauthorized"))

      true ->
        send_audio_message(socket, channel)
    end
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

    cond do
      is_nil(channel) ->
        {:noreply, put_flash(socket, :error, gettext("Could not send message"))}

      not socket.assigns.can_send_messages? ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

      Enum.any?(socket.assigns.uploads.media.entries, &(not &1.done?)) ->
        {:noreply, put_flash(socket, :error, gettext("Please wait for uploads to finish"))}

      true ->
        images = XamtWeb.Uploads.consume_gallery_images(socket, :media)
        attrs = build_message_attrs(params, images, socket.assigns.replying_to)

        case Messages.create_message(scope, channel.id, attrs) do
          {:ok, _message} ->
            {:noreply,
             socket
             |> assign(:editing_message_id, nil)
             |> assign(:replying_to, nil)
             |> push_event("composer:clear", %{})}

          {:error, :rate_limited} ->
            {:noreply, put_flash(socket, :error, gettext("Messages sent too fast"))}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

          {:error, :invalid_reply} ->
            {:noreply, put_flash(socket, :error, gettext("Could not send message"))}

          {:error, :too_long} ->
            {:noreply, put_flash(socket, :error, gettext("Message is too long"))}

          {:error, :invalid_content} ->
            {:noreply, put_flash(socket, :error, gettext("Could not send message"))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not send message"))}
        end
    end
  end

  def handle_event("open_poll_composer", _params, socket) do
    {:noreply,
     socket
     |> assign(:composer_mode, :poll)
     |> assign(:poll_form, empty_poll_form())
     |> assign(:editing_message_id, nil)}
  end

  def handle_event("cancel_poll_composer", _params, socket) do
    {:noreply, socket |> assign(:composer_mode, :text) |> assign(:poll_form, empty_poll_form())}
  end

  def handle_event("validate_poll", %{"poll" => params}, socket) do
    {:noreply, assign(socket, :poll_form, poll_form(normalize_poll_params(params)))}
  end

  def handle_event("add_poll_option", _params, socket) do
    params = poll_form_params(socket)
    options = poll_options(params)

    socket =
      if length(options) < 10 do
        assign(socket, :poll_form, poll_form(Map.put(params, "options", options ++ [""])))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("remove_poll_option", %{"index" => index}, socket) do
    params = poll_form_params(socket)
    options = poll_options(params)
    {idx, _} = Integer.parse(to_string(index))

    socket =
      if idx >= 2 and idx < length(options) do
        assign(
          socket,
          :poll_form,
          poll_form(Map.put(params, "options", List.delete_at(options, idx)))
        )
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("send_poll", %{"poll" => poll_params}, socket) do
    scope = socket.assigns.current_scope
    channel = socket.assigns.active_channel
    poll_params = normalize_poll_params(poll_params)

    cond do
      is_nil(channel) ->
        {:noreply, put_flash(socket, :error, gettext("Could not send poll"))}

      not socket.assigns.can_send_messages? ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

      true ->
        attrs = %{
          "question" => poll_params["question"],
          "options" => poll_params["options"],
          "allow_multiple" => poll_params["allow_multiple"],
          "results_open" => poll_params["results_open"],
          "reply_to_id" => socket.assigns.replying_to && socket.assigns.replying_to.id
        }

        case Messages.create_poll_message(scope, channel.id, attrs) do
          {:ok, _message} ->
            {:noreply,
             socket
             |> assign(:composer_mode, :text)
             |> assign(:poll_form, empty_poll_form())
             |> assign(:replying_to, nil)}

          {:error, :rate_limited} ->
            {:noreply, put_flash(socket, :error, gettext("Messages sent too fast"))}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

          {:error, :invalid_poll} ->
            {:noreply,
             put_flash(socket, :error, gettext("Poll needs a question and 2–10 options"))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not send poll"))}
        end
    end
  end

  def handle_event("cast_vote", %{"poll-id" => poll_id, "option-id" => option_id}, socket) do
    case Messages.toggle_vote(socket.assigns.current_scope, poll_id, option_id) do
      {:ok, _payload} ->
        socket =
          case socket.assigns.poll_details do
            %{id: ^poll_id} -> refresh_poll_details(socket, poll_id)
            _ -> socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not cast vote"))}
    end
  end

  def handle_event("open_poll_details", %{"poll-id" => poll_id}, socket) do
    case Messages.get_poll_details(socket.assigns.current_scope, poll_id) do
      {:ok, details} ->
        {:noreply, assign(socket, :poll_details, details)}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Only the poll author can see details"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not load poll details"))}
    end
  end

  def handle_event("close_poll_details", _params, socket) do
    {:noreply, assign(socket, :poll_details, nil)}
  end

  def handle_event("edit_message", %{"id" => id}, socket) do
    previous_id = socket.assigns.editing_message_id

    with {:ok, message} <- Messages.get_message_for_user(socket.assigns.current_scope, id),
         true <- own_active_message?(socket, message) and is_nil(message.deleted_at) do
      html = message.content_html || ""

      {:noreply,
       socket
       |> assign(:editing_message_id, id)
       |> assign(:replying_to, nil)
       |> restream_message(previous_id)
       |> stream_message(message)
       |> push_event("populate_composer", %{html: html})}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("reply_message", %{"id" => id}, socket) do
    with {:ok, message} <- Messages.get_message_for_user(socket.assigns.current_scope, id),
         true <- active_channel_message?(socket, message) do
      {:noreply,
       socket
       |> assign(:replying_to, message)
       |> assign(:editing_message_id, nil)
       |> assign(:mobile_panel, :messages)
       |> push_event("composer:focus", %{})}
    else
      _ ->
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
        new_images = XamtWeb.Uploads.consume_gallery_images(socket, :media)

        existing_images =
          case Messages.get_message_for_user(scope, id) do
            {:ok, message} -> gallery_images(message) || []
            _ -> []
          end

        images = Enum.take(existing_images ++ new_images, 10)
        attrs = build_message_attrs(params, images, nil)

        case Messages.update_message(scope, id, attrs) do
          {:ok, _message} ->
            {:noreply,
             socket
             |> assign(:editing_message_id, nil)
             |> push_event("composer:clear", %{})}

          {:error, :too_long} ->
            {:noreply, put_flash(socket, :error, gettext("Message is too long"))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not update message"))}
        end
    end
  end

  def handle_event("open_lightbox", %{"msg-id" => msg_id, "index" => index_str}, socket) do
    with {:ok, message} <- Messages.get_message_for_user(socket.assigns.current_scope, msg_id),
         images when is_list(images) and images != [] <- gallery_images(message) do
      index =
        case Integer.parse(to_string(index_str)) do
          {n, _} -> max(0, min(n, length(images) - 1))
          :error -> 0
        end

      {:noreply,
       socket
       |> assign(:lightbox_images, images)
       |> assign(:lightbox_index, index)}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_lightbox", _, socket) do
    {:noreply, assign(socket, lightbox_images: nil, lightbox_index: 0)}
  end

  def handle_event("lightbox_prev", _, socket) do
    new_index = max(0, socket.assigns.lightbox_index - 1)
    {:noreply, assign(socket, lightbox_index: new_index)}
  end

  def handle_event("lightbox_next", _, socket) do
    images = socket.assigns.lightbox_images || []
    max_index = max(0, length(images) - 1)
    new_index = min(max_index, socket.assigns.lightbox_index + 1)
    {:noreply, assign(socket, lightbox_index: new_index)}
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    handle_event("close_lightbox", %{}, socket)
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    handle_event("lightbox_prev", %{}, socket)
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    handle_event("lightbox_next", %{}, socket)
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

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
    case Messages.get_message_for_user(socket.assigns.current_scope, id) do
      {:ok, message} ->
        delete_message_action(socket, id, message)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("confirm_delete_message", %{"audit" => audit}, socket) do
    id = audit["id"]
    reason = audit["reason"]

    socket
    |> assign(:deleting_message, nil)
    |> delete_current_message(id, reason)
  end

  def handle_event("cancel_delete_message", _params, socket) do
    {:noreply, assign(socket, :deleting_message, nil)}
  end

  def handle_event("toggle_pinned_drawer", _params, socket) do
    case socket.assigns.active_channel do
      nil ->
        {:noreply, socket}

      channel ->
        if socket.assigns.show_pinned_drawer do
          {:noreply, assign(socket, show_pinned_drawer: false)}
        else
          messages = visible_pins(socket.assigns.current_scope, channel)

          {:noreply, assign(socket, show_pinned_drawer: true, pinned_messages: messages)}
        end
    end
  end

  def handle_event("close_pinned_drawer", _params, socket) do
    {:noreply, assign(socket, show_pinned_drawer: false)}
  end

  def handle_event("toggle_pin", %{"id" => id}, socket) do
    case Messages.toggle_pin_message(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, :deleted} ->
        {:noreply, put_flash(socket, :error, gettext("Message was deleted"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update pin"))}
    end
  end

  def handle_event("load_older", _params, socket) do
    channel = socket.assigns.active_channel
    oldest_id = socket.assigns[:oldest_message_id]

    if is_nil(channel) or not socket.assigns.has_more_messages or is_nil(oldest_id) do
      {:noreply, done_loading(socket, "load_older")}
    else
      messages =
        visible_messages(socket.assigns.current_scope, channel, before_id: oldest_id)

      socket =
        case messages do
          [first | _] = msgs ->
            offset = socket.assigns.timezone_offset
            {grouped, page_last, page_flags} = process_message_grouping(msgs, offset)

            skip_date =
              case socket.assigns[:oldest_message_info] do
                %{time: %DateTime{} = time} -> local_date(time, offset)
                _ -> nil
              end

            items = with_date_dividers(grouped, offset, skip_trailing_date: skip_date)

            socket
            |> assign(
              :header_flags,
              Map.merge(socket.assigns.header_flags, page_flags)
            )
            |> maybe_hide_continuation_header(page_last)
            |> assign(:oldest_message_id, first.id)
            |> assign(:oldest_message_info, oldest_message_info(grouped))
            |> assign(:has_more_messages, length(msgs) >= @message_page_size)
            |> merge_reactions(msgs)
            |> merge_polls(msgs)
            |> stream(:messages, items, at: 0)
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
    {:noreply, assign(socket, :show_server_menu, !socket.assigns.show_server_menu)}
  end

  def handle_event("close_server_menu", _params, socket) do
    {:noreply, assign(socket, :show_server_menu, false)}
  end

  def handle_event("open_status_picker", _params, socket) do
    {:noreply, assign(socket, :show_status_picker, true)}
  end

  def handle_event("close_status_picker", _params, socket) do
    {:noreply, assign(socket, :show_status_picker, false)}
  end

  def handle_event("set_status", %{"emoji" => emoji, "text" => text}, socket) do
    apply_custom_status(socket, %{status_emoji: emoji, status_text: text})
  end

  def handle_event("clear_status", _params, socket) do
    apply_custom_status(socket, %{status_emoji: nil, status_text: nil})
  end

  def handle_event("save_custom_status", params, socket) do
    apply_custom_status(socket, %{
      status_emoji: Map.get(params, "emoji"),
      status_text: Map.get(params, "text")
    })
  end

  def handle_event("save_channel", %{"channel" => params}, socket) do
    save_channel(socket, socket.assigns.live_action, params)
  end

  def handle_event("save_channel", params, socket) when is_map(params) do
    save_channel(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete_channel", %{"id" => id}, socket) do
    case Channels.delete_channel(socket.assigns.current_scope, id) do
      {:ok, _channel} ->
        {:noreply, socket}

      {:error, :last_channel} ->
        {:noreply, put_flash(socket, :error, gettext("A server needs at least one channel"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("move_channel", %{"id" => id, "direction" => direction}, socket) do
    direction = if direction == "up", do: :up, else: :down

    case Channels.move_channel(socket.assigns.current_scope, id, direction) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("kick_member", %{"user-id" => user_id}, socket) do
    server = socket.assigns.server

    case Servers.kick_member(socket.assigns.current_scope, server.id, user_id) do
      {:ok, _member} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("set_member_role", %{"user-id" => user_id, "role" => role}, socket) do
    server = socket.assigns.server

    case Servers.change_role(socket.assigns.current_scope, server.id, user_id, role) do
      {:ok, _member} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  def handle_event("typing_started", _params, socket) do
    case socket.assigns.active_channel do
      nil ->
        {:noreply, socket}

      channel ->
        TypingTracker.track_user(self(), channel, socket.assigns.current_scope.user)
        {:noreply, socket}
    end
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
    case socket.assigns.active_channel do
      nil ->
        {:noreply, socket}

      channel ->
        TypingTracker.untrack_user(self(), channel, socket.assigns.current_scope.user)
        {:noreply, socket}
    end
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
    open? = !socket.assigns.mobile_search?

    {:noreply,
     socket
     |> assign(:mobile_search?, open?)
     |> push_event(if(open?, do: "search:focus", else: "search:dismiss"), %{})}
  end

  def handle_event("search", %{"q" => q}, socket) do
    q = String.trim(q)

    results =
      if q == "" do
        nil
      else
        Messages.search_server_messages(
          socket.assigns.current_scope,
          socket.assigns.server.id,
          q
        )
      end

    {:noreply,
     assign(socket,
       search_q: q,
       search_results: results,
       mobile_search?: q != "" or socket.assigns.mobile_search?
     )}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(search_q: "", search_results: nil, mobile_search?: false)
     |> push_event("search:dismiss", %{})}
  end

  def handle_event("open_search_result", %{"id" => id} = params, socket) do
    channel_id = params["channel-id"] || params["channel_id"]
    active = socket.assigns.active_channel

    socket =
      socket
      |> assign(:search_results, nil)
      |> assign(:search_q, "")
      |> assign(:mobile_search?, false)
      |> push_event("search:dismiss", %{})

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
  def handle_info(_msg, %{assigns: %{member?: false}} = socket), do: {:noreply, socket}

  def handle_info({:member_removed, member}, socket) do
    if member.user_id == socket.assigns.current_scope.user.id do
      maybe_untrack_presence(socket)

      {:noreply,
       socket
       |> put_flash(:error, gettext("You were removed from this server."))
       |> push_navigate(to: ~p"/")}
    else
      {:noreply, stream_delete(socket, :members, member)}
    end
  end

  def handle_info({:member_joined, member}, socket) do
    {:noreply, stream_insert(socket, :members, ensure_member_user(member))}
  end

  def handle_info({:member_updated, member}, socket) do
    member = ensure_member_user(member)

    socket =
      socket
      |> stream_insert(:members, member)
      |> maybe_refresh_own_membership(member)

    {:noreply, socket}
  end

  def handle_info({:channels_changed}, socket) do
    previous_ids = MapSet.new(Enum.map(socket.assigns.channels, & &1.id))
    socket = refresh_channels(socket) |> sync_channel_subscriptions(previous_ids)

    active = socket.assigns.active_channel
    still_exists? = active && Enum.any?(socket.assigns.channels, &(&1.id == active.id))

    socket =
      if active && not still_exists? do
        case List.first(socket.assigns.channels) do
          nil ->
            socket

          next ->
            push_navigate(socket, to: channel_path(socket, next))
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:new_message, message}, socket) do
    if not socket.assigns.can_view_channel? do
      {:noreply, socket}
    else
      active_channel = socket.assigns.active_channel
      user_id = socket.assigns.current_scope.user.id

      socket =
        cond do
          active_channel && message.channel_id == active_channel.id ->
            # Stay in the stream; IntersectionObserver advances the watermark
            # only when the message actually enters the viewport.
            {message, last_info} = tag_incoming_message(socket, message)

            socket
            |> maybe_stream_date_divider(message)
            |> stream_insert(:messages, message)
            |> merge_polls([message])
            |> assign(:last_message_info, last_info)
            |> assign(
              :header_flags,
              Map.put(socket.assigns.header_flags, message.id, message.show_header)
            )
            |> assign(:last_message_at, message.inserted_at)
            |> assign(:messages_empty?, false)
            |> assign(:oldest_message_id, socket.assigns[:oldest_message_id] || message.id)
            |> assign(
              :oldest_message_info,
              socket.assigns[:oldest_message_info] || oldest_message_info([message])
            )
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
  end

  def handle_info({:updated_message, message}, socket) do
    if active_channel_message?(socket, message) do
      {:noreply, stream_message(socket, message)}
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
       |> stream_message(message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:poll_updated, payload}, socket) do
    active = socket.assigns.active_channel

    if active && payload.channel_id == active.id do
      poll = payload.poll
      options_data = Enum.map(poll.options, &%{id: &1.id, count: &1.votes_count})
      total_votes = Enum.sum(Enum.map(options_data, & &1.count))
      mine? = payload.user_id == socket.assigns.current_scope.user.id

      event = %{
        poll_id: poll.id,
        total_votes: total_votes,
        options: options_data
      }

      event =
        if mine? do
          Map.put(event, :selected_option_ids, poll.selected_option_ids)
        else
          event
        end

      socket =
        socket
        |> assign(
          :polls,
          Map.put(socket.assigns.polls, payload.message_id, %{poll | selected_option_ids: []})
        )
        |> maybe_patch_my_poll_votes(payload)
        |> maybe_refresh_open_poll_details(poll.id)
        |> push_event("update_poll_chart", event)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:deleted_message, message}, socket) do
    if active_channel_message?(socket, message) do
      {:noreply,
       socket
       |> maybe_cancel_edit(message.id)
       |> maybe_refresh_pinned_drawer(message)
       |> stream_message(message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:message_pinned_toggled, message}, socket) do
    if active_channel_message?(socket, message) do
      socket =
        socket
        |> stream_message(message)
        |> maybe_refresh_pinned_list()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:typing_diff, topic, joins, leaves}, socket) do
    active = socket.assigns.active_channel

    if is_nil(active) or TypingTracker.topic(active) != topic do
      {:noreply, socket}
    else
      current_user_id = socket.assigns.current_scope.user.id

      typing_users =
        socket.assigns.typing_users
        |> drop_typists(leaves, active)
        |> put_typists(joins, current_user_id)

      {:noreply, assign(socket, :typing_users, typing_users)}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff"}, socket) do
    if topic == channel_topic(socket.assigns.active_channel) do
      {:noreply, assign(socket, :online_users, list_online(socket.assigns.active_channel))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:custom_status_changed, user_id, emoji, text}, socket) do
    {:noreply,
     push_event(socket, "sync_status_badges", %{
       user_id: to_string(user_id),
       emoji: emoji,
       text: text
     })}
  end

  @impl true
  def render(%{member?: false} = assigns), do: preview(assigns)

  def render(assigns), do: chat(assigns)

  defp delete_message_action(socket, id, message) do
    current_user_id = socket.assigns.current_scope.user.id
    is_mine = message.user_id == current_user_id
    is_mod = socket.assigns.can_manage_messages?

    cond do
      is_mine ->
        delete_current_message(socket, id)

      is_mod ->
        {:noreply,
         socket
         |> assign(:deleting_message, message)
         |> assign(
           :delete_reason_form,
           to_form(%{"reason" => "", "id" => message.id}, as: :audit)
         )}

      true ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    end
  end

  defp delete_current_message(socket, id, reason \\ nil) do
    case Messages.delete_message(socket.assigns.current_scope, id, reason) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete message"))}
    end
  end

  defp assign_member_permissions(socket, nil) do
    assign(socket,
      admin?: false,
      can_manage_server?: false,
      can_manage_channels?: false,
      can_kick_members?: false,
      can_manage_messages?: false,
      can_send_messages?: false,
      can_view_channel?: false
    )
  end

  defp assign_member_permissions(socket, member) do
    perms = member.permissions
    can_manage_server? = Permissions.has_permission?(perms, :manage_server)
    can_manage_channels? = Permissions.has_permission?(perms, :manage_channels)

    assign(socket,
      admin?: can_manage_server? or can_manage_channels?,
      can_manage_server?: can_manage_server?,
      can_manage_channels?: can_manage_channels?,
      can_kick_members?: Permissions.has_permission?(perms, :kick_members),
      can_manage_messages?: Permissions.has_permission?(perms, :manage_messages),
      can_send_messages?: Permissions.has_permission?(perms, :send_messages),
      can_view_channel?: Permissions.has_permission?(perms, :view_channel)
    )
  end

  defp can_view_channel?(nil), do: false

  defp can_view_channel?(member) do
    Permissions.has_permission?(member.permissions, :view_channel)
  end

  defp assign_messages(socket, messages) do
    offset = socket.assigns.timezone_offset
    {grouped, last_info, flags} = Helpers.process_message_grouping(messages, offset)

    oldest_id =
      case grouped do
        [first | _] -> first.id
        _ -> nil
      end

    last_at =
      case List.last(grouped) do
        %{inserted_at: at} -> at
        _ -> nil
      end

    items = Helpers.with_date_dividers(grouped, offset)

    socket
    |> assign(:oldest_message_id, oldest_id)
    |> assign(:oldest_message_info, Helpers.oldest_message_info(grouped))
    |> assign(:last_message_at, last_at)
    |> assign(:last_message_info, last_info)
    |> assign(:header_flags, flags)
    |> assign(:has_more_messages, length(messages) >= @message_page_size)
    |> assign(:messages_empty?, messages == [])
    |> assign(:reactions, Messages.reaction_summary(Enum.map(messages, & &1.id)))
    |> assign_polls(messages)
    |> stream(:messages, items, reset: true)
  end

  defp assign_polls(socket, messages) do
    ids = Enum.map(messages, & &1.id)
    polls = Messages.poll_summary(ids)
    poll_ids = polls |> Map.values() |> Enum.map(& &1.id)
    user_id = socket.assigns.current_scope.user.id
    my_votes = Messages.poll_votes_for_user(user_id, poll_ids)

    socket
    |> assign(:polls, polls)
    |> assign(:my_poll_votes, my_votes)
  end

  defp merge_polls(socket, messages) do
    ids = Enum.map(messages, & &1.id)
    summary = Messages.poll_summary(ids)

    if summary == %{} do
      socket
    else
      poll_ids = summary |> Map.values() |> Enum.map(& &1.id)
      user_id = socket.assigns.current_scope.user.id
      my_votes = Messages.poll_votes_for_user(user_id, poll_ids)

      socket
      |> assign(:polls, Map.merge(socket.assigns.polls, summary))
      |> assign(:my_poll_votes, Map.merge(socket.assigns.my_poll_votes, my_votes))
    end
  end

  defp maybe_patch_my_poll_votes(socket, %{user_id: user_id, poll: poll}) do
    if socket.assigns.current_scope.user.id == user_id do
      assign(
        socket,
        :my_poll_votes,
        Map.put(socket.assigns.my_poll_votes, poll.id, MapSet.new(poll.selected_option_ids))
      )
    else
      socket
    end
  end

  defp maybe_refresh_open_poll_details(socket, poll_id) do
    case socket.assigns[:poll_details] do
      %{id: ^poll_id} -> refresh_poll_details(socket, poll_id)
      _ -> socket
    end
  end

  defp refresh_poll_details(socket, poll_id) do
    case Messages.get_poll_details(socket.assigns.current_scope, poll_id) do
      {:ok, details} -> assign(socket, :poll_details, details)
      _ -> socket
    end
  end

  defp tag_incoming_message(socket, message) do
    last_info = socket.assigns.last_message_info
    offset = socket.assigns.timezone_offset
    message = %{message | show_header: start_of_group?(last_info, message, offset)}
    {message, %{user_id: message.user_id, time: message.inserted_at}}
  end

  # When older history is prepended, the previous oldest may now continue a group.
  defp maybe_hide_continuation_header(socket, page_last) do
    oldest = socket.assigns[:oldest_message_info] || oldest_message_info([])
    offset = socket.assigns.timezone_offset

    cond do
      is_nil(oldest.id) ->
        socket

      start_of_group?(page_last, %{user_id: oldest.user_id, inserted_at: oldest.time}, offset) ->
        socket

      true ->
        case Messages.get_message_for_user(socket.assigns.current_scope, oldest.id) do
          {:ok, message} ->
            socket
            |> assign(:header_flags, Map.put(socket.assigns.header_flags, message.id, false))
            |> stream_insert(:messages, %{message | show_header: false})

          {:error, _} ->
            socket
        end
    end
  end

  defp maybe_stream_date_divider(socket, message) do
    offset = socket.assigns.timezone_offset
    last_at = socket.assigns[:last_message_at]

    if needs_date_divider?(last_at, message.inserted_at, offset) do
      date = local_date(message.inserted_at, offset)
      stream_insert(socket, :messages, date_divider(date, message.id))
    else
      socket
    end
  end

  defp merge_reactions(socket, messages) do
    summary = Messages.reaction_summary(Enum.map(messages, & &1.id))
    assign(socket, :reactions, Map.merge(socket.assigns.reactions, summary))
  end

  defp maybe_done_loading(socket, _event, true), do: socket

  defp maybe_done_loading(socket, event, false) do
    done_loading(socket, event)
  end

  defp done_loading(socket, event) do
    push_event(socket, "infinite_scroll:done", %{event: event})
  end

  defp visible_messages(scope, channel), do: visible_messages(scope, channel, [])
  defp visible_messages(_scope, nil, _opts), do: []

  defp visible_messages(scope, channel, opts) do
    case Messages.list_messages_for_user(scope, channel.id, opts) do
      {:ok, messages} -> messages
      {:error, _} -> []
    end
  end

  defp visible_pins(_scope, nil), do: []

  defp visible_pins(scope, channel) do
    case Messages.list_pinned_messages_for_user(scope, channel.id) do
      {:ok, messages} -> messages
      {:error, _} -> []
    end
  end

  defp maybe_scroll_to_highlight(socket, %{"highlight" => id})
       when is_binary(id) and id != "" do
    push_event(socket, "messages:scroll_to", %{id: id})
  end

  defp maybe_scroll_to_highlight(socket, _), do: socket

  defp maybe_push_composer_reset(socket, _params) do
    push_event(socket, "composer:clear", %{})
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
      if ((connected?(socket) and old_channel) && old_channel.id != channel.id) and
           socket.assigns.can_view_channel? do
        Presence.untrack_user(self(), channel_topic(old_channel), scope.user)
        Presence.track_user(self(), channel_topic(channel), scope.user)
        TypingTracker.untrack_user(self(), old_channel, scope.user)
        unsubscribe_typing(old_channel)
        subscribe_typing(channel)
        socket
      else
        socket
      end

    messages = visible_messages(scope, channel)

    socket
    |> assign(:active_channel, channel)
    |> assign(:online_users, list_online(channel))
    |> assign(:typing_users, list_typists(channel, scope.user.id))
    |> assign(:editing_message_id, nil)
    |> assign(:replying_to, nil)
    |> assign(:deleting_message, nil)
    |> assign(:composer_mode, :text)
    |> assign(:poll_form, empty_poll_form())
    |> assign(:poll_details, nil)
    |> assign(:show_pinned_drawer, false)
    |> assign(:pinned_messages, [])
    |> assign(:mobile_panel, :messages)
    |> assign(:search_q, "")
    |> assign(:search_results, nil)
    |> assign(:highlight_id, Map.get(params, "highlight"))
    |> assign_messages(messages)
    |> maybe_push_composer_reset(params)
    |> maybe_scroll_to_highlight(params)
  end

  defp apply_action(socket, :new_channel, _params) do
    if socket.assigns.can_manage_channels? do
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
      not socket.assigns.can_manage_channels? ->
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
        {:noreply,
         socket
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
          socket = maybe_replace_active_channel(socket, updated)
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

  defp empty_poll_form, do: poll_form(empty_poll_params())

  defp empty_poll_params do
    %{
      "question" => "",
      "options" => ["", ""],
      "allow_multiple" => "false",
      "results_open" => "true"
    }
  end

  defp poll_form(params), do: to_form(params, as: :poll)

  defp poll_form_params(socket) do
    case socket.assigns.poll_form do
      %{params: params} when is_map(params) and params != %{} ->
        normalize_poll_params(params)

      %{source: source} when is_map(source) ->
        normalize_poll_params(source)

      _ ->
        empty_poll_params()
    end
  end

  defp normalize_poll_params(params) when is_map(params) do
    options =
      params
      |> Map.get("options", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)

    %{
      "question" => to_string(Map.get(params, "question") || ""),
      "options" => options,
      "allow_multiple" => truthy_param(Map.get(params, "allow_multiple")),
      "results_open" => truthy_param(Map.get(params, "results_open"), "true")
    }
  end

  defp poll_options(params), do: List.wrap(params["options"])

  defp truthy_param(value, default \\ "false")
  defp truthy_param("true", _default), do: "true"
  defp truthy_param(true, _default), do: "true"
  defp truthy_param("false", _default), do: "false"
  defp truthy_param(false, _default), do: "false"
  defp truthy_param(_, default), do: default

  defp ensure_member_user(member) do
    Xamt.Repo.preload(member, :user)
  end

  defp maybe_refresh_own_membership(socket, member) do
    if member.user_id == socket.assigns.current_scope.user.id do
      previous_view? = socket.assigns.can_view_channel?

      socket
      |> assign(:current_member, member)
      |> assign_member_permissions(member)
      |> sync_view_subscriptions(previous_view?)
    else
      socket
    end
  end

  defp sync_view_subscriptions(socket, previous_view?) do
    can_view? = socket.assigns.can_view_channel?

    cond do
      not connected?(socket) ->
        socket

      previous_view? and not can_view? ->
        Enum.each(socket.assigns.channels, &unsubscribe_channel/1)
        maybe_untrack_presence(socket)
        unsubscribe_typing(socket.assigns.active_channel)
        assign_messages(socket, [])

      can_view? and not previous_view? ->
        Enum.each(socket.assigns.channels, &subscribe_channel/1)

        if channel = socket.assigns.active_channel do
          Presence.track_user(
            self(),
            channel_topic(channel),
            socket.assigns.current_scope.user
          )

          subscribe_typing(channel)
        end

        assign_messages(
          socket,
          visible_messages(socket.assigns.current_scope, socket.assigns.active_channel)
        )

      true ->
        socket
    end
  end

  defp sync_channel_subscriptions(socket, previous_ids) do
    if connected?(socket) and socket.assigns.can_view_channel? do
      current = socket.assigns.channels
      current_ids = MapSet.new(Enum.map(current, & &1.id))

      Enum.each(current, fn channel ->
        if not MapSet.member?(previous_ids, channel.id) do
          subscribe_channel(channel)
        end
      end)

      Enum.each(previous_ids, fn id ->
        if not MapSet.member?(current_ids, id) do
          Phoenix.PubSub.unsubscribe(Xamt.PubSub, channel_topic_id(id))
        end
      end)
    end

    socket
  end

  defp maybe_untrack_presence(socket) do
    case socket.assigns.active_channel do
      nil ->
        :ok

      channel ->
        Presence.untrack_user(
          self(),
          channel_topic(channel),
          socket.assigns.current_scope.user
        )

        TypingTracker.untrack_user(self(), channel, socket.assigns.current_scope.user)
    end
  end

  defp subscribe_channel(%Channel{} = channel) do
    Phoenix.PubSub.subscribe(Xamt.PubSub, channel_topic(channel))
  end

  defp unsubscribe_channel(%Channel{} = channel) do
    Phoenix.PubSub.unsubscribe(Xamt.PubSub, channel_topic(channel))
  end

  defp channel_topic_id(id), do: "xamt:channel:#{id}"

  defp subscribe_typing(nil), do: :ok

  defp subscribe_typing(%Channel{} = channel) do
    Phoenix.PubSub.subscribe(Xamt.PubSub, TypingTracker.topic(channel))
  end

  defp unsubscribe_typing(nil), do: :ok

  defp unsubscribe_typing(%Channel{} = channel) do
    Phoenix.PubSub.unsubscribe(Xamt.PubSub, TypingTracker.topic(channel))
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
    case Messages.get_message_for_user(socket.assigns.current_scope, id) do
      {:ok, message} -> stream_message(socket, message)
      {:error, _} -> socket
    end
  end

  defp restream_message(socket, _), do: socket

  defp stream_message(socket, message) do
    show_header = Map.get(socket.assigns.header_flags, message.id, true)
    stream_insert(socket, :messages, %{message | show_header: show_header})
  end

  defp maybe_refresh_pinned_list(socket) do
    if socket.assigns.show_pinned_drawer and socket.assigns.active_channel do
      messages = visible_pins(socket.assigns.current_scope, socket.assigns.active_channel)
      assign(socket, :pinned_messages, messages)
    else
      socket
    end
  end

  defp maybe_refresh_pinned_drawer(socket, message) do
    if socket.assigns.show_pinned_drawer and message.is_pinned do
      maybe_refresh_pinned_list(socket)
    else
      socket
    end
  end

  defp maybe_cancel_edit(socket, message_id) do
    if socket.assigns.editing_message_id == message_id do
      socket
      |> assign(:editing_message_id, nil)
      |> push_event("composer:clear", %{})
    else
      socket
    end
  end

  defp channel_topic(%Channel{id: id}), do: "xamt:channel:#{id}"
  defp channel_topic(nil), do: "xamt:channel:none"

  defp apply_custom_status(socket, attrs) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_custom_status(user, attrs) do
      {:ok, updated_user} ->
        channel = socket.assigns.active_channel
        topic = channel_topic(channel)
        emoji = updated_user.status_emoji
        text = updated_user.status_text

        if connected?(socket) and channel do
          Presence.update_user_status(self(), topic, updated_user, %{
            status_emoji: emoji,
            status_text: text
          })

          Phoenix.PubSub.broadcast(
            Xamt.PubSub,
            topic,
            {:custom_status_changed, updated_user.id, emoji, text}
          )
        end

        {:noreply,
         socket
         |> assign(:current_scope, %{socket.assigns.current_scope | user: updated_user})
         |> assign(:online_users, list_online(channel))
         |> assign(:show_status_picker, false)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update status"))}
    end
  end

  defp list_online(nil), do: []

  defp list_online(channel) do
    Presence.list(channel_topic(channel))
    |> Enum.map(fn {id, %{metas: metas}} ->
      meta = List.first(metas) || %{}

      %{
        id: id,
        display_name: presence_meta(meta, :display_name) || presence_meta(meta, :username) || "?",
        username: presence_meta(meta, :username),
        avatar: presence_meta(meta, :avatar),
        status_emoji: presence_meta(meta, :status_emoji),
        status_text: presence_meta(meta, :status_text),
        global_role: presence_meta(meta, :global_role) || "user"
      }
    end)
  end

  defp list_typists(nil, _), do: %{}

  defp list_typists(channel, current_user_id) do
    Enum.reduce(TypingTracker.list(channel), %{}, fn {user_id, meta}, acc ->
      put_typist(acc, user_id, meta, current_user_id)
    end)
  end

  defp drop_typists(typing_users, leaves, channel) do
    Enum.reduce(leaves, typing_users, fn {user_id, _meta}, acc ->
      if TypingTracker.still_typing?(channel, user_id) do
        acc
      else
        Map.delete(acc, user_id)
      end
    end)
  end

  defp put_typists(typing_users, joins, current_user_id) do
    Enum.reduce(joins, typing_users, fn {user_id, meta}, acc ->
      put_typist(acc, user_id, meta, current_user_id)
    end)
  end

  defp put_typist(typing_users, user_id, _meta, user_id), do: typing_users

  defp put_typist(typing_users, user_id, meta, _current_user_id) do
    Map.put(typing_users, user_id, TypingTracker.display_name(meta))
  end

  defp presence_meta(meta, key) when is_atom(key) do
    Map.get(meta, key) || Map.get(meta, Atom.to_string(key))
  end

  # Browser `Date.getTimezoneOffset()`: minutes to add to local time to get UTC.
  # UTC+8 returns -480, so we subtract that offset to show wall-clock time.
  defp connect_timezone_offset(socket) do
    if connected?(socket) do
      case get_connect_params(socket) do
        %{"timezone_offset" => offset} when is_integer(offset) and offset in -840..840 ->
          offset

        %{"timezone_offset" => offset} when is_binary(offset) ->
          case Integer.parse(offset) do
            {n, ""} when n in -840..840 -> n
            _ -> 0
          end

        _ ->
          0
      end
    else
      0
    end
  end

  defp send_audio_message(socket, channel) do
    {done, in_progress} = Phoenix.LiveView.uploaded_entries(socket, :audio)

    socket =
      Enum.reduce(in_progress, socket, fn entry, acc ->
        cancel_upload(acc, :audio, entry.ref)
      end)

    cond do
      done == [] ->
        voice_failed(socket, gettext("Could not send voice message"))

      true ->
        case XamtWeb.Uploads.consume_audio(socket, :audio) do
          url when is_binary(url) ->
            attrs = %{
              "content" => %{"type" => "audio", "url" => url},
              "content_html" => "🎤 <em>#{gettext("Voice message")}</em>",
              "content_type" => "audio",
              "reply_to_id" => socket.assigns.replying_to && socket.assigns.replying_to.id
            }

            case Messages.create_message(socket.assigns.current_scope, channel.id, attrs) do
              {:ok, _message} ->
                voice_sent(socket)

              {:error, :rate_limited} ->
                voice_failed(socket, gettext("Messages sent too fast"))

              {:error, :unauthorized} ->
                voice_failed(socket, gettext("Unauthorized"))

              {:error, :invalid_reply} ->
                voice_failed(socket, gettext("Could not send voice message"))

              {:error, :invalid_content} ->
                voice_failed(socket, gettext("Could not send voice message"))

              {:error, _changeset} ->
                voice_failed(socket, gettext("Could not send voice message"))
            end

          _ ->
            voice_failed(socket, gettext("Could not send voice message"))
        end
    end
  end

  defp voice_sent(socket) do
    {:noreply,
     socket
     |> assign(:replying_to, nil)
     |> push_event("voice:sent", %{})}
  end

  defp voice_failed(socket, message) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> push_event("voice:failed", %{})}
  end
end
