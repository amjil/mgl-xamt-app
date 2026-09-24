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
end
