defmodule Xamt.Messages.RateLimiter do
  @moduledoc """
  Lightweight sliding-window rate limit for message sends.

  Keys are `{user_id, window}` buckets stored in ETS so checks stay in-process
  and do not hit Postgres on the hot path.

  This is intentionally single-node: each BEAM node has its own ETS table, so
  limits are not shared across a cluster. That is fine for one Phoenix instance;
  if Xamt runs multi-node, swap this for a central store (Postgres / Redis) or
  accept that the effective limit scales with node count.
  """

  use GenServer

  @table :xamt_rate_limits
  @default_limit 5
  @default_window_seconds 3
  @sweep_ms 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table =
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

    schedule_sweep()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  @doc """
  Returns `:ok` when the user is under the limit, or `{:error, :rate_limited}`.

  Options:
    * `:limit` — max events per window (default from app config, else 5)
    * `:window_seconds` — bucket width in seconds (default 3)
  """
  def check_rate(user_id, opts \\ []) when not is_nil(user_id) do
    {limit, window_seconds} = resolve_limits(opts)

    if limit == :infinity or limit <= 0 do
      :ok
    else
      now = System.system_time(:second)
      expires_at = (div(now, window_seconds) + 1) * window_seconds
      key = {user_id, expires_at}

      case :ets.update_counter(@table, key, {2, 1}, {key, 0}) do
        count when count <= limit -> :ok
        _ -> {:error, :rate_limited}
      end
    end
  end

  @doc false
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  @doc false
  def sweep do
    if :ets.whereis(@table) != :undefined do
      now = System.system_time(:second)

      :ets.select_delete(@table, [
        {{{:"$1", :"$2"}, :"$3"}, [{:<, :"$2", now}], [true]}
      ])
    end

    :ok
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_ms)
  end

  defp resolve_limits(opts) do
    conf = Application.get_env(:xamt, __MODULE__, [])

    limit =
      Keyword.get(opts, :limit, Keyword.get(conf, :limit, @default_limit))

    window =
      Keyword.get(
        opts,
        :window_seconds,
        Keyword.get(conf, :window_seconds, @default_window_seconds)
      )

    {limit, window}
  end
end
