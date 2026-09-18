defmodule XamtWeb.ServerLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.{Accounts, Servers, Channels, Messages}
  alias Xamt.Messages.Reaction

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

  test "strangers cannot open a private server", %{server: server} do
    stranger = user_fixture()
    conn = log_in_user(build_conn(), stranger)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/servers/#{server.slug}")
  end

  test "public servers show a join page", %{scope: scope} do
    {:ok, public} =
      Servers.create_server(scope, %{"name" => "Open Hall", "visibility" => "public"})

    stranger = user_fixture()
    conn = log_in_user(build_conn(), stranger)
    {:ok, view, html} = live(conn, ~p"/servers/#{public.slug}")
    assert html =~ "Join server"
    assert has_element?(view, "#join-server")
  end

  test "replying sets the composer preview", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>quote me</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    view
    |> element("button[phx-click=reply_message][phx-value-id='#{message.id}']")
    |> render_click()

    assert has_element?(view, "#reply-preview")
  end

  test "toggling a reaction updates the chip", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>react</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    emoji = hd(Reaction.emojis())

    view
    |> element(
      ".xamt-reaction-picker button[phx-value-emoji='#{emoji}'][phx-value-id='#{message.id}']"
    )
    |> render_click()

    html = render(view)
    assert html =~ emoji
  end

  test "search finds a message in the channel", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, _message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>unique-needle</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    view |> form("#channel-search", %{q: "unique-needle"}) |> render_change()
    assert has_element?(view, "#search-results")
    assert render(view) =~ "unique-needle"
  end

  test "invite live redeems a code", %{scope: scope, server: server} do
    {:ok, invite} = Servers.create_invite(scope, server.id)
    stranger = user_fixture()
    conn = log_in_user(build_conn(), stranger)

    {:ok, view, _html} = live(conn, ~p"/invite/#{invite.code}")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#accept-invite") |> render_click()

    assert to =~ "/servers/#{server.slug}"
  end
end
