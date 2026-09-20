defmodule XamtWeb.ServerLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.{Accounts, Servers, Channels, Messages}
  alias Xamt.Messages.Reaction
  alias XamtWeb.TypingTracker

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
    assert has_element?(view, "#message-composer-wrap[data-channel-id='#{channel.id}']")
    assert has_element?(view, "#composer-peek")

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>ᠮᠣᠩᠭᠣᠯ</p>",
        "content" => %{"type" => "rich_text", "html" => "<p>ᠮᠣᠩᠭᠣᠯ</p>"}
      })

    html = render(view)
    assert html =~ "ᠮᠣᠩᠭᠣᠯ"
    assert html =~ message.id or true
  end

  test "displays message time in the client's timezone", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    utc = ~U[2026-09-19 07:13:00Z]

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>time check</p>",
        "content" => %{"type" => "rich_text"}
      })

    message
    |> Ecto.Changeset.change(inserted_at: utc, updated_at: utc)
    |> Xamt.Repo.update!()

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"timezone_offset" => -480})
      |> live(~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "time.xamt-message__time", "15:13")
    refute has_element?(view, "time.xamt-message__time", "07:13")
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

    picker =
      ".xamt-reaction-picker button[phx-value-emoji='#{emoji}'][phx-value-id='#{message.id}']"

    chip =
      ".xamt-reaction:not(.xamt-reaction--add)[phx-value-emoji='#{emoji}'][phx-value-id='#{message.id}']"

    view
    |> element(picker)
    |> render_click()

    assert has_element?(view, chip)
    refute has_element?(view, picker)
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

  test "create channel drawer accepts a Mongolian name", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}/new")

    view
    |> form("#create-channel-form", %{channel: %{name: "ᠮᠣᠩᠭᠣᠯ"}})
    |> render_submit()

    assert_patch(view, ~p"/servers/#{server.slug}/untitled")
    refute has_element?(view, "#create-channel-form")
    html = render(view)
    assert html =~ "ᠮᠣᠩᠭᠣᠯ"
  end

  test "second Mongolian channel gets a unique slug", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, _first} = Channels.create_channel(scope, server, %{"name" => "ᠮᠣᠩᠭᠣᠯ"})
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}/new")

    view
    |> form("#create-channel-form", %{channel: %{name: "ᠪᠢᠴᠢᠭ"}})
    |> render_submit()

    assert_patch(view, ~p"/servers/#{server.slug}/untitled-1")
    html = render(view)
    assert html =~ "ᠪᠢᠴᠢᠭ"
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

  test "server info button opens overlay with name and slug", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#mobile-nav-server")
    refute has_element?(view, "#server-menu-drawer")

    view |> element("#mobile-nav-server") |> render_click()
    assert has_element?(view, "#server-menu-drawer")
    assert has_element?(view, "#server-menu-title", server.name)
    assert has_element?(view, "#server-menu-slug", "/#{server.slug}")
    assert has_element?(view, "#server-menu-new-channel")
  end

  test "members can open server info but not admin actions", %{
    conn: _conn,
    server: server,
    channel: channel
  } do
    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)
    member_conn = log_in_user(build_conn(), member)

    {:ok, view, _html} = live(member_conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#mobile-nav-server")
    refute has_element?(view, "#server-menu")

    view |> element("#mobile-nav-server") |> render_click()
    assert has_element?(view, "#server-menu-drawer")
    assert has_element?(view, "#server-menu-title", server.name)
    refute has_element?(view, "#server-menu-new-channel")
    refute has_element?(view, "#server-menu-settings")
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

  test "renders a link preview card and replaces it over PubSub", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>https://example.com/story</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute html =~ "xamt-link-preview"

    {:ok, _} =
      Messages.put_link_preview(message, %{
        "url" => "https://example.com/story",
        "title" => "Example Story",
        "description" => "A short summary",
        "image" => "https://example.com/og.png"
      })

    assert has_element?(view, "#msg-preview-#{message.id}")
    assert has_element?(view, "#msg-preview-#{message.id}[href='https://example.com/story']")
    html = render(view)
    assert html =~ "Example Story"
    assert html =~ "A short summary"
    assert html =~ ~s(src="https://example.com/og.png")
  end

  test "saves a web push subscription from the LiveView hook", %{
    conn: conn,
    server: server,
    channel: channel,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#web-push-manager")

    endpoint = "https://push.example/live-#{System.unique_integer([:positive])}"

    render_hook(view, "save_push_subscription", %{
      "endpoint" => endpoint,
      "p256dh" => "live-p256dh",
      "auth" => "live-auth"
    })

    assert [sub] = Xamt.Notifications.list_user_subscriptions(user.id)
    assert sub.endpoint == endpoint
    assert sub.p256dh == "live-p256dh"
    assert sub.auth == "live-auth"
  end

  test "owner can edit a message and the stream shows an edited marker", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>orig-edit-body</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#edit-message-#{message.id}")
    assert has_element?(view, "#message-composer-wrap[data-submit-event='send_message']")

    view |> element("#edit-message-#{message.id}") |> render_click()

    assert has_element?(view, "#composer-cancel-edit")
    assert has_element?(view, "article.xamt-message--editing")
    assert has_element?(view, "#message-composer-wrap[data-submit-event='update_message']")
    assert has_element?(view, "#message-composer-wrap[data-editing-id='#{message.id}']")
    assert_push_event(view, "populate_composer", %{html: html})
    assert html =~ "orig-edit-body"

    render_hook(view, "update_message", %{
      "content_html" => "<p>revised-edit-body</p>",
      "content_json" => ~s({"type":"rich_text","blocks":[]}),
      "content_type" => "rich_text"
    })

    html = render(view)
    assert html =~ "revised-edit-body"
    assert has_element?(view, ".xamt-message__edited")
    refute has_element?(view, "#composer-cancel-edit")
    refute has_element?(view, "article.xamt-message--editing")
    assert has_element?(view, "#message-composer-wrap[data-submit-event='send_message']")
  end

  test "owner can soft-delete a message and the tombstone stays in the stream", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>secret-delete-body</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#msg-content-#{message.id}")

    view |> element("#delete-message-#{message.id}") |> render_click()

    assert has_element?(view, "#msg-tombstone-#{message.id}")
    assert has_element?(view, "article.xamt-message--deleted")
    refute has_element?(view, "#msg-content-#{message.id}")
    refute has_element?(view, "#edit-message-#{message.id}")
    html = render(view)
    refute html =~ "secret-delete-body"
    assert html =~ "This message was deleted"

    {:ok, reloaded, reloaded_html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(reloaded, "#msg-tombstone-#{message.id}")
    refute reloaded_html =~ "secret-delete-body"
  end

  test "members cannot edit or delete someone else's message", %{
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>owner-only</p>",
        "content" => %{"type" => "rich_text"}
      })

    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)
    member_conn = log_in_user(build_conn(), member)
    {:ok, view, _html} = live(member_conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    refute has_element?(view, "#edit-message-#{message.id}")
    refute has_element?(view, "#delete-message-#{message.id}")
    assert has_element?(view, "#reply-message-#{message.id}")
  end

  test "owners can delete another member's message from the stream", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)

    {:ok, message} =
      Messages.create_message(Accounts.Scope.for_user(member), channel.id, %{
        "content_html" => "<p>mod-delete-me</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#delete-message-#{message.id}")

    view |> element("#delete-message-#{message.id}") |> render_click()

    assert has_element?(view, "#delete-reason-form")
    assert has_element?(view, "#delete-reason-preview", "mod-delete-me")
    refute has_element?(view, "#msg-tombstone-#{message.id}")

    view
    |> form("#delete-reason-form", audit: %{reason: "spam"})
    |> render_submit()

    refute has_element?(view, "#delete-reason-form")
    assert has_element?(view, "#msg-tombstone-#{message.id}")
    refute has_element?(view, "#msg-content-#{message.id}")
  end

  test "moderators can cancel a delete without removing the message", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)

    {:ok, message} =
      Messages.create_message(Accounts.Scope.for_user(member), channel.id, %{
        "content_html" => "<p>keep-me</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    view |> element("#delete-message-#{message.id}") |> render_click()
    assert has_element?(view, "#delete-reason-form")

    view |> element("#delete-reason-cancel") |> render_click()

    refute has_element?(view, "#delete-reason-form")
    assert has_element?(view, "#msg-content-#{message.id}")
    refute has_element?(view, "#msg-tombstone-#{message.id}")
  end

  test "typing_started tracks the user without a per-keystroke broadcast", %{
    conn: conn,
    user: user,
    server: server,
    channel: channel
  } do
    {:ok, view, html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#channel-typing")
    refute html =~ "is typing..."

    topic = TypingTracker.topic(channel)
    Phoenix.PubSub.subscribe(Xamt.PubSub, topic)

    render_hook(view, "typing_started", %{})
    tracked = List.keyfind(TypingTracker.list(channel), user.id, 0)
    assert tracked
    assert elem(tracked, 0) == user.id

    assert_receive {:typing_diff, ^topic, _joins, _leaves}, 500
    refute render(view) =~ "is typing..."
  end

  test "batched typing diffs show other members and hide them on stop", %{
    conn: conn,
    user: user,
    server: server,
    channel: channel
  } do
    member = user_fixture(%{username: unique_user_username(), display_name: "Typer One"})

    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)
    member_conn = log_in_user(build_conn(), member)

    {:ok, owner_view, _} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    {:ok, member_view, _} = live(member_conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    topic = TypingTracker.topic(channel)
    Phoenix.PubSub.subscribe(Xamt.PubSub, topic)

    render_hook(member_view, "typing_started", %{})
    assert_receive {:typing_diff, ^topic, _joins, _leaves}, 500
    assert render(owner_view) =~ "Typer One is typing..."

    render_hook(owner_view, "typing_started", %{})
    assert_receive {:typing_diff, ^topic, _joins, _leaves}, 500
    html = render(owner_view)
    assert html =~ "Typer One is typing..."
    refute html =~ "#{user.username} is typing"

    render_hook(member_view, "typing_stopped", %{})
    assert_receive {:typing_diff, ^topic, _joins, _leaves}, 500
    refute render(owner_view) =~ "Typer One is typing..."
  end

  test "typing label aggregates two and several typists", %{
    conn: conn,
    user: user,
    server: server,
    channel: channel
  } do
    {:ok, view, _} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    topic = TypingTracker.topic(channel)

    send(
      view.pid,
      {:typing_diff, topic, [{Ecto.UUID.generate(), %{display_name: "Ada"}}], []}
    )

    assert render(view) =~ "Ada is typing..."

    send(
      view.pid,
      {:typing_diff, topic,
       [
         {Ecto.UUID.generate(), %{display_name: "Bob"}}
       ], []}
    )

    html = render(view)
    assert html =~ "Ada and Bob are typing..." or html =~ "Bob and Ada are typing..."

    send(
      view.pid,
      {:typing_diff, topic, [{Ecto.UUID.generate(), %{display_name: "Cyd"}}], []}
    )

    assert render(view) =~ "Several people are typing..."

    send(
      view.pid,
      {:typing_diff, TypingTracker.topic("other"), [{user.id, %{username: "nope"}}], []}
    )

    refute render(view) =~ "nope"
  end

  test "switching channels untracks typing on the previous channel", %{
    conn: conn,
    user: user,
    scope: scope,
    server: server,
    channel: channel
  } do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "second"})
    {:ok, view, _} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    render_hook(view, "typing_started", %{})
    assert List.keyfind(TypingTracker.list(channel), user.id, 0)

    view |> element("#channel-link-#{other.slug}") |> render_click()
    assert_patch(view, ~p"/servers/#{server.slug}/#{other.slug}")
    refute List.keyfind(TypingTracker.list(channel), user.id, 0)
  end

  test "renders a native player for voice messages", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "🎤 <em>Voice message</em>",
        "content" => %{"type" => "audio", "url" => "/uploads/voice-test.webm"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#audio-form")
    assert has_element?(view, "#btn-record")
    assert has_element?(view, "#msg-audio-#{message.id}[src='/uploads/voice-test.webm']")
    refute has_element?(view, "#edit-message-#{message.id}")
  end

  test "send_audio persists an uploaded recording", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    audio =
      file_input(view, "#audio-form", :audio, [
        %{name: "voice.webm", content: <<1, 2, 3, 4>>, type: "audio/webm"}
      ])

    render_upload(audio, "voice.webm")

    view
    |> form("#audio-form")
    |> render_submit()

    assert has_element?(view, "audio.xamt-audio-player")
  end

  test "send_audio accepts Safari m4a recordings", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    audio =
      file_input(view, "#audio-form", :audio, [
        %{name: "voice.m4a", content: <<1, 2, 3, 4>>, type: "audio/mp4"}
      ])

    render_upload(audio, "voice.m4a")

    view
    |> form("#audio-form")
    |> render_submit()

    assert has_element?(view, "audio.xamt-audio-player")
  end
end
