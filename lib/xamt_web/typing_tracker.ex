defmodule XamtWeb.TypingTracker do
  @moduledoc """
  Dedicated `Phoenix.Tracker` for high-frequency typing indicators.

  Presence stays on stable online/offline state. This tracker collects
  `track` / `untrack` calls and `handle_diff/2` fires at most once per
  `broadcast_period` (default 2000ms), packing every join and leave in
  that window into a single `{:typing_diff, topic, joins, leaves}`
  message. That keeps large channels from an O(M×N) PubSub storm.

  Tracking is bound to the LiveView pid, so a crash or disconnect
  automatically drops the typist and avoids ghost indicators.
  """

  use Phoenix.Tracker

  @default_broadcast_period 2_000

  def start_link(opts) do
    opts =
      opts
      |> Keyword.put_new(:name, __MODULE__)
      |> Keyword.put_new(:pubsub_server, Xamt.PubSub)
      |> Keyword.put_new(:broadcast_period, broadcast_period(opts))
      |> Keyword.put_new(:log_level, false)

    Phoenix.Tracker.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :pubsub_server)

    {:ok,
     %{
       pubsub_server: server,
       node_name: Phoenix.PubSub.node_name(server)
     }}
  end

  @impl true
  def handle_diff(diff, state) do
    # Offload so a PubSub error cannot crash the tracker shard.
    Task.Supervisor.start_child(Xamt.TaskSupervisor, fn ->
      for {topic, {joins, leaves}} <- diff do
        Phoenix.PubSub.direct_broadcast!(
          state.node_name,
          state.pubsub_server,
          topic,
          {:typing_diff, topic, joins, leaves}
        )
      end
    end)

    {:ok, state}
  end

  def topic(%{id: id}), do: topic(id)
  def topic(channel_id), do: "typing:channel:#{channel_id}"

  def track_user(pid, channel, user) when is_pid(pid) do
    meta = %{
      username: user.username,
      display_name: user.display_name || user.username
    }

    case Phoenix.Tracker.track(__MODULE__, pid, topic(channel), user.id, meta) do
      {:ok, _ref} -> :ok
      {:error, {:already_tracked, _, _, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def untrack_user(pid, channel, user) when is_pid(pid) do
    Phoenix.Tracker.untrack(__MODULE__, pid, topic(channel), user.id)
  end

  def untrack_user(pid) when is_pid(pid) do
    Phoenix.Tracker.untrack(__MODULE__, pid)
  end

  def list(channel) do
    Phoenix.Tracker.list(__MODULE__, topic(channel))
  end

  def still_typing?(channel, user_id) do
    match?([_ | _], Phoenix.Tracker.get_by_key(__MODULE__, topic(channel), user_id))
  end

  def display_name(meta) when is_map(meta) do
    meta[:display_name] || meta["display_name"] || meta[:username] || meta["username"] || "?"
  end

  defp broadcast_period(opts) do
    opts
    |> Keyword.get(:broadcast_period)
    |> case do
      period when is_integer(period) and period > 0 ->
        period

      _ ->
        :xamt
        |> Application.get_env(__MODULE__, [])
        |> Keyword.get(:broadcast_period, @default_broadcast_period)
    end
  end
end
