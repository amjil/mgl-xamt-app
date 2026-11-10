defmodule XamtWeb.BotApiControllerTest do
  use XamtWeb.ConnCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Bots, Channels, Messages, Servers}

  setup %{conn: conn} do
    owner = Xamt.AccountsFixtures.creator_fixture()
    owner_scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(owner_scope, %{"name" => "API Hall"})
    channel = hd(Channels.list_channels(server.id))

    {:ok, %{installation: inst, token: %{raw_token: raw_token}, bot: bot}} =
      Bots.create_and_install_bot(
        owner,
        server.id,
        %{
          "name" => "API Bot",
          "webhook_url" => "https://bots.example.com/hooks/api"
        },
        granted_scopes: [
          "channel.messages.send",
          "channel.messages.read",
          "channel.messages.manage"
        ],
        subscribed_events: ["message.created"],
        allowed_channel_ids: [channel.id]
      )

    conn = put_req_header(conn, "authorization", "Bearer #{raw_token}")

    %{
      conn: conn,
      owner: owner,
      owner_scope: owner_scope,
      server: server,
      channel: channel,
      installation: inst,
      bot: bot,
      raw_token: raw_token
    }
  end

  test "GET /api/v1/bot/me", %{conn: conn, bot: bot, installation: inst} do
    conn = get(conn, ~p"/api/v1/bot/me")
    assert %{"ok" => true, "data" => data} = json_response(conn, 200)
    assert data["bot"]["id"] == bot.id
    assert data["installation"]["id"] == inst.id
  end

  test "lists only authorized channels", %{
    conn: conn,
    channel: channel,
    owner_scope: scope,
    server: server
  } do
    {:ok, _other} = Channels.create_channel(scope, server, %{"name" => "hidden"})

    conn = get(conn, ~p"/api/v1/bot/channels")
    assert %{"ok" => true, "data" => data} = json_response(conn, 200)
    assert Enum.map(data, & &1["id"]) == [channel.id]
  end

  test "posts a message as the bot", %{conn: conn, channel: channel} do
    conn =
      post(conn, ~p"/api/v1/bot/channels/#{channel.id}/messages", %{
        "body" => "hello from bot",
        "nonce" => "op-1"
      })

    assert %{"ok" => true, "data" => data} = json_response(conn, 201)
    assert data["body"] == "hello from bot"
    assert data["channel_id"] == channel.id
    assert data["author_type"] == "bot"
  end

  test "nonce replay returns same message", %{conn: conn, channel: channel} do
    conn1 =
      post(conn, ~p"/api/v1/bot/channels/#{channel.id}/messages", %{
        "body" => "once",
        "nonce" => "stable-nonce"
      })

    assert %{"ok" => true, "data" => first} = json_response(conn1, 201)

    conn2 =
      post(conn, ~p"/api/v1/bot/channels/#{channel.id}/messages", %{
        "body" => "once again",
        "nonce" => "stable-nonce"
      })

    assert %{"ok" => true, "data" => second, "replayed" => true} = json_response(conn2, 200)
    assert second["id"] == first["id"]
  end

  test "rejects unauthorized channel send", %{conn: conn, owner_scope: scope, server: server} do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "nope"})

    conn = post(conn, ~p"/api/v1/bot/channels/#{other.id}/messages", %{"body" => "no"})
    assert %{"ok" => false} = json_response(conn, 403)
  end

  test "revoked token is rejected", %{
    conn: conn,
    installation: inst,
    owner: owner,
    channel: channel
  } do
    assert {:ok, _} = Bots.revoke_installation_tokens(inst, owner)

    conn = post(conn, ~p"/api/v1/bot/channels/#{channel.id}/messages", %{"body" => "no"})
    assert %{"ok" => false, "error" => "invalid_or_revoked_token"} = json_response(conn, 401)
  end

  test "lists event subscriptions", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/bot/events/subscriptions")

    assert %{"ok" => true, "data" => [%{"event_type" => "message.created"}]} =
             json_response(conn, 200)
  end

  test "updates and deletes own bot message", %{conn: conn, channel: channel} do
    create =
      post(conn, ~p"/api/v1/bot/channels/#{channel.id}/messages", %{"body" => "edit me"})

    assert %{"data" => %{"id" => id}} = json_response(create, 201)

    update = patch(conn, ~p"/api/v1/bot/messages/#{id}", %{"body" => "edited"})
    assert %{"ok" => true, "data" => %{"body" => "edited"}} = json_response(update, 200)

    delete = delete(conn, ~p"/api/v1/bot/messages/#{id}")
    assert %{"ok" => true, "data" => data} = json_response(delete, 200)
    assert data["deleted_at"]
  end

  test "reads authorized channel messages", %{
    conn: conn,
    channel: channel,
    owner_scope: scope
  } do
    {:ok, _} = Messages.create_message(scope, channel.id, %{"content_html" => "<p>user msg</p>"})

    conn = get(conn, ~p"/api/v1/bot/channels/#{channel.id}/messages")
    assert %{"ok" => true, "data" => data} = json_response(conn, 200)
    assert Enum.any?(data, &(&1["body"] == "user msg"))
  end
end
