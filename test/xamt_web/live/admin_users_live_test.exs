defmodule XamtWeb.AdminUsersLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  test "unauthenticated visitors are sent to login", %{conn: conn} do
    conn = get(conn, ~p"/admin/users")
    assert redirected_to(conn) == ~p"/login"
  end

  test "non-admins are redirected away", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/settings"}}} = live(conn, ~p"/admin/users")
  end

  test "creators are redirected away", %{conn: conn} do
    conn = log_in_user(conn, creator_fixture())

    assert {:error, {:redirect, %{to: "/settings"}}} = live(conn, ~p"/admin/users")
  end

  test "admins can search the user list", %{conn: conn} do
    admin = admin_fixture()
    suffix = System.unique_integer([:positive])

    alice =
      user_fixture(%{
        username: "alice#{suffix}",
        display_name: "Alice Neighbor",
        email: "alice#{suffix}@example.com"
      })

    bob =
      user_fixture(%{
        username: "bob#{suffix}",
        display_name: "Bob Guest",
        email: "bob#{suffix}@example.com"
      })

    {:ok, view, html} = live(log_in_user(conn, admin), ~p"/admin/users")

    assert html =~ "Users"
    assert has_element?(view, "#admin-users-search")
    assert has_element?(view, "#admin-users-q")
    assert has_element?(view, "#admin-users-create")
    assert has_element?(view, "#users-#{alice.id}")
    assert has_element?(view, "#users-#{bob.id}")
    assert has_element?(view, "#admin-user-edit-#{alice.id}")
    assert has_element?(view, "#users-#{alice.id} .xamt-admin-user__username")
    assert has_element?(view, "#users-#{alice.id} .xamt-admin-user__email")
    refute has_element?(view, "#users-#{alice.id} .xamt-upright")
    refute has_element?(view, "#users-#{alice.id} .xamt-latin")

    view
    |> form("#admin-users-search", %{q: "Alice Neighbor"})
    |> render_change()

    assert has_element?(view, "#users-#{alice.id}")
    refute has_element?(view, "#users-#{bob.id}")

    view
    |> form("#admin-users-search", %{q: "bob#{suffix}"})
    |> render_change()

    refute has_element?(view, "#users-#{alice.id}")
    assert has_element?(view, "#users-#{bob.id}")
  end

  test "admins can open the edit page from the list", %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture()
    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/users")

    {:ok, edit_view, html} =
      view
      |> element("#admin-user-edit-#{user.id}")
      |> render_click()
      |> follow_redirect(conn, ~p"/admin/users/#{user.id}/edit")

    assert html =~ "Edit user"
    assert has_element?(edit_view, "#admin-edit-user-form")
  end
end
