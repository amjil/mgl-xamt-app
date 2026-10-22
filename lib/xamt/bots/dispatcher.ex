defmodule Xamt.Bots.Dispatcher do
  @moduledoc false

  import Ecto.Query
  alias Xamt.Bots.{Bot, BotInstallation, BotSubscription, BotEvent, Permissions}
  alias Xamt.Repo

  @doc """
  Runs inside an Ecto.Multi transaction: matches subscriptions, checks permissions, enqueues bot_events.
  """
  def enqueue_event_multi(multi, step_name, attrs) do
    Ecto.Multi.run(multi, step_name, fn repo, _changes ->
      {:ok, do_enqueue(repo, attrs)}
    end)
  end

  @doc """
  Enqueues in a standalone transaction; call from the domain layer after persisting messages.
  """
  def enqueue_event(attrs) do
    Repo.transact(fn ->
      {:ok, do_enqueue(Repo, attrs)}
    end)
  end

  defp do_enqueue(repo, %{
         server_id: server_id,
         channel_id: channel_id,
         event_type: event_type,
         actor_is_bot: actor_is_bot,
         payload: payload
       }) do
    if actor_is_bot do
      []
    else
      do_enqueue_targets(repo, server_id, channel_id, event_type, payload)
    end
  end

  defp do_enqueue(_repo, _attrs), do: []

  defp do_enqueue_targets(repo, server_id, channel_id, event_type, payload) do
    required_scope = Permissions.required_scope_for_event(event_type)

    if is_nil(required_scope) do
      []
    else
      now = DateTime.utc_now()

      query =
        from s in BotSubscription,
          join: i in BotInstallation,
          on: s.bot_installation_id == i.id,
          join: b in Bot,
          on: i.bot_id == b.id,
          where: s.event_type == ^event_type and s.is_enabled == true,
          where: i.server_id == ^server_id and i.status == "enabled",
          where: b.status == "active",
          where: fragment("? = ANY(?)", ^required_scope, i.granted_scopes),
          select: {b.id, i.id, s.filter}

      query =
        if channel_id do
          from [s, i, b] in query,
            where: is_nil(s.channel_id) or s.channel_id == ^channel_id,
            where:
              i.channel_id == ^channel_id or
                (is_nil(i.channel_id) and
                   (fragment("cardinality(?) = 0", i.allowed_channel_ids) or
                      ^channel_id in i.allowed_channel_ids))
        else
          query
        end

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
                "event_id" => event_id,
                "event_type" => event_type,
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
        {_count, inserted} = repo.insert_all(BotEvent, events_to_insert, returning: [:id])
        inserted
      end
    end
  end

  defp matches_filter?(_payload, filter) when map_size(filter) == 0, do: true

  defp matches_filter?(payload, filter) do
    Enum.all?(filter, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      Map.get(payload, key) == v or Map.get(payload, k) == v
    end)
  end
end
