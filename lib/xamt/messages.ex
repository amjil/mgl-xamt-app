defmodule Xamt.Messages do
  @moduledoc """
  Channel messages and real-time broadcasts.

  Authorization belongs here: prefer scope-taking entry points
  (`create_message/3`, `update_message/3`, `delete_message/3`,
  `toggle_reaction/3`, `get_message_for_user/2`, `search_server_messages/3`)
  over bare `get_message!/1` / `search_messages/2` from LiveViews and HTTP.
  Message HTML is scrubbed by `Xamt.Messages.HtmlSanitizer` before persist.
  Gallery and audio payloads only accept same-origin `/uploads/...` paths.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Accounts.User
  alias Xamt.Channels.Channel
  alias Xamt.Channels.LastMessageCache
  alias Xamt.Moderation.AuditLog
  alias Xamt.Repo
  alias Xamt.Servers.Permissions
  alias Xamt.Servers.ServerMember
  alias Xamt.Messages.{Mentions, Message, Polls, RateLimiter, Reactions, Search}

  @default_limit 50

  def create_message(%Scope{user: user}, channel_id, attrs) when is_map(attrs) do
    raw_html = Map.get(attrs, "content_html") || Map.get(attrs, :content_html)

    with :ok <- validate_html_size(raw_html),
         {content_html, mention_ids} <- Mentions.prepare(raw_html, channel_id),
         :ok <- validate_html_size(content_html),
         attrs <- put_sanitized_html(attrs, content_html),
         content <- build_content(attrs),
         type <- content_type(attrs, content),
         reply_to_id <- normalize_reply_to_id(attrs),
         :ok <- RateLimiter.check_rate(user.id),
         :ok <- authorize_channel_perm(user.id, channel_id, :send_messages),
         :ok <- validate_reply_to(reply_to_id, channel_id),
         :ok <- validate_media_content(content, type),
         {:ok, message} <-
           Repo.transact(fn ->
             with {:ok, message} <-
                    %Message{}
                    |> Message.changeset(%{
                      channel_id: channel_id,
                      user_id: user.id,
                      content: content,
                      content_type: type,
                      content_html: content_html,
                      search_text: Search.normalize(index_text(content_html, content)),
                      reply_to_id: reply_to_id
                    })
                    |> Repo.insert(),
                  :ok <- Mentions.replace(message.id, mention_ids) do
               {:ok, message}
             end
           end) do
      message = preload_message!(message)
      LastMessageCache.put(channel_id, message.id, message.inserted_at)
      broadcast(channel_id, :new_message, strip_for_broadcast(message))
      Xamt.Messages.LinkPreview.maybe_fetch_and_update(message)
      Xamt.Notifications.WebPush.notify_mentions(message)
      {:ok, message}
    end
  end

  def update_message(%Scope{user: user}, message_id, attrs) when is_map(attrs) do
    with {:ok, message} <- fetch_message(message_id),
         :ok <- writable?(message, user) do
      raw_html =
        Map.get(attrs, "content_html") || Map.get(attrs, :content_html) ||
          message.content_html

      previous_mention_ids = message.mentioned_user_ids || []

      with :ok <- validate_html_size(raw_html),
           {content_html, mention_ids} <- Mentions.prepare(raw_html, message.channel_id),
           :ok <- validate_html_size(content_html),
           attrs <- put_sanitized_html(attrs, content_html),
           content <- build_content(attrs, message.content),
           type <- content_type(attrs, content),
           :ok <- validate_media_content(content, type),
           {:ok, message} <-
             Repo.transact(fn ->
               with {:ok, message} <-
                      message
                      |> Message.changeset(%{
                        content: content,
                        content_type: type,
                        content_html: content_html,
                        search_text: Search.normalize(index_text(content_html, content))
                      })
                      |> Repo.update(),
                    :ok <- Mentions.replace(message.id, mention_ids) do
                 {:ok, message}
               end
             end) do
        message = preload_message!(message)
        broadcast(message.channel_id, :updated_message, strip_for_broadcast(message))
        Xamt.Messages.LinkPreview.maybe_fetch_and_update(message)
        Xamt.Notifications.WebPush.notify_mentions(message, except: previous_mention_ids)
        {:ok, message}
      end
    end
  end

  @doc """
  Soft-deletes a message by writing `deleted_at`.

  When a moderator deletes someone else's message, an audit log row is written
  in the same transaction so the tombstone and the record cannot diverge.
  Authors deleting their own messages do not produce a server audit log.

  Broadcasts the tombstone struct so LiveViews can `stream_insert/3` over the
  existing DOM node instead of removing it.
  """
  def delete_message(%Scope{user: user}, message_id, reason \\ nil) do
    with {:ok, message} <- fetch_message(message_id),
         :ok <- deletable?(message, user) do
      moderated? = message.user_id != user.id

      Ecto.Multi.new()
      |> Ecto.Multi.update(:message, Message.delete_changeset(message))
      |> maybe_insert_message_deleted_log(moderated?, message, user, reason)
      |> Repo.transaction()
      |> case do
        {:ok, %{message: deleted}} ->
          deleted = preload_message!(deleted)
          LastMessageCache.refresh(deleted.channel_id)
          broadcast(deleted.channel_id, :deleted_message, strip_for_broadcast(deleted))
          {:ok, deleted}

        {:error, _op, value, _changes} ->
          {:error, value}
      end
    end
  end

  def soft_delete_message(scope, message_id, reason \\ nil) do
    delete_message(scope, message_id, reason)
  end

  @doc """
  Toggles `is_pinned` when the actor has `:manage_messages` on the channel.

  Broadcasts `{:message_pinned_toggled, message}` so LiveViews can refresh the
  pin badge in the main stream and the pinned drawer when it is open.
  """
  def toggle_pin_message(%Scope{user: user}, message_id) do
    with {:ok, message} <- fetch_message(message_id),
         :ok <- pinable?(message, user) do
      message
      |> Message.pin_changeset(%{is_pinned: not message.is_pinned})
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          updated = preload_message!(updated)
          broadcast(updated.channel_id, :message_pinned_toggled, strip_for_broadcast(updated))
          {:ok, updated}

        error ->
          error
      end
    end
  end

  @doc "Pinned, non-deleted messages for a channel, newest first."
  def list_pinned_messages(channel_id) do
    from(m in Message,
      where: m.channel_id == ^channel_id and m.is_pinned == true and is_nil(m.deleted_at),
      order_by: [desc: m.inserted_at, desc: m.id],
      preload: [:user]
    )
    |> Repo.all()
  end

  def list_messages(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    before_id = Keyword.get(opts, :before_id)
    before_time = Keyword.get(opts, :before_time)

    from(m in Message, where: m.channel_id == ^channel_id)
    |> apply_pagination(before_id, before_time)
    |> with_assoc_joins()
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&attach_mention_ids/1)
    |> Enum.reverse()
  end

  def get_message!(id) do
    from(m in Message, where: m.id == ^id)
    |> with_assoc_joins()
    |> Repo.one!()
    |> attach_mention_ids()
  end

  @doc """
  Loads a message only when the user may view its channel.

  Prefer this (or other scope-taking APIs) over `get_message!/1` from LiveViews
  and controllers so authorization cannot be skipped by accident.
  """
  def get_message_for_user(%Scope{user: user}, id) do
    with {:ok, message} <- fetch_message(id),
         :ok <- authorize_channel_perm(user.id, message.channel_id, :view_channel) do
      {:ok, message}
    end
  end

  @doc """
  Stores Open Graph data on a message without bumping `updated_at`.

  Used by link unfurling so a completed fetch does not mark the message as
  edited. Broadcasts `:updated_message` so LiveViews can `stream_insert/3`.
  """
  def put_link_preview(%Message{} = message, preview)
      when is_map(preview) or is_nil(preview) do
    {count, _} =
      from(m in Message, where: m.id == ^message.id and is_nil(m.deleted_at))
      |> Repo.update_all(set: [link_preview: preview])

    if count == 1 do
      message = get_message!(message.id)
      broadcast(message.channel_id, :updated_message, strip_for_broadcast(message))
      {:ok, message}
    else
      {:error, :not_found}
    end
  end

  @gallery_placeholder "🖼"

  @doc """
  Plain text of a message, used for reply previews and search indexing.

  Messages are stored as editor HTML, so tags have to come off before the text
  is shown out of context or fed to a tsvector. Gallery-only messages (no
  caption) fall back to a short placeholder so replies stay readable.
  """
  def plain_text(%Message{content_html: html, content: content}) do
    index_text(html, content)
  end

  def plain_text(%Message{content_html: html}), do: plain_text(html)
  def plain_text(nil), do: ""

  def plain_text(html) when is_binary(html) do
    html
    |> String.replace(~r{<(script|style)\b[^>]*>.*?</\1>}is, " ")
    |> String.replace(~r{<br\s*/?>}i, "\n")
    |> String.replace(~r{</(p|div|li|h[1-6]|blockquote)>}i, "\n")
    |> String.replace(~r{<[^>]+>}, "")
    |> unescape_entities()
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{2,}/, "\n")
    |> String.trim()
  end

  defp index_text(html, %{"type" => "gallery", "images" => images} = _content)
       when is_list(images) and images != [] do
    case plain_text(html) do
      "" -> @gallery_placeholder
      text -> text
    end
  end

  defp index_text(_html, %{"type" => "poll", "question" => question})
       when is_binary(question) and question != "" do
    question
  end

  defp index_text(html, _content), do: plain_text(html)

  @entities %{
    "&amp;" => "&",
    "&lt;" => "<",
    "&gt;" => ">",
    "&quot;" => "\"",
    "&#39;" => "'",
    "&apos;" => "'",
    "&nbsp;" => " "
  }

  defp unescape_entities(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  defdelegate search_normalize(text), to: Search, as: :normalize
  defdelegate search_messages(channel_ids, query), to: Search
  defdelegate search_messages(channel_ids, query, opts), to: Search
  defdelegate search_server_messages(scope, server_id, query), to: Search
  defdelegate search_server_messages(scope, server_id, query, opts), to: Search

  @doc """
  Shortens `plain_text/1` for the quoted preview shown above a reply.
  """
  def excerpt(message, limit \\ 60) do
    text = plain_text(message)

    if String.length(text) > limit do
      String.slice(text, 0, limit) <> "…"
    else
      text
    end
  end

  ## Polls

  @doc """
  Creates a poll message with question and options in one transaction.

  Broadcasts `:new_message` like other creates. Options must be 2..10 non-empty
  strings. Poll content is immutable after create.
  """
  def create_poll_message(%Scope{user: user}, channel_id, attrs) when is_map(attrs) do
    question =
      (Map.get(attrs, "question") || Map.get(attrs, :question) || "")
      |> to_string()
      |> String.trim()

    options =
      (Map.get(attrs, "options") || Map.get(attrs, :options) || [])
      |> List.wrap()
      |> Enum.map(&(to_string(&1) |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    allow_multiple =
      truthy_flag?(Map.get(attrs, "allow_multiple") || Map.get(attrs, :allow_multiple))

    # Default open; only explicit false / "false" closes voter details.
    # Do not use `||` — `false` is falsy in Elixir and would be dropped.
    results_open = open_results_flag?(attrs)

    {min_opts, max_opts} = Polls.option_limits()
    reply_to_id = normalize_reply_to_id(attrs)

    cond do
      question == "" ->
        {:error, :invalid_poll}

      length(options) < min_opts or length(options) > max_opts ->
        {:error, :invalid_poll}

      true ->
        content_html = poll_question_html(question)
        content = %{"type" => "poll", "question" => question}

        with :ok <- RateLimiter.check_rate(user.id),
             :ok <- authorize_channel_perm(user.id, channel_id, :send_messages),
             :ok <- validate_reply_to(reply_to_id, channel_id),
             {:ok, message} <-
               Repo.transact(fn ->
                 with {:ok, message} <-
                        %Message{}
                        |> Message.changeset(%{
                          channel_id: channel_id,
                          user_id: user.id,
                          content: content,
                          content_type: "poll",
                          content_html: content_html,
                          search_text: Search.normalize(question),
                          reply_to_id: reply_to_id
                        })
                        |> Repo.insert() do
                   _poll =
                     Polls.insert_for_message!(
                       message.id,
                       question,
                       options,
                       allow_multiple,
                       results_open
                     )

                   {:ok, message}
                 end
               end) do
          message = preload_message!(message)
          LastMessageCache.put(channel_id, message.id, message.inserted_at)
          broadcast(channel_id, :new_message, strip_for_broadcast(message))
          {:ok, message}
        end
    end
  end

  defp poll_question_html(question) do
    escaped =
      question
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")

    "<p>#{escaped}</p>"
  end

  defp open_results_flag?(attrs) do
    value =
      case Map.fetch(attrs, "results_open") do
        {:ok, v} ->
          v

        :error ->
          case Map.fetch(attrs, :results_open) do
            {:ok, v} -> v
            :error -> true
          end
      end

    value not in [false, "false"]
  end

  defp truthy_flag?(true), do: true
  defp truthy_flag?("true"), do: true
  defp truthy_flag?("on"), do: true
  defp truthy_flag?(_), do: false

  @doc """
  Toggles the user's vote on a poll option.

  Broadcasts `{:poll_updated, payload}` so LiveViews can animate bars without
  re-streaming the message.
  """
  def toggle_vote(%Scope{user: user}, poll_id, option_id) do
    with {:ok, poll} <- fetch_poll(poll_id),
         {:ok, message} <- fetch_message(poll.message_id),
         :ok <- authorize_channel_perm(user.id, message.channel_id, :view_channel) do
      if match?(%DateTime{}, message.deleted_at) do
        {:error, :deleted}
      else
        case Polls.toggle_vote(user.id, poll_id, option_id) do
          {:ok, poll_summary} ->
            payload = %{
              channel_id: message.channel_id,
              message_id: message.id,
              user_id: user.id,
              poll: poll_summary
            }

            Phoenix.PubSub.broadcast(
              Xamt.PubSub,
              channel_topic(message.channel_id),
              {:poll_updated, payload}
            )

            {:ok, payload}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Returns who voted for each option.

  Open polls: any channel member. Closed polls: only the message author.
  """
  def get_poll_details(%Scope{user: user}, poll_id) do
    with {:ok, poll} <- fetch_poll(poll_id),
         {:ok, message} <- fetch_message(poll.message_id),
         :ok <- authorize_channel_perm(user.id, message.channel_id, :view_channel),
         :ok <- authorize_poll_details(poll, message, user) do
      case Polls.details(poll_id) do
        nil -> {:error, :not_found}
        details -> {:ok, Map.put(details, :author_id, message.user_id)}
      end
    end
  end

  defp authorize_poll_details(%{results_open: true}, _message, _user), do: :ok

  defp authorize_poll_details(%{results_open: false}, %{user_id: author_id}, %{id: user_id})
       when author_id == user_id,
       do: :ok

  defp authorize_poll_details(_poll, _message, _user), do: {:error, :forbidden}

  defp fetch_poll(id) do
    case Polls.get_poll_with_options(id) do
      nil -> {:error, :not_found}
      poll -> {:ok, poll}
    end
  end

  defdelegate poll_summary(message_ids), to: Polls, as: :summary
  defdelegate poll_votes_for_user(user_id, poll_ids), to: Polls, as: :votes_for_user

  ## Reactions

  @doc """
  Adds the user's reaction, or removes it when it is already there.

  Broadcasts the affected message together with its new summary so subscribers
  can re-insert the stream item without another query.
  """
  def toggle_reaction(%Scope{user: user}, message_id, emoji) do
    with {:ok, message} <- fetch_message(message_id),
         :ok <- authorize_channel_perm(user.id, message.channel_id, :view_channel) do
      if match?(%DateTime{}, message.deleted_at) do
        {:error, :deleted}
      else
        with {:ok, _} <- Reactions.toggle_on(message, user, emoji) do
          summary = Map.get(Reactions.summary([message.id]), message.id, %{})

          Phoenix.PubSub.broadcast(
            Xamt.PubSub,
            channel_topic(message.channel_id),
            {:reaction_changed, strip_for_broadcast(message), summary}
          )

          {:ok, summary}
        end
      end
    end
  end

  defp writable?(%Message{deleted_at: %DateTime{}}, _user), do: {:error, :deleted}
  defp writable?(%Message{user_id: user_id}, %{id: user_id}), do: :ok
  defp writable?(_message, _user), do: {:error, :unauthorized}

  defp deletable?(%Message{deleted_at: %DateTime{}}, _user), do: {:error, :deleted}
  defp deletable?(%Message{user_id: user_id}, %{id: user_id}), do: :ok

  defp deletable?(%Message{} = message, user) do
    authorize_channel_perm(user.id, message.channel_id, :manage_messages)
  end

  defp pinable?(%Message{deleted_at: %DateTime{}}, _user), do: {:error, :deleted}

  defp pinable?(%Message{} = message, user) do
    authorize_channel_perm(user.id, message.channel_id, :manage_messages)
  end

  defp maybe_insert_message_deleted_log(multi, false, _message, _user, _reason) do
    Ecto.Multi.put(multi, :audit_log, nil)
  end

  defp maybe_insert_message_deleted_log(multi, true, message, user, reason) do
    snippet =
      message
      |> plain_text()
      |> String.slice(0, 100)

    attrs = %{
      server_id: channel_server_id(message.channel_id),
      actor_id: user.id,
      target_user_id: message.user_id,
      target_resource_id: message.id,
      action: "message_deleted",
      reason: present_reason(reason),
      metadata: %{
        "channel_id" => message.channel_id,
        "content_snippet" => snippet,
        "actor_username" => user.username,
        "target_username" => message_author_username(message)
      }
    }

    Ecto.Multi.insert(multi, :audit_log, AuditLog.changeset(%AuditLog{}, attrs))
  end

  defp message_author_username(%{user: %User{username: username}}), do: username
  defp message_author_username(_), do: nil

  defp present_reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_reason(_), do: nil

  defp authorize_channel_perm(user_id, channel_id, perm) do
    case member_permissions(user_id, channel_id) do
      nil ->
        {:error, :unauthorized}

      perms ->
        if Permissions.has_permission?(perms, perm), do: :ok, else: {:error, :unauthorized}
    end
  end

  defp member_permissions(user_id, channel_id) do
    from(m in ServerMember,
      join: c in Channel,
      on: c.server_id == m.server_id,
      where: m.user_id == ^user_id and c.id == ^channel_id,
      select: m.permissions
    )
    |> Repo.one()
  end

  defdelegate reaction_summary(message_ids), to: Reactions, as: :summary

  # Join-bind belongs_to associations so list/get is one round-trip for the
  # message, author, quoted message, and quoted author. `mentions` stays a
  # separate preload: joining has_many would cartesian-expand the page.
  # Reactions are the same shape, but the UI needs `{emoji => [user_id]}`
  # so `reaction_summary/1` issues one aggregated query instead of loading
  # `reactions: :user` structs.
  defp with_assoc_joins(query) do
    from m in query,
      join: u in assoc(m, :user),
      left_join: r in assoc(m, :reply_to),
      left_join: ru in assoc(r, :user),
      preload: [:mentions, user: u, reply_to: {r, user: ru}]
  end

  # Reload after insert/update/delete so PubSub payloads include nested
  # `reply_to.user` (the quote chip renders "replied to @someone").
  defp preload_message!(%Message{id: id}), do: get_message!(id)

  defp apply_pagination(query, before_id, before_time) do
    cond do
      before_id && before_time ->
        where(
          query,
          [m],
          m.inserted_at < ^before_time or
            (m.inserted_at == ^before_time and m.id < ^before_id)
        )

      before_id ->
        case Repo.get(Message, before_id) do
          %Message{inserted_at: ts, id: id} ->
            where(
              query,
              [m],
              m.inserted_at < ^ts or (m.inserted_at == ^ts and m.id < ^id)
            )

          nil ->
            query
        end

      before_time ->
        where(query, [m], m.inserted_at < ^before_time)

      true ->
        query
    end
  end

  # Only same-origin upload paths may appear in gallery/audio payloads.
  # Clients cannot inject arbitrary https:// media URLs via content maps.
  @upload_path_re ~r|^/uploads/[A-Za-z0-9._-]+$|

  defp build_content(attrs, existing \\ %{}) do
    raw =
      case Map.get(attrs, "content") || Map.get(attrs, :content) do
        map when is_map(map) ->
          map

        _ ->
          html =
            Map.get(attrs, "content_html") || Map.get(attrs, :content_html) ||
              Map.get(existing, "html")

          json =
            Map.get(attrs, "content_json") || Map.get(attrs, :content_json) ||
              Map.get(existing, "json")

          type = content_type(attrs, existing)

          %{
            "type" => type,
            "html" => html,
            "json" => json
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()
      end

    sanitize_media_content(raw, content_type(attrs, raw))
  end

  defp content_type(attrs, content) when is_map(content) do
    Map.get(attrs, "content_type") ||
      Map.get(attrs, :content_type) ||
      Map.get(content, "type") ||
      "rich_text"
  end

  defp sanitize_media_content(content, "gallery") when is_map(content) do
    images =
      content
      |> Map.get("images", [])
      |> List.wrap()
      |> Enum.map(&sanitize_gallery_image/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(10)

    content
    |> Map.take(["html", "json", "blocks"])
    |> Map.merge(%{"type" => "gallery", "images" => images})
  end

  defp sanitize_media_content(content, "audio") when is_map(content) do
    case Map.get(content, "url") do
      url when is_binary(url) ->
        if safe_upload_path?(url),
          do: %{"type" => "audio", "url" => url},
          else: %{"type" => "audio"}

      _ ->
        %{"type" => "audio"}
    end
  end

  defp sanitize_media_content(content, type) when is_map(content) do
    content
    |> Map.drop(["images", "url"])
    |> Map.put("type", type)
  end

  defp sanitize_gallery_image(%{"thumb" => thumb, "original" => original})
       when is_binary(thumb) and is_binary(original) do
    if safe_upload_path?(thumb) and safe_upload_path?(original) do
      %{"thumb" => thumb, "original" => original}
    end
  end

  defp sanitize_gallery_image(_), do: nil

  def safe_upload_path?(url) when is_binary(url), do: Regex.match?(@upload_path_re, url)
  def safe_upload_path?(_), do: false

  defp validate_media_content(%{"type" => "gallery", "images" => images}, "gallery")
       when is_list(images) and images != [],
       do: :ok

  defp validate_media_content(%{"type" => "audio", "url" => url}, "audio")
       when is_binary(url),
       do: :ok

  defp validate_media_content(_content, type) when type in ["gallery", "audio"],
    do: {:error, :invalid_content}

  defp validate_media_content(_content, _type), do: :ok

  defp validate_html_size(html) when is_binary(html) do
    if String.length(html) <= Message.max_content_html(), do: :ok, else: {:error, :too_long}
  end

  defp validate_html_size(_), do: :ok

  # Strip nested payload we do not need on the wire.
  # LiveView rendering only depends on `content_html` and `user`, except
  # audio (`type` + `url`) and gallery (`type` + `images`) which need structured
  # content to mount players / photo grids without refetching.
  # Clear the editor AST so PubSub does not copy it into every subscriber heap.
  # Large `content_html` binaries are refcounted and shared by the BEAM with no copy cost.
  defp strip_for_broadcast(%Message{} = message) do
    reply_to =
      case message.reply_to do
        %Message{} = parent -> %{parent | content: broadcast_content(parent.content)}
        other -> other
      end

    message = attach_mention_ids(message)

    %{message | content: broadcast_content(message.content), reply_to: reply_to}
  end

  defp broadcast_content(%{"type" => "audio"} = content), do: Map.take(content, ["type", "url"])

  defp broadcast_content(%{"type" => "gallery"} = content),
    do: Map.take(content, ["type", "images"])

  defp broadcast_content(%{"type" => "poll"} = content),
    do: Map.take(content, ["type", "question"])

  defp broadcast_content(_), do: %{}

  defp attach_mention_ids(%Message{} = message) do
    ids =
      case message.mentions do
        mentions when is_list(mentions) -> Enum.map(mentions, & &1.user_id)
        _ -> message.mentioned_user_ids || []
      end

    %{message | mentioned_user_ids: ids}
  end

  defp attach_mention_ids(other), do: other

  defp put_sanitized_html(attrs, content_html) when is_map(attrs) do
    attrs
    |> Map.put("content_html", content_html)
    |> Map.put(:content_html, content_html)
    |> maybe_put_nested_html(content_html)
  end

  defp maybe_put_nested_html(attrs, content_html) do
    case Map.get(attrs, "content") || Map.get(attrs, :content) do
      content when is_map(content) ->
        Map.put(attrs, "content", Map.put(content, "html", content_html))

      _ ->
        attrs
    end
  end

  defp normalize_reply_to_id(attrs) when is_map(attrs) do
    case Map.get(attrs, "reply_to_id") || Map.get(attrs, :reply_to_id) do
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp validate_reply_to(nil, _channel_id), do: :ok

  defp validate_reply_to(reply_to_id, channel_id) when is_binary(reply_to_id) do
    case Repo.one(
           from(m in Message,
             where: m.id == ^reply_to_id,
             select: m.channel_id
           )
         ) do
      ^channel_id -> :ok
      _ -> {:error, :invalid_reply}
    end
  end

  defp fetch_message(id) do
    case Repo.one(from(m in Message, where: m.id == ^id) |> with_assoc_joins()) do
      %Message{} = message -> {:ok, attach_mention_ids(message)}
      nil -> {:error, :not_found}
    end
  end

  defp channel_server_id(channel_id) do
    Repo.one(from c in Channel, where: c.id == ^channel_id, select: c.server_id)
  end

  defp broadcast(channel_id, event, message) do
    Phoenix.PubSub.broadcast(
      Xamt.PubSub,
      channel_topic(channel_id),
      {event, message}
    )
  end

  def channel_topic(channel_id), do: "xamt:channel:#{channel_id}"
end
