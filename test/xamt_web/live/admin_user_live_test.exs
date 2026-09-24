defmodule XamtWeb.AdminUserLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.SiteSettings

  test "unauthenticated visitors are sent to login", %{conn: conn} do
    conn = get(conn, ~p"/admin/users/new")
    assert redirected_to(conn) == ~p"/login"
  end

  test "non-admins are redirected away", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/settings"}}} = live(conn, ~p"/admin/users/new")
  end

  test "creators are redirected away", %{conn: conn} do
    conn = log_in_user(conn, creator_fixture())

    assert {:error, {:redirect, %{to: "/settings"}}} = live(conn, ~p"/admin/users/new")
  end

  test "admins can create a user with a role", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, html} = live(log_in_user(conn, admin), ~p"/admin/users/new")

    assert html =~ "Create user"
    assert has_element?(view, "#admin-create-user-form")
    assert has_element?(view, "#create-user-submit")

    email = unique_user_email()
    username = unique_user_username()

    html =
      view
      |> form("#admin-create-user-form",
        user: %{
          display_name: "New Neighbor",
          username: username,
          email: email,
          password: valid_user_password(),
          password_confirmation: valid_user_password(),
          global_role: "creator"
        }
      )
      |> render_submit()

    assert html =~ "Created @#{username}"
    assert has_element?(view, "#admin-create-user-form")

    created = Accounts.get_user_by_email(email)
    assert created.username == username
    assert created.display_name == "New Neighbor"
    assert created.global_role == "creator"
    assert created.confirmed_at
  end

  test "admins can create users when registration is closed", %{conn: conn} do
    SiteSettings.put_registration_enabled!(false)
    admin = admin_fixture()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin/users/new")

    email = unique_user_email()

    view
    |> form("#admin-create-user-form",
      user: valid_user_attributes(email: email, global_role: "user")
    )
    |> render_submit()

    assert Accounts.get_user_by_email(email)
  end

  test "shows validation errors", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/users/new")

    html =
      view
      |> form("#admin-create-user-form", user: %{email: "not valid", username: "ab"})
      |> render_submit()

    assert html =~ "must have the @ sign and no spaces"
    assert html =~ "should be at least 3 character"
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
    assert has_element?(view, "#edit-user-submit")

    {:ok, _list_view, redirected} =
      view
      |> form("#admin-edit-user-form",
        user: %{
          display_name: "Updated Neighbor",
          username: username,
          email: email,
          bio: "Lives nearby.",
          global_role: "creator"
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
