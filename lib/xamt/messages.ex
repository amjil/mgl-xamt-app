defmodule Xamt.Messages do
  @moduledoc """
  Channel messages and real-time broadcasts.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Repo
  alias Xamt.Messages.Message

  @default_limit 50

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
             reply_to_id: Map.get(attrs, "reply_to_id") || Map.get(attrs, :reply_to_id)
           })
           |> Repo.insert() do
      message = Repo.preload(message, :user)
      broadcast(channel_id, :new_message, message)
      {:ok, message}
    end
  end

  def update_message(%Scope{user: user}, message_id, attrs) when is_map(attrs) do
    message = get_message!(message_id)

    if message.user_id != user.id do
      {:error, :unauthorized}
    else
      content = build_content(attrs, message.content)

      with {:ok, message} <-
             message
             |> Message.changeset(%{
               content: content,
               content_type: content_type(attrs, content),
               content_html:
                 Map.get(attrs, "content_html") || Map.get(attrs, :content_html) ||
                   message.content_html
             })
             |> Repo.update() do
        message = Repo.preload(message, :user)
        broadcast(message.channel_id, :updated_message, message)
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
        message = Repo.preload(message, :user)
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
        preload: [:user]

    query = apply_pagination(query, before_id, before_time)

    query
    |> Repo.all()
    |> Enum.reverse()
  end

  def get_message!(id), do: Repo.get!(Message, id) |> Repo.preload(:user)

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

  defp broadcast(channel_id, event, message) do
    Phoenix.PubSub.broadcast(
      Xamt.PubSub,
      channel_topic(channel_id),
      {event, message}
    )
  end

  def channel_topic(channel_id), do: "xamt:channel:#{channel_id}"
end
