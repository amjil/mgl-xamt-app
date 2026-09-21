defmodule Xamt.Notifications.WebPushTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Notifications, Servers}
  alias Xamt.Notifications.WebPush

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Push"})
    channel = hd(Channels.list_channels(server.id))
    previous = Application.get_env(:xamt, WebPush)

    on_exit(fn -> Application.put_env(:xamt, WebPush, previous) end)

    %{scope: scope, channel: channel, owner: owner, server: server}
  end

  test "sends a web push when a member is mentioned", %{
    scope: scope,
    channel: channel,
    server: server,
    owner: owner
  } do
    mentioned = mentionable_member(server)

    {:ok, sub} =
      Notifications.save_subscription(mentioned.id, %{
        "endpoint" => "https://push.example/mention",
        "p256dh" => "p256dh",
        "auth" => "auth"
      })

    test_pid = self()

    enable_push!(fn payload, sub_info ->
      send(test_pid, {:web_push, payload, sub_info})
      {:ok, %{status_code: 201}}
    end)

    {:ok, _message} = mention_message(scope, channel, mentioned)

    assert_receive {:web_push, payload, sub_info}
    decoded = Jason.decode!(payload)
    assert decoded["title"] == "Xamt: you were mentioned"
    assert decoded["body"] =~ owner.username
    assert decoded["url"] == "/servers/#{server.slug}/#{channel.slug}"
    assert sub_info.endpoint == sub.endpoint
    assert sub_info.keys.p256dh == "p256dh"
  end

  test "does not notify the author of a self-mention", %{
    scope: scope,
    channel: channel,
    owner: owner
  } do
    enable_push!(fn _payload, _sub_info ->
      send(self(), :unexpected_push)
      {:ok, %{status_code: 201}}
    end)

    {:ok, _} =
      Notifications.save_subscription(owner.id, %{
        "endpoint" => "https://push.example/self",
        "p256dh" => "p256dh",
        "auth" => "auth"
      })

    {:ok, _} = mention_message(scope, channel, owner)

    refute_received :unexpected_push
  end

  test "drops a subscription when the push service returns 410", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    mentioned = mentionable_member(server)

    {:ok, sub} =
      Notifications.save_subscription(mentioned.id, %{
        "endpoint" => "https://push.example/gone",
        "p256dh" => "p256dh",
        "auth" => "auth"
      })

    enable_push!(fn _payload, _sub_info -> {:error, %{status_code: 410}} end)

    {:ok, _} = mention_message(scope, channel, mentioned)

    assert Notifications.list_user_subscriptions(mentioned.id) == []
    refute Xamt.Repo.get(Xamt.Notifications.PushSubscription, sub.id)
  end

  test "encrypts a payload and posts it to the subscription endpoint", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    mentioned = mentionable_member(server)
    {ua_public, _ua_private} = :crypto.generate_key(:ecdh, :prime256v1)

    {:ok, _} =
      Notifications.save_subscription(mentioned.id, %{
        "endpoint" => "https://push.example/real",
        "p256dh" => Base.url_encode64(ua_public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      })

    test_pid = self()

    Application.put_env(:xamt, WebPush,
      enabled: true,
      async: false,
      req_options: [
        plug: fn conn ->
          send(
            test_pid,
            {:push_http, conn.method, conn.host, conn.request_path, conn.req_headers}
          )

          Plug.Conn.send_resp(conn, 201, "")
        end
      ]
    )

    {:ok, _} = mention_message(scope, channel, mentioned)

    assert_received {:push_http, "POST", "push.example", "/real", headers}
    header_map = Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
    assert header_map["authorization"] =~ "vapid t="
    assert header_map["content-type"] == "application/octet-stream"
  end

  defp mentionable_member(server) do
    user =
      Xamt.AccountsFixtures.user_fixture(%{
        username: "mia#{System.unique_integer() |> abs()}"
      })

    {:ok, _} = Servers.join_server(Scope.for_user(user), server.id)
    user
  end

  defp mention_message(scope, channel, user) do
    Messages.create_message(scope, channel.id, %{
      "content_html" => ~s(<p><span data-mention-id="#{user.id}">@#{user.username}</span></p>),
      "content" => %{"type" => "rich_text"}
    })
  end

  defp enable_push!(sender) do
    Application.put_env(:xamt, WebPush, enabled: true, async: false, sender: sender)
  end
end
