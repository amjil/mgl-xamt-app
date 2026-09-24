defmodule XamtWeb.ProfileLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  test "admin profile highlights with role accent and badge", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/profile/#{admin.username}")

    assert has_element?(view, "#profile-panel .xamt-profile.xamt-profile--role-admin")
    assert has_element?(view, "#profile-role-badge.xamt-role-badge--admin", "Admin")
    assert has_element?(view, ".xamt-profile__display-name.xamt-role--admin")
  end

  test "ordinary users have no role badge", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/profile/#{user.username}")

    refute has_element?(view, "#profile-role-badge")
    refute has_element?(view, ".xamt-profile--role-admin")
    refute has_element?(view, ".xamt-profile--role-creator")
    assert has_element?(view, ".xamt-profile__names .xamt-profile__display-name")
    assert has_element?(view, ".xamt-profile__names .xamt-profile__username")
    refute has_element?(view, ".xamt-profile__username.xamt-upright")
    assert has_element?(view, "#profile-edit")
    assert has_element?(view, "#profile-back")
  end
end
