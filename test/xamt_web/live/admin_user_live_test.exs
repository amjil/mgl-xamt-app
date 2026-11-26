defmodule XamtWeb.AdminUserLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts

  test "the create-user route no longer exists; accounts come from Mgl ID", %{conn: conn} do
    # Admin-created accounts had no Mgl ID identity and could never sign in.
    assert get(conn, "/admin/users/new").status == 404
  end

  test "unauthenticated visitors cannot edit a user", %{conn: conn} do
    user = user_fixture()
    conn = get(conn, ~p"/admin/users/#{user.id}/edit")
    assert redirected_to(conn) == ~p"/login"
  end

  test "non-admins cannot edit a user", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/settings"}}} =
             live(conn, ~p"/admin/users/#{user.id}/edit")
  end

  test "admins can update a user's profile and role", %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture(%{display_name: "Old Name"})
    email = unique_user_email()
    username = unique_user_username()

    conn = log_in_user(conn, admin)
    {:ok, view, html} = live(conn, ~p"/admin/users/#{user.id}/edit")

    assert html =~ "Edit user"
    assert has_element?(view, "#admin-edit-user-form")
    assert has_element?(view, "#admin-edit-profile-form")
    assert has_element?(view, "#edit-user-submit")
    assert has_element?(view, "#admin-user-detail-canvas")

    view
    |> form("#admin-edit-profile-form",
      user: %{
        display_name: "Updated Neighbor",
        bio: "Lives nearby."
      }
    )
    |> render_submit()

    view
    |> element("#admin-detail-role-form")
    |> render_change(%{role: "creator"})

    {:ok, _list_view, redirected} =
      view
      |> form("#admin-edit-user-form",
        user: %{
          username: username,
          email: email
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/users")

    assert redirected =~ "Updated @#{username}"

    updated = Accounts.get_user!(user.id)
    assert updated.display_name == "Updated Neighbor"
    assert updated.username == username
    assert updated.email == email
    assert updated.bio == "Lives nearby."
    assert updated.global_role == "creator"
  end

  test "shows validation errors on edit", %{conn: conn} do
    user = user_fixture()

    {:ok, view, _html} =
      live(log_in_user(conn, admin_fixture()), ~p"/admin/users/#{user.id}/edit")

    html =
      view
      |> form("#admin-edit-user-form", user: %{email: "not valid", username: "ab"})
      |> render_submit()

    assert html =~ "must have the @ sign and no spaces"
    assert html =~ "should be at least 3 character"
  end
end
