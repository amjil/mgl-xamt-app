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
    assert has_element?(view, "#composer-send")

    render_hook(view, "send_message", %{
      "content_html" => "<p>a reply</p>",
      "content_json" => ~s({"type":"rich_text","blocks":[]}),
      "content_type" => "rich_text"
    })

    refute has_element?(view, "#reply-preview")
    assert render(view) =~ "a reply"
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

  test "search finds a message in another channel and patches to it", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "second"})

    {:ok, message} =
      Messages.create_message(scope, other.id, %{
        "content_html" => "<p>unique-needle</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    view |> form("#channel-search", %{q: "unique-needle"}) |> render_change()
    assert has_element?(view, "#search-hit-#{message.id}")
    assert render(view) =~ "second"

    view |> element("#search-hit-#{message.id}") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{other.slug}?highlight=#{message.id}")
    assert has_element?(view, "#message-list[data-highlight='#{message.id}']")
  end

  test "channel admin menu is always reachable", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#channel-menu-#{channel.id}")
  end

  test "invite settings expose a copyable absolute URL", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, invite} = Servers.create_invite(scope, server.id)
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#server-menu-drawer")

    view |> element("#server-menu") |> render_click()
    assert has_element?(view, "#server-menu-drawer")
    assert has_element?(view, "#server-menu-new-channel")

    view |> element("#server-menu-settings") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{channel.slug}/settings")

    assert has_element?(view, "#server-drawer")
    assert has_element?(view, "#copy-invite-#{invite.id}")
    html = render(view)
    assert html =~ "/invite/#{invite.code}"
    assert html =~ ~s(data-copy=")
  end

  test "admin can open the create-channel drawer from the plus control", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#create-channel-form")

    view |> element("#toggle-channel-form") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{channel.slug}/new")
    assert has_element?(view, "#server-drawer")
    assert has_element?(view, "#create-channel-form")
    assert has_element?(view, "#channel_name")
  end

  test "admin can open the create-channel drawer from the server menu overlay", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#server-menu-drawer")

    view |> element("#server-menu") |> render_click()
    assert has_element?(view, "#server-menu-drawer")

    view |> element("#server-menu-new-channel") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{channel.slug}/new")
    refute has_element?(view, "#server-menu-drawer")
    assert has_element?(view, "#server-drawer")
    assert has_element?(view, "#create-channel-form")
  end

  test "create channel drawer submits and patches to the new channel", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}/new")
    assert has_element?(view, "#create-channel-form")

    view
    |> form("#create-channel-form", %{channel: %{name: "random"}})
    |> render_submit()

    assert_patch(view, ~p"/servers/#{server.slug}/random")
    refute has_element?(view, "#create-channel-form")
    html = render(view)
    assert html =~ "random"
  end

  test "cancel closes the create-channel drawer", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}/new")
    view |> element("#create-channel-form-cancel") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#create-channel-form")
  end

  test "edit channel drawer can rename a channel", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    view |> element("#edit-channel-#{channel.id}") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{channel.slug}/edit/#{channel.slug}")
    assert has_element?(view, "#edit-channel-form")

    view
    |> form("#edit-channel-form", %{channel: %{name: "renamed"}})
    |> render_submit()

    assert_patch(view, ~p"/servers/#{server.slug}/renamed")
    html = render(view)
    assert html =~ "renamed"
  end

  test "members cannot open the create-channel drawer", %{
    conn: _conn,
    server: server,
    channel: channel
  } do
    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)
    member_conn = log_in_user(build_conn(), member)

    {:ok, view, _html} = live(member_conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#toggle-channel-form")
    refute has_element?(view, "#server-menu")

    assert {:error, {:live_redirect, %{to: to}}} =
             live(member_conn, ~p"/servers/#{server.slug}/#{channel.slug}/new")

    assert to == ~p"/servers/#{server.slug}/#{channel.slug}"
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

  test "mobile menu opens the channel drawer and backdrop closes it", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#mobile-nav-menu")
    assert has_element?(view, "#mobile-nav-members")
    assert has_element?(view, ".xamt-app--panel-messages")
    refute has_element?(view, "#drawer-backdrop")

    view |> element("#mobile-nav-menu") |> render_click()
    assert has_element?(view, ".xamt-app--panel-channels")
    assert has_element?(view, "#drawer-backdrop")

    view |> element("#drawer-backdrop") |> render_click()
    assert has_element?(view, ".xamt-app--panel-messages")
    refute has_element?(view, "#drawer-backdrop")
  end

  test "mobile members button opens the members drawer", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    view |> element("#mobile-nav-members") |> render_click()
    assert has_element?(view, ".xamt-app--panel-members")
    assert has_element?(view, "#drawer-backdrop")
  end

  test "selecting the current channel closes the mobile drawer", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    view |> element("#mobile-nav-menu") |> render_click()
    assert has_element?(view, ".xamt-app--panel-channels")

    view |> element("#channel-link-#{channel.slug}") |> render_click()
    assert has_element?(view, ".xamt-app--panel-messages")
    refute has_element?(view, "#drawer-backdrop")
  end

  test "clicking the open panel button again closes the drawer", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    view |> element("#mobile-nav-members") |> render_click()
    assert has_element?(view, ".xamt-app--panel-members")

    view |> element("#mobile-nav-members") |> render_click()
    assert has_element?(view, ".xamt-app--panel-messages")
    refute has_element?(view, "#drawer-backdrop")
  end

  test "mention_search replies with matching members", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    username = "pat#{System.unique_integer() |> abs()}"
    target = user_fixture(%{username: username, display_name: "Pat"})
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(target), server.id)

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    html = render_hook(view, "mention_search", %{"q" => username})
    assert html
  end

  test "a mention chip is highlighted for the mentioned user", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    username = "mia#{System.unique_integer() |> abs()}"
    mentioned = user_fixture(%{username: username, display_name: "Mia"})
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(mentioned), server.id)

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    render_hook(view, "send_message", %{
      "content_html" => ~s(<p>hi <span data-mention-id="#{mentioned.id}">@#{username}</span></p>),
      "content_json" => ~s({"type":"rich_text","blocks":[]}),
      "content_type" => "rich_text"
    })

    html = render(view)
    assert html =~ "xamt-mention"
    assert html =~ "@#{username}"
    refute html =~ "xamt-message--mentioned"

    mentioned_conn = log_in_user(build_conn(), mentioned)

    {:ok, mentioned_view, mentioned_html} =
      live(mentioned_conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(mentioned_view, "article.xamt-message--mentioned")
    assert has_element?(mentioned_view, "a.xamt-mention")
    assert mentioned_html =~ ~s(data-you="true")
    assert mentioned_html =~ ~s(href="/profile/#{username}")
  end
end
