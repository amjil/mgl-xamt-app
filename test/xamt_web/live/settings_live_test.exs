defmodule XamtWeb.SettingsLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "renders five-zone settings canvas", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")

    assert html =~ "Account"
    assert has_element?(view, "#settings-canvas")
    assert has_element?(view, "#avatar-form")
    assert has_element?(view, "#profile-form")
    assert has_element?(view, "#email_form")
    refute has_element?(view, "#password_form")
    assert has_element?(view, "#web-push-settings")
    assert has_element?(view, "#settings-status-emoji[phx-hook='StatusEmoji']")
  end

  test "saves profile info and custom status", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#profile-form", %{
      user: %{display_name: "Сайн", bio: "hello bio"},
      status_emoji: "😀",
      status_text: "hello"
    })
    |> render_submit()

    updated = Accounts.get_user!(user.id)
    assert updated.display_name == "Сайн"
    assert updated.bio == "hello bio"
    assert updated.status_emoji == "😀"
    assert updated.status_text == "hello"
  end

  test "regular users do not see the site admin section", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    refute has_element?(view, "#site-settings")
    refute has_element?(view, "#manage-users-link")
  end

  test "admins see the users link and no sign-up or magic link switches", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/settings")

    assert has_element?(view, "#site-settings")
    assert has_element?(view, "#manage-users-link")
    refute has_element?(view, "#registration-toggle")
    refute has_element?(view, "#magic-link-toggle")
  end

  test "revokes all sessions and redirects to log in", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    {:ok, conn} =
      view
      |> element("button[phx-click='revoke_all_sessions']")
      |> render_click()
      |> follow_redirect(conn, ~p"/users/log-in")

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "logged out"
    assert Accounts.get_user_by_session_token(get_session(conn, :user_token)) == nil
    # user still exists; only sessions were revoked
    assert Accounts.get_user!(user.id)
  end
end
