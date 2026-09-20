defmodule Xamt.Channels.ChannelListCache do
  @moduledoc """
  ETS-backed cache of ordered channel lists per server.

  Shared across all LiveView mounts so reconnect storms do not re-query
  `channels` for every user. Unread status stays per-user and is layered on
  top via `LastMessageCache` + `channel_reads`.
  """

  use GenServer

  import Ecto.Query

  alias Xamt.Repo
  alias Xamt.Channels.Channel

  @table :xamt_channel_list_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ref ->
        @table
    end

    send(self(), :load_initial_data)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load_initial_data, state) do
    if Application.get_env(:xamt, :ets_cache_warmup, true) do
      from(c in Channel, order_by: [asc: c.position, asc: c.name])
      |> Repo.all()
      |> Enum.group_by(& &1.server_id)
      |> Enum.each(fn {server_id, channels} -> put(server_id, channels) end)
    end

    {:noreply, state}
  end

  @doc "Stores the ordered channel list for a server."
  def put(server_id, channels) when is_binary(server_id) and is_list(channels) do
    :ets.insert(@table, {server_id, Enum.map(channels, &strip/1)})
    channels
  end

  @doc "Drops the cached list so the next read reloads from Postgres."
  def invalidate(server_id) when is_binary(server_id) do
    :ets.delete(@table, server_id)
    :ok
  end

  @doc "Returns the cached channel list, or `nil` on miss."
  def get(server_id) when is_binary(server_id) do
    case :ets.lookup(@table, server_id) do
      [{^server_id, channels}] -> channels
      [] -> nil
    end
  end

  @doc false
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp strip(%Channel{} = channel) do
    %Channel{
      id: channel.id,
      name: channel.name,
      slug: channel.slug,
      type: channel.type,
      position: channel.position,
      server_id: channel.server_id,
      inserted_at: channel.inserted_at,
      updated_at: channel.updated_at,
      has_unread: false
    }
  end
end
