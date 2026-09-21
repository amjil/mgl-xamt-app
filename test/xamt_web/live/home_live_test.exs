defmodule XamtWeb.HomeLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Repo
  alias Xamt.Servers.Server

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
end
