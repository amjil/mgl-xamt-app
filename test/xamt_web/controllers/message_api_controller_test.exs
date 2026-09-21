defmodule XamtWeb.MessageApiControllerTest do
  use XamtWeb.ConnCase, async: false

  import Xamt.AccountsFixtures

  alias Xamt.Accounts.Scope
  alias Xamt.Messages
  alias Xamt.Messages.RateLimiter
  alias Xamt.{Channels, Servers}

  setup %{conn: conn} do
    RateLimiter.reset()

    user = creator_fixture()
    scope = Scope.for_user(user)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Sync Server"})
    channel = hd(Channels.list_channels(server.id))

    %{
      conn: log_in_user(conn, user),
      user: user,
      scope: scope,
      server: server,
      channel: channel
    }
  end

  test "replays a queued message and broadcasts over PubSub", %{
    conn: conn,
    channel: channel
  } do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    conn =
      conn
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => channel.id,
        "content_html" => "<p>offline-queue</p>",
        "content_json" => ~s({"type":"rich_text","blocks":[]}),
        "content_type" => "rich_text"
      })

    assert %{"status" => "ok"} = json_response(conn, 200)
    assert_receive {:new_message, message}
    assert message.content_html =~ "offline-queue"
    assert hd(Messages.list_messages(channel.id)).id == message.id
  end

  test "accepts a JSON body the way the Service Worker sends it", %{
    conn: conn,
    channel: channel
  } do
    body =
      Jason.encode!(%{
        "channel_id" => channel.id,
        "content_html" => "<p>from-sw</p>",
        "content_json" => ~s({"type":"rich_text","blocks":[]}),
        "content_type" => "rich_text"
      })

    conn =
      conn
      |> with_csrf()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/messages/sync", body)

    assert %{"status" => "ok"} = json_response(conn, 200)
    assert hd(Messages.list_messages(channel.id)).content_html =~ "from-sw"
  end

  test "stores reply_to_id from the queued payload", %{
    conn: conn,
    channel: channel,
    scope: scope
  } do
    {:ok, parent} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>parent</p>",
        "content" => %{"type" => "rich_text"}
      })

    conn =
      conn
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => channel.id,
        "content_html" => "<p>queued-reply</p>",
        "content_type" => "rich_text",
        "reply_to_id" => parent.id
      })

    assert %{"status" => "ok"} = json_response(conn, 200)

    reply =
      Enum.find(Messages.list_messages(channel.id), fn message ->
        message.content_html =~ "queued-reply"
      end)

    assert reply.reply_to_id == parent.id
  end

  test "rejects guests with JSON 401", %{channel: channel} do
    conn =
      build_conn()
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => channel.id,
        "content_html" => "<p>nope</p>"
      })

    assert %{"status" => "error", "detail" => "unauthorized"} = json_response(conn, 401)
  end

  test "rejects non-members", %{channel: channel} do
    stranger = user_fixture()

    conn =
      build_conn()
      |> log_in_user(stranger)
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => channel.id,
        "content_html" => "<p>intruder</p>"
      })

    assert %{"status" => "error", "detail" => "forbidden"} = json_response(conn, 403)
    assert Messages.list_messages(channel.id) == []
  end

  test "returns 404 for an unknown channel", %{conn: conn} do
    conn =
      conn
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => Ecto.UUID.generate(),
        "content_html" => "<p>ghost</p>"
      })

    assert %{"status" => "error", "detail" => "not_found"} = json_response(conn, 404)
  end

  test "returns 422 for a malformed channel id", %{conn: conn} do
    conn =
      conn
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => "not-a-uuid",
        "content_html" => "<p>bad</p>"
      })

    assert %{"status" => "error", "detail" => "invalid_channel"} = json_response(conn, 422)
  end

  test "sanitizes XSS payloads from the sync API", %{conn: conn, channel: channel} do
    conn =
      conn
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => channel.id,
        "content_html" => ~s|<p>ok<img src=x onerror="alert(1)"><script>x</script></p>|,
        "content_type" => "rich_text"
      })

    assert %{"status" => "ok"} = json_response(conn, 200)
    [message] = Messages.list_messages(channel.id)
    refute message.content_html =~ "onerror"
    refute message.content_html =~ "<script"
    assert message.content_html =~ "ok"
  end

  test "rejects cross-channel reply_to_id", %{
    conn: conn,
    scope: scope,
    channel: channel,
    server: server
  } do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "elsewhere"})

    {:ok, foreign} =
      Messages.create_message(scope, other.id, %{
        "content_html" => "<p>parent</p>",
        "content" => %{"type" => "rich_text"}
      })

    conn =
      conn
      |> with_csrf()
      |> post(~p"/api/messages/sync", %{
        "channel_id" => channel.id,
        "content_html" => "<p>reply</p>",
        "reply_to_id" => foreign.id,
        "content_type" => "rich_text"
      })

    assert %{"status" => "error", "detail" => "invalid_reply"} = json_response(conn, 422)
    assert Messages.list_messages(channel.id) == []
  end

  defp with_csrf(conn) do
    conn = get(conn, ~p"/")
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-csrf-token", token)
  end
end
