defmodule Xamt.Messages do
  @moduledoc """
  Channel messages and real-time broadcasts.

  Authorization belongs here: prefer scope-taking entry points
  (`create_message/3`, `update_message/3`, `delete_message/3`,
  `toggle_reaction/3`, `get_message_for_user/2`, `search_server_messages/3`)
  over bare `get_message!/1` / `search_messages/2` from LiveViews and HTTP.
  Message HTML is scrubbed by `Xamt.Messages.HtmlSanitizer` before persist.
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
  alias Xamt.Messages.{HtmlSanitizer, Mention, Message, RateLimiter, Reaction}

  @default_limit 50
  @mention_tag_re ~r/<(span|a)\b([^>]*\bdata-mention-id=["']([^"']+)["'][^>]*)>(.*?)<\/\1>/si
  @mention_id_re ~r/data-mention-id=["']([0-9a-fA-F-]{36})["']/

  def create_message(%Scope{user: user}, channel_id, attrs) when is_map(attrs) do
    raw_html = Map.get(attrs, "content_html") || Map.get(attrs, :content_html)
    {content_html, mention_ids} = prepare_mentions(raw_html, channel_id)
    attrs = put_sanitized_html(attrs, content_html)
    content = build_content(attrs)
    reply_to_id = normalize_reply_to_id(attrs)

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
                      content_type: content_type(attrs, content),
                      content_html: content_html,
                      search_text: search_normalize(index_text(content_html, content)),
                      reply_to_id: reply_to_id
                    })
                    |> Repo.insert(),
                  :ok <- replace_mentions(message.id, mention_ids) do
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

      {content_html, mention_ids} = prepare_mentions(raw_html, message.channel_id)
      attrs = put_sanitized_html(attrs, content_html)
      content = build_content(attrs, message.content)
      previous_mention_ids = message.mentioned_user_ids || []

      with {:ok, message} <-
             Repo.transact(fn ->
               with {:ok, message} <-
                      message
                      |> Message.changeset(%{
                        content: content,
                        content_type: content_type(attrs, content),
                        content_html: content_html,
                        search_text: search_normalize(index_text(content_html, content))
                      })
                      |> Repo.update(),
                    :ok <- replace_mentions(message.id, mention_ids) do
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

  # Traditional Mongolian joins suffixes with NNBSP (U+202F) and the Mongolian
  # vowel separator (U+180E); Postgres' parser does not break on either, so a
  # word plus its suffix would index as a single token. Free variation
  # selectors (U+180B..U+180D) and zero-width joiners only pick a glyph shape,
  # so they must not affect whether two spellings match.
  @search_separators ["\u202F", "\u180E", "\u00A0"]
  @search_ignored ["\u180B", "\u180C", "\u180D", "\u200C", "\u200D", "\uFEFF"]

  @doc """
  Normalises text for the search index and for search queries.

  Both sides must go through this function or Mongolian spellings that differ
  only in variation selectors will fail to match.
  """
  def search_normalize(nil), do: ""

  def search_normalize(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfc_binary()
    |> replace_all(@search_separators, " ")
    |> replace_all(@search_ignored, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp replace_all(text, patterns, replacement) do
    Enum.reduce(patterns, text, &String.replace(&2, &1, replacement))
  end

  @doc """
  Full-text search across the given channels, newest first.

  Prefer `search_server_messages/3` from LiveViews and controllers: this
  lower-level form trusts the caller to supply only authorized channel IDs.
  """
  def search_messages(channel_ids, query, opts \\ [])
  def search_messages([], _query, _opts), do: []

  def search_messages(channel_ids, query, opts) when is_list(channel_ids) do
    normalized = search_normalize(query)

    if normalized == "" do
      []
    else
      limit = Keyword.get(opts, :limit, 30)

      from(m in Message,
        where:
          m.channel_id in ^channel_ids and is_nil(m.deleted_at) and
            fragment("search_tsv @@ plainto_tsquery('simple', ?)", ^normalized),
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit,
        preload: [:user, :channel]
      )
      |> Repo.all()
    end
  end

  @doc """
  Searches messages in a server the user belongs to.

  Channel IDs are resolved inside the context from membership, so callers cannot
  widen the search to foreign servers by inventing IDs.
  """
  def search_server_messages(%Scope{user: user}, server_id, query, opts \\ [])
      when is_binary(server_id) do
    if Xamt.Servers.member?(server_id, user.id) do
      channel_ids =
        from(c in Channel, where: c.server_id == ^server_id, select: c.id)
        |> Repo.all()

      search_messages(channel_ids, query, opts)
    else
      []
    end
  end

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
        toggle_reaction_on(message, user, emoji)
      end
    end
  end

  defp toggle_reaction_on(message, user, emoji) do
    existing =
      Repo.get_by(Reaction, message_id: message.id, user_id: user.id, emoji: emoji)

    result =
      if existing do
        Repo.delete(existing)
      else
        %Reaction{}
        |> Reaction.changeset(%{message_id: message.id, user_id: user.id, emoji: emoji})
        |> Repo.insert()
      end

    with {:ok, _} <- result do
      summary = Map.get(reaction_summary([message.id]), message.id, %{})

      Phoenix.PubSub.broadcast(
        Xamt.PubSub,
        channel_topic(message.channel_id),
        {:reaction_changed, strip_for_broadcast(message), summary}
      )

      {:ok, summary}
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

  @doc """
  Reactions for the given messages as `%{message_id => %{emoji => [user_id]}}`.
  """
  def reaction_summary([]), do: %{}

  def reaction_summary(message_ids) when is_list(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      order_by: [asc: r.inserted_at],
      select: {r.message_id, r.emoji, r.user_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {message_id, emoji, user_id}, acc ->
      Map.update(acc, message_id, %{emoji => [user_id]}, fn by_emoji ->
        Map.update(by_emoji, emoji, [user_id], &(&1 ++ [user_id]))
      end)
    end)
  end

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

  defp build_content(attrs, existing \\ %{}) do
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
  end

  defp content_type(attrs, content) when is_map(content) do
    Map.get(attrs, "content_type") ||
      Map.get(attrs, :content_type) ||
      Map.get(content, "type") ||
      "rich_text"
  end

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

  defp prepare_mentions(html, channel_id) when is_binary(html) and is_binary(channel_id) do
    html = HtmlSanitizer.sanitize(html)
    server_id = channel_server_id(channel_id)
    ids = extract_mention_ids(html)
    users = mentionable_users(server_id, ids)
    {rewrite_mention_tags(html, users), Map.keys(users)}
  end

  defp prepare_mentions(_html, _channel_id), do: {"", []}

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

  defp extract_mention_ids(html) do
    @mention_id_re
    |> Regex.scan(html)
    |> Enum.map(fn [_, id] -> id end)
    |> Enum.uniq()
    |> Enum.filter(&valid_uuid?/1)
  end

  defp valid_uuid?(id) do
    match?({:ok, _}, Ecto.UUID.cast(id))
  end

  defp mentionable_users(_server_id, []), do: %{}

  defp mentionable_users(server_id, ids) when is_binary(server_id) do
    from(u in User,
      join: m in ServerMember,
      on: m.user_id == u.id,
      where: m.server_id == ^server_id and u.id in ^ids,
      select: u
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp mentionable_users(_server_id, _ids), do: %{}

  defp rewrite_mention_tags(html, users_by_id) do
    Regex.replace(@mention_tag_re, html, fn _full, _tag, _attrs, id, inner ->
      case Map.get(users_by_id, id) do
        %User{} = user -> mention_chip_html(user)
        _ -> strip_tags(inner)
      end
    end)
  end

  defp mention_chip_html(%User{id: id, username: username}) do
    safe = html_escape(username || "")

    ~s(<a class="xamt-mention mongol-text" href="/profile/#{safe}" data-phx-link="redirect" data-phx-link-state="push" data-mention-id="#{id}" data-mention-username="#{safe}">@#{safe}</a>)
  end

  defp strip_tags(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> html_escape()
  end

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp channel_server_id(channel_id) do
    Repo.one(from c in Channel, where: c.id == ^channel_id, select: c.server_id)
  end

  defp replace_mentions(message_id, user_ids) do
    from(m in Mention, where: m.message_id == ^message_id) |> Repo.delete_all()

    now = DateTime.utc_now(:second)

    entries =
      user_ids
      |> Enum.uniq()
      |> Enum.map(fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          message_id: message_id,
          user_id: user_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [] do
      Repo.insert_all(Mention, entries)
    end

    :ok
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
