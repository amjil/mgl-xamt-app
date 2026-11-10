defmodule Xamt.BotsTest do
  use Xamt.DataCase, async: false

  import Ecto.Query

  alias Xamt.Accounts.Scope
  alias Xamt.{Bots, Channels, Messages, Servers}
  alias Xamt.Bots.{BotEvent, BotIdempotencyKey, BotToken}
  alias Xamt.Repo

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    owner_scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(owner_scope, %{"name" => "Bot Hall"})
    channel = hd(Channels.list_channels(server.id))

    {:ok, %{bot: bot, installation: inst, token: %{raw_token: raw_token}}} =
      Bots.create_and_install_bot(
        owner,
        server.id,
        %{
          "name" => "Echo",
          "description" => "echo bot",
          "webhook_url" => "https://bots.example.com/hooks/echo"
        },
        granted_scopes: [
          "channel.messages.send",
          "channel.messages.read",
          "channel.messages.manage"
        ],
        subscribed_events: ["message.created", "message.updated", "message.deleted"],
        allowed_channel_ids: [channel.id]
      )

    %{
      owner: owner,
      owner_scope: owner_scope,
      server: server,
      channel: channel,
      bot: bot,
      installation: inst,
      raw_token: raw_token
    }
  end

  test "authenticate_token accepts issued token and rejects revoked", %{
    raw_token: raw_token,
    installation: inst,
    owner: owner
  } do
    assert {:ok, token} = Bots.authenticate_token(raw_token)
    assert token.bot_installation_id == inst.id
    assert Repo.get!(BotToken, token.id).last_used_at

    assert {:ok, _} = Bots.revoke_installation_tokens(inst, owner)
    assert {:error, :invalid_token} = Bots.authenticate_token(raw_token)
  end

  test "uninstall stops authentication", %{raw_token: raw_token, installation: inst, owner: owner} do
    assert {:ok, _} = Bots.uninstall_bot(inst, owner)
    assert {:error, :invalid_token} = Bots.authenticate_token(raw_token)
  end

  test "message create and outbox share one transaction", %{
    owner_scope: scope,
    channel: channel,
    installation: inst
  } do
    assert {:ok, message} =
             Messages.create_message(scope, channel.id, %{"content_html" => "<p>hello bot</p>"})

    events =
      Repo.all(
        from e in BotEvent,
          where: e.bot_installation_id == ^inst.id and e.event_type == "message.created"
      )

    assert length(events) == 1
    assert hd(events).payload["message"]["id"] == message.id
    assert hd(events).status == "pending"

    jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.worker == "Xamt.Bots.DeliveryWorker",
          where: fragment("?->>'event_id' = ?", j.args, ^hd(events).id)
      )

    assert length(jobs) == 1
    assert hd(jobs).queue == "bot_webhook_delivery"
  end

  test "rotate_installation_token invalidates old token", %{
    raw_token: raw_token,
    installation: inst
  } do
    assert {:ok, %{raw_token: new_token}} = Bots.rotate_installation_token(inst)
    assert {:error, :invalid_token} = Bots.authenticate_token(raw_token)
    assert {:ok, _} = Bots.authenticate_token(new_token)
  end

  test "authorize_channel_action respects allowlist", %{
    raw_token: raw_token,
    channel: channel,
    owner_scope: scope,
    server: server
  } do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "other-room"})
    assert {:ok, token} = Bots.authenticate_token(raw_token)
    assert :ok = Bots.authorize_channel_action(token, channel, "channel.messages.send")

    assert {:error, :channel_not_authorized} =
             Bots.authorize_channel_action(token, other, "channel.messages.send")
  end

  test "idempotency key remembers nonce", %{
    installation: inst,
    owner_scope: scope,
    channel: channel
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{"content_html" => "<p>n</p>"})

    assert {:ok, _} = Bots.remember_nonce(inst.id, "nonce-1", message.id)
    assert %BotIdempotencyKey{message: found} = Bots.find_message_by_nonce(inst.id, "nonce-1")
    assert found.id == message.id
  end

  test "emits member.left when a member is kicked", %{
    owner: owner,
    owner_scope: owner_scope,
    server: server,
    installation: inst
  } do
    subscribe_events!(inst, ["member.left"], ["server.members.events"])

    member = Xamt.AccountsFixtures.user_fixture()
    {:ok, _} = Servers.add_member(Scope.for_user(member), server.id)

    assert {:ok, _} = Servers.kick_member(owner_scope, server.id, member.id)

    events =
      Repo.all(
        from e in BotEvent,
          where: e.bot_installation_id == ^inst.id and e.event_type == "member.left"
      )

    assert length(events) == 1
    assert hd(events).payload["member"]["id"] == member.id
    assert hd(events).payload["data"]["removed_by"]["id"] == owner.id
  end

  test "emits channel.created for new channels", %{
    owner_scope: scope,
    server: server,
    installation: inst
  } do
    subscribe_events!(inst, ["channel.created"], ["channel.messages.read"])

    assert {:ok, channel} = Channels.create_channel(scope, server, %{"name" => "announcements"})

    events =
      Repo.all(
        from e in BotEvent,
          where: e.bot_installation_id == ^inst.id and e.event_type == "channel.created"
      )

    assert length(events) == 1
    assert hd(events).channel_id == channel.id
    assert hd(events).payload["channel"]["id"] == channel.id
  end

  test "emits bot.mentioned only for the mentioned bot", %{
    owner_scope: scope,
    channel: channel,
    bot: bot,
    installation: inst
  } do
    subscribe_events!(inst, ["bot.mentioned"], ["channel.messages.read"])
    bot = Repo.preload(bot, :bot_user)

    html =
      ~s(<p>hey <span data-mention-id="#{bot.bot_user_id}">@#{bot.bot_user.username}</span></p>)

    assert {:ok, message} =
             Messages.create_message(scope, channel.id, %{"content_html" => html})

    events =
      Repo.all(
        from e in BotEvent,
          where: e.bot_installation_id == ^inst.id and e.event_type == "bot.mentioned"
      )

    assert length(events) == 1
    assert hd(events).bot_id == bot.id
    assert hd(events).payload["message"]["id"] == message.id
    assert bot.id in hd(events).payload["data"]["mentioned_bot_ids"]
  end

  defp subscribe_events!(inst, events, scopes) do
    {:ok, _} =
      Bots.update_installation_config(inst, %{
        "status" => "enabled",
        "granted_scopes" => Enum.uniq(inst.granted_scopes ++ scopes),
        "allowed_channel_ids" => inst.allowed_channel_ids,
        "subscribed_events" => events
      })
  end
end
