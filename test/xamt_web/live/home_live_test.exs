defmodule XamtWeb.HomeLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.Repo
  alias Xamt.Servers
  alias Xamt.Servers.Server
  alias Xamt.SiteSettings

  test "regular users do not see the create server control", %{conn: conn} do
    {:ok, view, html} = live(log_in_user(conn, user_fixture()), ~p"/")

    refute has_element?(view, "#toggle-create-server")
    refute has_element?(view, "#create-server-form")
    assert html =~ "Join a public server or wait for an invite"
  end

  test "creators can open the form and create a server", %{conn: conn} do
    conn = log_in_user(conn, creator_fixture())
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#toggle-create-server")
    refute has_element?(view, "#create-server-form")

    view |> element("#toggle-create-server") |> render_click()
    assert has_element?(view, "#create-server-form")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#create-server-form", server: %{name: "New Hall"})
             |> render_submit()

    assert to == "/servers/new-hall"
    assert Repo.get_by(Server, slug: "new-hall")
  end

  test "admins can open the create form from the query param", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, admin_fixture()), ~p"/?create=1")
    assert has_element?(view, "#create-server-form")
  end

  test "regular users cannot create a server by sending the event", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/")

    html =
      render_click(view, "create_server", %{"server" => %{"name" => "Hacked Hall"}})

    assert html =~ "permission to create a server"
    refute Repo.get_by(Server, name: "Hacked Hall")
  end

  test "create query param does not open the form for regular users", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/?create=1")
    refute has_element?(view, "#create-server-form")
  end

  test "owners can edit a server from the home card", %{conn: conn} do
    user = creator_fixture()
    scope = Accounts.Scope.for_user(user)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Old Hall", "description" => "old"})

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/")
    assert has_element?(view, "#edit-server-#{server.id}")
    assert has_element?(view, ".xamt-server-card__desc", "old")
    refute has_element?(view, "#edit-server-drawer")

    view |> element("#edit-server-#{server.id}") |> render_click()
    assert has_element?(view, "#edit-server-drawer")
    assert has_element?(view, "#edit-server-form")

    view
    |> form("#edit-server-form", %{
      server: %{name: "Renamed Hall", description: "updated hall"}
    })
    |> render_submit()

    refute has_element?(view, "#edit-server-drawer")
    assert has_element?(view, ".xamt-server-card__name", "Renamed Hall")
    assert has_element?(view, ".xamt-server-card__desc", "updated hall")
    assert Repo.get!(Server, server.id).description == "updated hall"
  end

  test "server settings expose a copyable invite URL", %{conn: conn} do
    user = creator_fixture()
    scope = Accounts.Scope.for_user(user)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Invite Hall"})
    {:ok, invite} = Servers.create_invite(scope, server.id)

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/")
    view |> element("#edit-server-#{server.id}") |> render_click()

    assert has_element?(view, "#copy-invite-#{invite.id}")
    html = render(view)
    assert html =~ "/invite/#{invite.code}"
    assert html =~ ~s(data-copy=")
  end

  test "regular members do not see the server settings control", %{conn: conn} do
    owner = creator_fixture()
    scope = Accounts.Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Closed Hall"})

    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)

    {:ok, view, _html} = live(log_in_user(conn, member), ~p"/")
    refute has_element?(view, "#edit-server-#{server.id}")
    refute has_element?(view, "#edit-server-form")
  end

  test "regular members cannot open settings by sending the event", %{conn: conn} do
    owner = creator_fixture()
    scope = Accounts.Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Guarded Hall"})

    member = user_fixture()
    {:ok, _} = Servers.join_server(Accounts.Scope.for_user(member), server.id)

    {:ok, view, _html} = live(log_in_user(conn, member), ~p"/")
    html = render_click(view, "edit_server_request", %{"id" => server.id})

    refute has_element?(view, "#edit-server-form")
    assert html =~ "Unauthorized"
  end

  test "guests see a register link while registration is open", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ ~p"/register"
    assert has_element?(view, "a[href='/register']", "Register")
  end

  test "guests do not see a register link when registration is closed", %{conn: conn} do
    SiteSettings.put_registration_enabled!(false)

    {:ok, view, html} = live(conn, ~p"/")

    refute html =~ ~p"/register"
    refute has_element?(view, "a[href='/register']")
  end
end
