defmodule Xamt.Channels.LastMessageCache do
  @moduledoc """
  ETS-backed cache of each channel's latest non-deleted message id + inserted_at.

  Timestamps are required because binary_id defaults to UUIDv4 (not time-ordered).
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
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      _tid ->
        @table
    end

    send(self(), :load_initial_data)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load_initial_data, state) do
    if Application.get_env(:xamt, :ets_cache_warmup, true) do
      query =
        from m in Message,
          where: is_nil(m.deleted_at),
          distinct: m.channel_id,
          order_by: [desc: m.channel_id, desc: m.inserted_at, desc: m.id],
          select: {m.channel_id, m.id, m.inserted_at}

      Repo.all(query)
      |> Enum.each(fn {channel_id, message_id, inserted_at} ->
        put(channel_id, message_id, inserted_at)
      end)
    end

    {:noreply, state}
  end

  @doc "Updates the channel's latest message id and inserted_at."
  def put(channel_id, message_id, inserted_at)
      when is_binary(channel_id) and is_binary(message_id) do
    case :ets.lookup(@table, channel_id) do
      [{^channel_id, _id, existing_at}] ->
        if DateTime.compare(inserted_at, existing_at) != :lt do
          :ets.insert(@table, {channel_id, message_id, inserted_at})
        end

      [] ->
        :ets.insert(@table, {channel_id, message_id, inserted_at})
    end

    :ok
  end

  @doc "Removes a channel entry from the cache."
  def delete(channel_id) do
    :ets.delete(@table, channel_id)
  end

  @doc """
  Reads `{message_id, inserted_at}` for the channel, or `nil`.
  """
  def get(channel_id) do
    case :ets.lookup(@table, channel_id) do
      [{^channel_id, message_id, inserted_at}] -> {message_id, inserted_at}
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
        select: {m.id, m.inserted_at}

    case Repo.one(query) do
      nil -> delete(channel_id)
      {message_id, inserted_at} -> put(channel_id, message_id, inserted_at)
    end
  end
end
