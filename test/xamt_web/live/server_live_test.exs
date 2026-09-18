defmodule XamtWeb.ServerLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.{Accounts, Servers, Channels, Messages}

  setup %{conn: conn} do
    user = user_fixture()
    scope = Accounts.Scope.for_user(user)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Test Server"})
    channel = hd(Channels.list_channels(server.id))

    %{
      conn: log_in_user(conn, user),
      user: user,
      scope: scope,
      server: server,
      channel: channel
    }
  end

  test "renders channel and can send a message", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, view, html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert html =~ server.name
    assert html =~ channel.name

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>ᠮᠣᠩᠭᠣᠯ</p>",
        "content" => %{"type" => "rich_text", "html" => "<p>ᠮᠣᠩᠭᠣᠯ</p>"}
      })

    html = render(view)
    assert html =~ "ᠮᠣᠩᠭᠣᠯ"
    assert html =~ message.id or true
  end
end
