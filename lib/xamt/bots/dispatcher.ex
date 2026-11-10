defmodule Xamt.Bots.Dispatcher do
  @moduledoc false

  import Ecto.Query
  alias Xamt.Bots.{Bot, BotInstallation, BotSubscription, BotEvent, Permissions}
  alias Xamt.Repo

  # These events are about the server (or a new channel on it), not gated by
  # installation channel allowlists. The concrete channel_id is still stored
  # on the event row / payload when provided.
  @server_scoped_events ~w(member.joined member.left channel.created)

  @doc """
  Runs inside an Ecto.Multi transaction: matches subscriptions, checks permissions, enqueues bot_events.
  """
  def enqueue_event_multi(multi, step_name, attrs) when is_map(attrs) do
    Ecto.Multi.run(multi, step_name, fn repo, _changes ->
      {:ok, do_enqueue(repo, attrs)}
    end)
  end

  def enqueue_event_multi(multi, step_name, attrs_fun) when is_function(attrs_fun, 1) do
    Ecto.Multi.run(multi, step_name, fn repo, changes ->
      {:ok, do_enqueue(repo, attrs_fun.(changes))}
    end)
  end

  @doc """
  Enqueues in a standalone transaction; prefer `enqueue_event_multi/3` when possible.
  """
  def enqueue_event(attrs) do
    if bot_webhook_delivery_enabled?() do
      Repo.transact(fn ->
        {:ok, do_enqueue(Repo, attrs)}
      end)
    else
      {:ok, []}
    end
  end

  defp do_enqueue(_repo, %{server_id: nil}), do: []

  defp do_enqueue(
         repo,
         %{
           server_id: server_id,
           channel_id: channel_id,
           event_type: event_type,
           actor_is_bot: actor_is_bot,
           payload: payload
         } = attrs
       ) do
    cond do
      not bot_webhook_delivery_enabled?() ->
        []

      actor_is_bot ->
        []

      true ->
        only_bot_ids = Map.get(attrs, :only_bot_ids) || Map.get(attrs, "only_bot_ids")

        do_enqueue_targets(repo, server_id, channel_id, event_type, payload, only_bot_ids)
    end
  end

  defp do_enqueue(_repo, _attrs), do: []

  defp do_enqueue_targets(repo, server_id, channel_id, event_type, payload, only_bot_ids) do
    required_scope = Permissions.required_scope_for_event(event_type)

    cond do
      is_nil(required_scope) ->
        []

      # Mentions must name the target bot(s); never fan out to every subscriber.
      event_type == "bot.mentioned" and (only_bot_ids == nil or only_bot_ids == []) ->
        []

      true ->
        now = DateTime.utc_now()

        query =
          from s in BotSubscription,
            join: i in BotInstallation,
            on: s.bot_installation_id == i.id,
            join: b in Bot,
            on: i.bot_id == b.id,
            where: s.event_type == ^event_type and s.is_enabled == true,
            where: i.server_id == ^server_id and i.status == "enabled",
            where: is_nil(i.uninstalled_at),
            where: b.status == "active",
            where: fragment("? = ANY(?)", ^required_scope, i.granted_scopes),
            select: {b.id, i.id, s.filter}

        query =
          case only_bot_ids do
            ids when is_list(ids) and ids != [] ->
              from [s, i, b] in query, where: b.id in ^ids

            _ ->
              query
          end

        query = apply_channel_scope(query, channel_id, event_type)

        insert_matched_events(repo, query, server_id, channel_id, event_type, payload, now)
    end
  end

  defp insert_matched_events(repo, query, server_id, channel_id, event_type, payload, now) do
    matched_targets = repo.all(query)

    events_to_insert =
      matched_targets
      |> Enum.filter(fn {_bot_id, _inst_id, filter} -> matches_filter?(payload, filter) end)
      |> Enum.map(fn {bot_id, inst_id, _filter} ->
        event_id = Ecto.UUID.generate()

        %{
          id: event_id,
          bot_id: bot_id,
          bot_installation_id: inst_id,
          server_id: server_id,
          channel_id: channel_id,
          event_type: event_type,
          payload:
            Map.merge(payload, %{
              "id" => event_id,
              "type" => event_type,
              "event_id" => event_id,
              "event_type" => event_type,
              "version" => 1,
              "created_at" => DateTime.to_iso8601(now),
              "server_id" => server_id,
              "channel_id" => channel_id,
              "timestamp" => DateTime.to_iso8601(now)
            }),
          status: "pending",
          retry_count: 0,
          max_retries: 5,
          next_attempt_at: now,
          execution_result: %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    if events_to_insert == [] do
      []
    else
      {_count, inserted} =
        repo.insert_all(BotEvent, events_to_insert, returning: [:id, :max_retries])

      jobs =
        Enum.map(inserted, fn event ->
          Xamt.Bots.DeliveryWorker.enqueue_changeset(event.id, max_attempts: event.max_retries)
        end)

      # Same Repo transaction as the outbox insert when called from Multi/transact.
      _ = Oban.insert_all(jobs)
      inserted
    end
  end

  defp apply_channel_scope(query, channel_id, event_type)
       when is_binary(channel_id) and event_type not in @server_scoped_events do
    from [s, i, b] in query,
      where: is_nil(s.channel_id) or s.channel_id == ^channel_id,
      where:
        i.channel_id == ^channel_id or
          (is_nil(i.channel_id) and
             (fragment("cardinality(?) = 0", i.allowed_channel_ids) or
                ^channel_id in i.allowed_channel_ids))
  end

  defp apply_channel_scope(query, _channel_id, _event_type), do: query

  defp matches_filter?(_payload, filter) when map_size(filter) == 0, do: true

  defp matches_filter?(payload, filter) do
    Enum.all?(filter, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      Map.get(payload, key) == v or Map.get(payload, k) == v
    end)
  end

  defp bot_webhook_delivery_enabled? do
    Application.get_env(:xamt, :bot_webhook_delivery_enabled, true)
  end
end
