defmodule Xamt.Messages.Search do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Channels.Channel
  alias Xamt.Messages.Message
  alias Xamt.Repo

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
  def normalize(nil), do: ""

  def normalize(text) when is_binary(text) do
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
    normalized = normalize(query)

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
    if Xamt.Servers.can?(server_id, user.id, :view_channel) do
      channel_ids =
        from(c in Channel, where: c.server_id == ^server_id, select: c.id)
        |> Repo.all()

      search_messages(channel_ids, query, opts)
    else
      []
    end
  end
end
