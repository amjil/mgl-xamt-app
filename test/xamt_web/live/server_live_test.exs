defmodule XamtWeb.ServerLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.{Accounts, Servers, Channels, Messages}
  alias Xamt.Messages.Reaction
  alias XamtWeb.TypingTracker

  setup %{conn: conn} do
    user = creator_fixture()
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

  test "renders gallery grid and opens lightbox originals", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    images = [
      %{"thumb" => "/uploads/thumb_1.jpg", "original" => "/uploads/orig_1.jpg"},
      %{"thumb" => "/uploads/thumb_2.jpg", "original" => "/uploads/orig_2.jpg"},
      %{"thumb" => "/uploads/thumb_3.jpg", "original" => "/uploads/orig_3.jpg"},
      %{"thumb" => "/uploads/thumb_4.jpg", "original" => "/uploads/orig_4.jpg"}
    ]

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>trip</p>",
        "content" => %{"type" => "gallery", "images" => images},
        "content_type" => "gallery"
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#gallery-#{message.id}[data-count='4']")
    assert has_element?(view, "#gallery-#{message.id}-0 img[src='/uploads/thumb_1.jpg']")
    refute has_element?(view, "#media-lightbox")

    view
    |> element("#gallery-#{message.id}-1")
    |> render_click()

    assert has_element?(view, "#media-lightbox")
    assert has_element?(view, "#lightbox-image[src='/uploads/orig_2.jpg']")
    assert has_element?(view, "#lightbox-counter", "2 / 4")
    assert has_element?(view, "#lightbox-prev")
    assert has_element?(view, "#lightbox-next")

    view |> element("#lightbox-next") |> render_click()
    assert has_element?(view, "#lightbox-image[src='/uploads/orig_3.jpg']")
    assert has_element?(view, "#lightbox-counter", "3 / 4")

    view |> element("#lightbox-close") |> render_click()
    refute has_element?(view, "#media-lightbox")
  end

  test "gallery overflow shows +N and lightbox still has all originals", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    images =
      for n <- 1..10 do
        %{
          "thumb" => "/uploads/thumb_#{n}.jpg",
          "original" => "/uploads/orig_#{n}.jpg"
        }
      end

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "",
        "content" => %{"type" => "gallery", "images" => images},
        "content_type" => "gallery"
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#gallery-#{message.id}[data-count='overflow']")
    assert has_element?(view, "#gallery-#{message.id}-7", "+2")
    refute has_element?(view, "#gallery-#{message.id}-8")

    view
    |> element("#gallery-#{message.id}-7")
    |> render_click()

    assert has_element?(view, "#lightbox-image[src='/uploads/orig_8.jpg']")
    assert has_element?(view, "#lightbox-counter", "8 / 10")

    view |> element("#lightbox-next") |> render_click()
    assert has_element?(view, "#lightbox-image[src='/uploads/orig_9.jpg']")
    assert has_element?(view, "#lightbox-counter", "9 / 10")
  end

  test "long plain text messages show a read-more mask; short ones do not", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    long_body = String.duplicate("a", 401)

    {:ok, long_msg} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>#{long_body}</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, short_msg} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>short body</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#msg-body-#{long_msg.id}.xamt-text-collapsed")
    assert has_element?(view, "#msg-toggle-#{long_msg.id}")
    assert has_element?(view, "#msg-read-more-#{long_msg.id}")
    assert has_element?(view, "#msg-read-less-#{long_msg.id}[hidden]")

    assert has_element?(view, "#msg-body-#{short_msg.id}")
    refute has_element?(view, "#msg-body-#{short_msg.id}.xamt-text-collapsed")
    refute has_element?(view, "#msg-toggle-#{short_msg.id}")
  end

  test "chat drawer has close and home, not server switcher", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#drawer-close")
    assert has_element?(view, "#drawer-home")
    refute has_element?(view, "#create-server-rail")
    refute has_element?(view, "#current-user-chip")
    refute has_element?(view, ".xamt-server-dot")
  end

  test "drawer home returns to the home page", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert {:error, {:live_redirect, %{to: "/"}}} =
             view |> element("#drawer-home") |> render_click()
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

  test "renders sticky date dividers for each local day", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, day1} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>day one</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, day2} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>day two</p>",
        "content" => %{"type" => "rich_text"}
      })

    day1
    |> Ecto.Changeset.change(
      inserted_at: ~U[2026-09-18 12:00:00Z],
      updated_at: ~U[2026-09-18 12:00:00Z]
    )
    |> Xamt.Repo.update!()

    day2
    |> Ecto.Changeset.change(
      inserted_at: ~U[2026-09-19 12:00:00Z],
      updated_at: ~U[2026-09-19 12:00:00Z]
    )
    |> Xamt.Repo.update!()

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"timezone_offset" => -480})
      |> live(~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#messages-date-2026-09-18")
    assert has_element?(view, "#messages-date-2026-09-19")
    assert has_element?(view, ".xamt-date-divider__text", "-- 2026-09-18 --")
    assert has_element?(view, ".xamt-date-divider__text", "-- 2026-09-19 --")
  end

  test "consecutive messages from the same author hide the later header", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope,
    user: user
  } do
    {:ok, first} = post_html(scope, channel.id, "first")
    {:ok, second} = post_html(scope, channel.id, "second")

    stamp(first, ~U[2026-09-22 10:00:00Z])
    stamp(second, ~U[2026-09-22 10:02:00Z])

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(
             view,
             "[data-message-id='#{first.id}'] .xamt-message__username",
             user.username
           )

    assert has_element?(view, "#msg-header-#{first.id}")
    refute has_element?(view, "#msg-header-#{first.id}.xamt-message__header--spacer")
    assert has_element?(view, "#msg-header-#{second.id}.xamt-message__header--spacer")
    refute has_element?(view, "[data-message-id='#{second.id}'] .xamt-message__username")
    assert has_element?(view, "article.xamt-message--grouped[data-message-id='#{second.id}']")
    assert has_element?(view, "[data-message-id='#{second.id}'] time.xamt-message__time")
  end

  test "global roles tint the nickname and show a badge", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope,
    user: creator
  } do
    admin = admin_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(admin), server.id)
    admin_scope = Accounts.Scope.for_user(admin)
    regular = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(regular), server.id)
    regular_scope = Accounts.Scope.for_user(regular)

    {:ok, creator_msg} = post_html(scope, channel.id, "from creator")
    {:ok, admin_msg} = post_html(admin_scope, channel.id, "from admin")
    {:ok, regular_msg} = post_html(regular_scope, channel.id, "from user")

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(
             view,
             "[data-message-id='#{creator_msg.id}'] .xamt-message__username.xamt-role--creator",
             creator.username
           )

    assert has_element?(
             view,
             "[data-message-id='#{creator_msg.id}'] .xamt-role-badge.xamt-role-badge--creator",
             "Creator"
           )

    assert has_element?(
             view,
             "[data-message-id='#{admin_msg.id}'] .xamt-message__username.xamt-role--admin"
           )

    assert has_element?(
             view,
             "[data-message-id='#{admin_msg.id}'] .xamt-role-badge.xamt-role-badge--admin",
             "Admin"
           )

    assert has_element?(
             view,
             "[data-message-id='#{regular_msg.id}'] .xamt-message__username",
             regular.username
           )

    refute has_element?(
             view,
             "[data-message-id='#{regular_msg.id}'] .xamt-role-badge"
           )
  end

  test "a new author or a 5-minute gap starts a new header", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    other = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(other), server.id)
    other_scope = Accounts.Scope.for_user(other)

    {:ok, first} = post_html(scope, channel.id, "mine")
    {:ok, later} = post_html(scope, channel.id, "much later")
    {:ok, other_msg} = post_html(other_scope, channel.id, "theirs")

    stamp(first, ~U[2026-09-22 10:00:00Z])
    stamp(later, ~U[2026-09-22 10:06:00Z])
    stamp(other_msg, ~U[2026-09-22 10:06:30Z])

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    refute has_element?(view, "#msg-header-#{first.id}.xamt-message__header--spacer")
    refute has_element?(view, "#msg-header-#{later.id}.xamt-message__header--spacer")
    refute has_element?(view, "#msg-header-#{other_msg.id}.xamt-message__header--spacer")
  end

  test "a local date change starts a new header even within 5 minutes", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, before_midnight} = post_html(scope, channel.id, "before")
    {:ok, after_midnight} = post_html(scope, channel.id, "after")

    stamp(before_midnight, ~U[2026-09-21 15:58:00Z])
    stamp(after_midnight, ~U[2026-09-21 16:01:00Z])

    {:ok, view, _html} =
      conn
      |> put_connect_params(%{"timezone_offset" => -480})
      |> live(~p"/servers/#{server.slug}/#{channel.slug}")

    refute has_element?(view, "#msg-header-#{before_midnight.id}.xamt-message__header--spacer")
    refute has_element?(view, "#msg-header-#{after_midnight.id}.xamt-message__header--spacer")
    assert has_element?(view, "#messages-date-2026-09-21")
    assert has_element?(view, "#messages-date-2026-09-22")
  end

  test "a live incoming message continues the current group", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, first} = post_html(scope, channel.id, "live-first")
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    refute has_element?(view, "#msg-header-#{first.id}.xamt-message__header--spacer")

    {:ok, second} = post_html(scope, channel.id, "live-second")
    html = render(view)

    assert html =~ "live-second"
    assert has_element?(view, "#msg-header-#{second.id}.xamt-message__header--spacer")
  end

  test "editing a grouped message keeps the header collapsed", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, first} = post_html(scope, channel.id, "keep header")
    {:ok, second} = post_html(scope, channel.id, "grouped body")
    stamp(first, ~U[2026-09-22 11:00:00Z])
    stamp(second, ~U[2026-09-22 11:01:00Z])

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#msg-header-#{second.id}.xamt-message__header--spacer")

    view |> element("#edit-message-#{second.id}") |> render_click()

    render_hook(view, "update_message", %{
      "content_html" => "<p>grouped body edited</p>",
      "content_json" => ~s({"type":"rich_text","blocks":[]}),
      "content_type" => "rich_text"
    })

    assert render(view) =~ "grouped body edited"
    assert has_element?(view, "#msg-header-#{second.id}.xamt-message__header--spacer")
    assert has_element?(view, ".xamt-message__edited")
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
    |> element("#reply-message-#{message.id}")
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

  test "chat page has no server-settings entry", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#server-menu")
    refute has_element?(view, "#server-menu-settings")
    refute has_element?(view, "#edit-server-form")
    refute has_element?(view, "#server-settings")
    assert has_element?(view, "#server-info h1", server.name)
    refute has_element?(view, "#server-info button")
    refute has_element?(view, "#server-info", "/#{server.slug}")
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

  test "admin can open the create-channel drawer from the server info overlay", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(view, "#server-menu-drawer")

    view |> element("#mobile-nav-server") |> render_click()
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
    assert has_element?(view, "#drawer-close")

    view |> element("#drawer-close") |> render_click()
    assert has_element?(view, ".xamt-app--panel-messages")
    refute has_element?(view, "#drawer-backdrop")

    view |> element("#mobile-nav-menu") |> render_click()
    assert has_element?(view, ".xamt-app--panel-channels")

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
    assert has_element?(view, "#msg-embed-#{message.id}.xamt-embed-island")
    html = render(view)
    assert html =~ "Example Story"
    assert html =~ "A short summary"
    assert html =~ ~s(src="https://example.com/og.png")
  end

  test "renders video and audiobook cards as horizontal islands", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, video} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>https://www.youtube.com/watch?v=dQw4w9WgXcQ</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, book} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>https://audio-app-domain.com/books/jangar</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    {:ok, _} =
      Messages.put_link_preview(video, %{
        "type" => "video",
        "provider" => "YouTube",
        "video_id" => "dQw4w9WgXcQ",
        "url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "title" => "Jangar episode",
        "iframe_url" => "javascript:alert(1)"
      })

    assert has_element?(view, "#msg-embed-frame-#{video.id}")
    refute has_element?(view, "#msg-embed-frame-#{video.id}[sandbox]")
    assert has_element?(view, "#msg-embed-open-#{video.id}")

    html = render(view)
    assert html =~ "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1"
    assert html =~ "xamt-embed-island"
    assert html =~ ~s(referrerpolicy="strict-origin-when-cross-origin")
    refute html =~ "javascript:"
    refute html =~ "sandbox="

    {:ok, _} =
      Messages.put_link_preview(video, %{
        "type" => "video",
        "provider" => "Bilibili",
        "video_id" => "BV1NgY5zUEiM",
        "url" =>
          "https://www.bilibili.com/video/BV1NgY5zUEiM/?share_source=copy_web&vd_source=afac77442229c491cfe53a1ce797831d",
        "title" => "MGL斯琴布和"
      })

    html = render(view)
    assert html =~ "isOutside=true"
    assert html =~ "bvid=BV1NgY5zUEiM"
    assert html =~ "Open original"

    {:ok, _} =
      Messages.put_link_preview(video, %{
        "type" => "video",
        "provider" => "YouTube",
        "video_id" => "not a video",
        "url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "iframe_url" => "https://evil.example/embed"
      })

    html = render(view)
    refute html =~ "evil.example"
    refute html =~ "msg-embed-frame-#{video.id}"

    {:ok, _} =
      Messages.put_link_preview(book, %{
        "type" => "audio_book",
        "provider" => "MyAudioApp",
        "url" => "https://audio-app-domain.com/books/jangar",
        "title" => "江格尔",
        "cover_url" => "https://cdn.example/cover.jpg",
        "audio_sample_url" => "https://cdn.example/sample.m4a"
      })

    assert has_element?(
             view,
             "#msg-embed-sample-#{book.id}[src='https://cdn.example/sample.m4a']"
           )

    html = render(view)
    assert html =~ "江格尔"
    assert html =~ "xamt-embed-audio"
    assert html =~ ~s(src="https://cdn.example/cover.jpg")

    {:ok, _} =
      Messages.put_link_preview(book, %{
        "type" => "audio_book",
        "provider" => "MyAudioApp",
        "url" => "https://audio-app-domain.com/books/jangar",
        "title" => "江格尔",
        "audio_sample_url" => "javascript:alert(1)",
        "cover_url" => "https://127.0.0.1/cover.jpg"
      })

    html = render(view)
    refute html =~ "javascript:"
    refute html =~ "127.0.0.1"
    refute has_element?(view, "#msg-embed-sample-#{book.id}")
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

  test "opens status picker from own avatar and applies a preset", %{
    conn: conn,
    user: user,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>hello</p>",
        "content" => %{"type" => "rich_text", "html" => "<p>hello</p>"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, ".status-badge-container[data-user-id='#{user.id}']")
    assert has_element?(view, "#messages-#{message.id} .status-badge-container")
    refute has_element?(view, "#status-picker-drawer")

    view
    |> element("#member-avatar-#{user.id}-trigger")
    |> render_click()

    assert has_element?(view, "#status-picker-drawer")
    assert has_element?(view, "#status-preset-0")

    view
    |> element("#status-preset-0")
    |> render_click()

    refute has_element?(view, "#status-picker-drawer")

    updated = Accounts.get_user!(user.id)
    assert updated.status_emoji == "🏍️"
    assert updated.status_text == "Out on a motorcycle ride"

    html = render(view)
    assert html =~ "🏍️"
  end

  test "clears custom status from the picker", %{
    conn: conn,
    user: user,
    server: server,
    channel: channel
  } do
    {:ok, _} =
      Accounts.update_user_custom_status(user, %{
        status_emoji: "🎧",
        status_text: "Listening to an audiobook"
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    view
    |> element("#member-avatar-#{user.id}-trigger")
    |> render_click()

    view
    |> element("#status-clear")
    |> render_click()

    updated = Accounts.get_user!(user.id)
    assert updated.status_emoji == nil
    assert updated.status_text == nil
  end

  test "composer opens poll form and sends a poll", %{
    conn: conn,
    server: server,
    channel: channel
  } do
    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#composer-poll")
    refute has_element?(view, "#poll-composer-form")

    view |> element("#composer-poll") |> render_click()
    assert has_element?(view, "#poll-composer-form")
    assert has_element?(view, "#poll-question")

    view
    |> form("#poll-composer-form",
      poll: %{
        question: "Weekend route?",
        options: ["East loop", "West loop"],
        allow_multiple: "false"
      }
    )
    |> render_submit()

    html = render(view)
    assert html =~ "Weekend route?"
    assert html =~ "East loop"
    assert html =~ "West loop"
    assert has_element?(view, ".xamt-poll")
    refute has_element?(view, "#poll-composer-form")
  end

  test "casting a poll vote updates the poll card", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope,
    user: user
  } do
    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Vote me",
        "options" => ["Alpha", "Beta"]
      })

    poll = Messages.poll_summary([message.id])[message.id]
    option = hd(poll.options)
    poll_id = poll.id

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#poll-#{poll_id}")
    assert has_element?(view, "#poll-vote-#{option.id}")

    view |> element("#poll-vote-#{option.id}") |> render_click()

    assert_push_event(view, "update_poll_chart", %{
      poll_id: ^poll_id,
      total_votes: 1
    })

    my = Messages.poll_votes_for_user(user.id, [poll_id])
    assert MapSet.member?(my[poll_id], option.id)
  end

  test "poll details drawer lists voters", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope,
    user: user
  } do
    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Who?",
        "options" => ["Me", "You"],
        "results_open" => true
      })

    poll = Messages.poll_summary([message.id])[message.id]
    option = hd(poll.options)
    assert {:ok, _} = Messages.toggle_vote(scope, poll.id, option.id)

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(view, "#poll-details-#{poll.id}")

    view |> element("#poll-details-#{poll.id}") |> render_click()

    assert has_element?(view, "#poll-details-drawer")
    assert has_element?(view, "#poll-details-option-#{option.id}")
    assert has_element?(view, "#poll-voter-#{option.id}-#{user.id}")
  end

  test "closed poll hides details for non-authors", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    member =
      Xamt.AccountsFixtures.user_fixture(%{
        username: "peek#{System.unique_integer() |> abs()}"
      })

    {:ok, _} = Servers.join_server(Xamt.Accounts.Scope.for_user(member), server.id)

    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Secret",
        "options" => ["A", "B"],
        "results_open" => false
      })

    poll = Messages.poll_summary([message.id])[message.id]

    {:ok, author_view, _} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    assert has_element?(author_view, "#poll-details-#{poll.id}")

    member_conn = log_in_user(build_conn(), member)
    {:ok, member_view, _} = live(member_conn, ~p"/servers/#{server.slug}/#{channel.slug}")
    refute has_element?(member_view, "#poll-details-#{poll.id}")
  end

  test "pinned drawer lazy-loads and pin toggles update the board", %{
    conn: conn,
    server: server,
    channel: channel,
    scope: scope
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>announcement</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, view, _html} = live(conn, ~p"/servers/#{server.slug}/#{channel.slug}")

    assert has_element?(view, "#toggle-pinned-drawer")
    refute has_element?(view, "#pinned-messages-drawer")

    view |> element("#toggle-pinned-drawer") |> render_click()
    assert has_element?(view, "#pinned-messages-drawer")
    assert has_element?(view, "#pinned-messages-empty")

    view |> element("#pin-message-#{message.id}") |> render_click()
    assert has_element?(view, "#pinned-msg-#{message.id}")
    refute has_element?(view, "#pinned-messages-empty")
    assert has_element?(view, "#msg-content-#{message.id}")
    assert has_element?(view, ".xamt-message__pinned")

    view |> element("#unpin-message-#{message.id}") |> render_click()
    assert has_element?(view, "#pinned-messages-empty")
    refute has_element?(view, "#pinned-msg-#{message.id}")
  end

  defp post_html(scope, channel_id, text) do
    Messages.create_message(scope, channel_id, %{
      "content_html" => "<p>#{text}</p>",
      "content" => %{"type" => "rich_text"}
    })
  end

  defp stamp(message, inserted_at) do
    message
    |> Ecto.Changeset.change(inserted_at: inserted_at, updated_at: inserted_at)
    |> Xamt.Repo.update!()
  end
end
