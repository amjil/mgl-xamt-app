defmodule Xamt.Messages do
  @moduledoc """
  Channel messages and real-time broadcasts.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Channels.LastMessageCache
  alias Xamt.Repo
  alias Xamt.Messages.{Message, Reaction}

  @default_limit 50
  @preloads [:user, reply_to: :user]

  def create_message(%Scope{user: user}, channel_id, attrs) when is_map(attrs) do
    content = build_content(attrs)
    content_html = Map.get(attrs, "content_html") || Map.get(attrs, :content_html)

    with {:ok, message} <-
           %Message{}
           |> Message.changeset(%{
             channel_id: channel_id,
             user_id: user.id,
             content: content,
             content_type: content_type(attrs, content),
             content_html: content_html,
             search_text: search_normalize(plain_text(content_html)),
             reply_to_id: Map.get(attrs, "reply_to_id") || Map.get(attrs, :reply_to_id)
           })
           |> Repo.insert() do
      message = Repo.preload(message, @preloads)
      LastMessageCache.put(channel_id, message.id)
      broadcast(channel_id, :new_message, strip_for_broadcast(message))
      {:ok, message}
    end
  end

  def update_message(%Scope{user: user}, message_id, attrs) when is_map(attrs) do
    message = get_message!(message_id)

    if message.user_id != user.id do
      {:error, :unauthorized}
    else
      content = build_content(attrs, message.content)

      content_html =
        Map.get(attrs, "content_html") || Map.get(attrs, :content_html) ||
          message.content_html

      with {:ok, message} <-
             message
             |> Message.changeset(%{
               content: content,
               content_type: content_type(attrs, content),
               content_html: content_html,
               search_text: search_normalize(plain_text(content_html))
             })
             |> Repo.update() do
        message = Repo.preload(message, @preloads)
        broadcast(message.channel_id, :updated_message, strip_for_broadcast(message))
        {:ok, message}
      end
    end
  end

  def soft_delete_message(%Scope{user: user}, message_id) do
    message = get_message!(message_id)

    if message.user_id != user.id do
      {:error, :unauthorized}
    else
      with {:ok, message} <-
             message
             |> Message.delete_changeset()
             |> Repo.update() do
        message = Repo.preload(message, @preloads)
        LastMessageCache.refresh(message.channel_id)
        broadcast(message.channel_id, :deleted_message, message)
        {:ok, message}
      end
    end
  end

  def list_messages(channel_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    before_id = Keyword.get(opts, :before_id)
    before_time = Keyword.get(opts, :before_time)

    query =
      from m in Message,
        where: m.channel_id == ^channel_id and is_nil(m.deleted_at),
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit,
        preload: ^@preloads

    query = apply_pagination(query, before_id, before_time)

    query
    |> Repo.all()
    |> Enum.reverse()
  end

  def get_message!(id), do: Repo.get!(Message, id) |> Repo.preload(@preloads)

  @doc """
  Plain text of a message, used for reply previews and search indexing.

  Messages are stored as editor HTML, so tags have to come off before the text
  is shown out of context or fed to a tsvector.
  """
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
        preload: [:user]
      )
      |> Repo.all()
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
    message = get_message!(message_id)

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

  defp apply_pagination(query, before_id, before_time) do
    cond do
      before_id && before_time ->
        from m in query,
          where:
            m.inserted_at < ^before_time or
              (m.inserted_at == ^before_time and m.id < ^before_id)

      before_id ->
        case Repo.get(Message, before_id) do
          %Message{inserted_at: ts, id: id} ->
            from m in query,
              where: m.inserted_at < ^ts or (m.inserted_at == ^ts and m.id < ^id)

          nil ->
            query
        end

      before_time ->
        from m in query, where: m.inserted_at < ^before_time

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
  # LiveView rendering only depends on `content_html` and `user`.
  # Clear `content` (Map) so PubSub does not copy a large AST into every subscriber heap.
  # Large `content_html` binaries are refcounted and shared by the BEAM with no copy cost.
  defp strip_for_broadcast(%Message{} = message) do
    reply_to =
      case message.reply_to do
        %Message{} = parent -> %{parent | content: %{}}
        other -> other
      end

    %{message | content: %{}, reply_to: reply_to}
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
