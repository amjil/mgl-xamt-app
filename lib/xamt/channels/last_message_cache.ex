defmodule Xamt.Channels.LastMessageCache do
  @moduledoc """
  ETS-backed cache of each channel's latest non-deleted message ID.
  """

  use GenServer

  import Ecto.Query

  alias Xamt.Repo
  alias Xamt.Messages.Message

  @table :channel_last_messages

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

    send(self(), :load_initial_data)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load_initial_data, state) do
    query =
      from m in Message,
        where: is_nil(m.deleted_at),
        distinct: m.channel_id,
        order_by: [desc: m.channel_id, desc: m.inserted_at, desc: m.id],
        select: {m.channel_id, m.id}

    Repo.all(query)
    |> Enum.each(fn {channel_id, message_id} ->
      put(channel_id, message_id)
    end)

    {:noreply, state}
  end

  @doc "Updates the channel's latest message ID."
  def put(channel_id, message_id) do
    :ets.insert(@table, {channel_id, message_id})
  end

  @doc "Removes a channel entry from the cache."
  def delete(channel_id) do
    :ets.delete(@table, channel_id)
  end

  @doc "Reads the channel's latest message ID from memory."
  def get(channel_id) do
    case :ets.lookup(@table, channel_id) do
      [{^channel_id, message_id}] -> message_id
      [] -> nil
    end
  end

  @doc """
  Reloads the latest non-deleted message for a channel after soft-delete.
  """
  def refresh(channel_id) when is_binary(channel_id) do
    query =
      from m in Message,
        where: m.channel_id == ^channel_id and is_nil(m.deleted_at),
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: 1,
        select: m.id

    case Repo.one(query) do
      nil -> delete(channel_id)
      message_id -> put(channel_id, message_id)
    end
  end
end
