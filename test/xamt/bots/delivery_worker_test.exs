defmodule Xamt.Bots.DeliveryWorkerTest do
  use Xamt.DataCase, async: false

  import Ecto.Query

  alias Xamt.Accounts.Scope
  alias Xamt.{Bots, Channels, Messages, Servers}
  alias Xamt.Bots.{BotEvent, DeliveryWorker}
  alias Xamt.Repo

  setup do
    previous = Application.get_env(:xamt, DeliveryWorker)
    on_exit(fn -> Application.put_env(:xamt, DeliveryWorker, previous) end)

    owner = Xamt.AccountsFixtures.creator_fixture()
    owner_scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(owner_scope, %{"name" => "Webhook Hall"})
    channel = hd(Channels.list_channels(server.id))

    {:ok, %{installation: inst}} =
      Bots.create_and_install_bot(
        owner,
        server.id,
        %{
          "name" => "Hook",
          "description" => "webhook bot",
          "webhook_url" => "https://example.com/hooks/echo"
        },
        granted_scopes: ["channel.messages.read"],
        subscribed_events: ["message.created"],
        allowed_channel_ids: [channel.id]
      )

    %{owner_scope: owner_scope, channel: channel, installation: inst}
  end

  test "Oban drain delivers a pending webhook event", %{
    owner_scope: scope,
    channel: channel,
    installation: inst
  } do
    test_pid = self()

    Application.put_env(:xamt, DeliveryWorker,
      max_attempts: 5,
      timeout_ms: 5_000,
      req_options: [plug: {Req.Test, DeliveryWorker}]
    )

    Req.Test.stub(DeliveryWorker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook, conn.method, body, conn.req_headers})
      Req.Test.json(conn, %{ok: true})
    end)

    assert {:ok, message} =
             Messages.create_message(scope, channel.id, %{"content_html" => "<p>hi</p>"})

    event =
      Repo.one!(
        from e in BotEvent,
          where: e.bot_installation_id == ^inst.id and e.event_type == "message.created"
      )

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(queue: :bot_webhook_delivery)

    assert_received {:webhook, "POST", body, headers}
    assert Jason.decode!(body)["message"]["id"] == message.id

    header_map = Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
    assert header_map["x-xamt-event"] == "message.created"
    assert header_map["x-xamt-delivery"] == event.id
    assert header_map["x-xamt-signature-256"] =~ "sha256="

    assert Repo.get!(BotEvent, event.id).status == "delivered"
  end

  test "retry_event_delivery re-enqueues an Oban job", %{
    owner_scope: scope,
    channel: channel,
    installation: inst
  } do
    assert {:ok, _message} =
             Messages.create_message(scope, channel.id, %{"content_html" => "<p>retry</p>"})

    event =
      Repo.one!(
        from e in BotEvent,
          where: e.bot_installation_id == ^inst.id and e.event_type == "message.created"
      )

    now = DateTime.utc_now()

    from(e in BotEvent, where: e.id == ^event.id)
    |> Repo.update_all(set: [status: "dead", updated_at: now])

    from(j in Oban.Job,
      where: j.worker == "Xamt.Bots.DeliveryWorker",
      where: fragment("?->>'event_id' = ?", j.args, ^event.id)
    )
    |> Repo.update_all(set: [state: "cancelled", cancelled_at: now])

    assert {:ok, retried} = Bots.retry_event_delivery(event.id)
    assert retried.status == "pending"

    jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.worker == "Xamt.Bots.DeliveryWorker",
          where: fragment("?->>'event_id' = ?", j.args, ^event.id),
          where: j.state in ["available", "scheduled"]
      )

    assert length(jobs) == 1
  end
end
