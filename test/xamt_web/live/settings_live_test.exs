defmodule XamtWeb.SettingsLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "renders custom status section and applies a preset", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/settings")

    assert html =~ "Settings"
    assert has_element?(view, "#settings-status")
    assert has_element?(view, "#settings-status-preset-0")
    assert has_element?(view, "#settings-status-emoji[phx-hook='StatusEmoji']")

    view
    |> element("#settings-status-preset-2")
    |> render_click()

    updated = Accounts.get_user!(user.id)
    assert updated.status_emoji == "🏖️"
    assert updated.status_text == "On vacation"
    assert render(view) =~ "🏖️"
  end

  test "saves a custom status from the form", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> form("#settings-status-form", %{emoji: "😀", text: "hello"})
    |> render_submit()

    updated = Accounts.get_user!(user.id)
    assert updated.status_emoji == "😀"
    assert updated.status_text == "hello"
  end

  test "regular users do not see the site registration toggle", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    refute has_element?(view, "#site-settings")
    refute has_element?(view, "#registration-toggle")
    refute has_element?(view, "#create-user-link")
  end

  test "admins can close and reopen registration", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/settings")

    assert has_element?(view, "#site-settings")
    assert has_element?(view, "#create-user-link")
    assert has_element?(view, "#registration-toggle[aria-checked='true']")

    view |> element("#registration-toggle") |> render_click()

    refute Xamt.SiteSettings.registration_enabled?()
    assert has_element?(view, "#registration-toggle[aria-checked='false']")

    view |> element("#registration-toggle") |> render_click()

    assert Xamt.SiteSettings.registration_enabled?()
    assert has_element?(view, "#registration-toggle[aria-checked='true']")
  end

  test "non-admins cannot toggle registration by sending the event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html = render_click(view, "toggle_registration", %{})
    assert html =~ "permission to change this"
    assert Xamt.SiteSettings.registration_enabled?()
  end

  test "clears custom status", %{conn: conn, user: user} do
    {:ok, _} =
      Accounts.update_user_custom_status(user, %{
        status_emoji: "🚗",
        status_text: "On a road trip"
      })

    {:ok, view, _html} = live(conn, ~p"/settings")

    view
    |> element("#settings-status-clear")
    |> render_click()

    updated = Accounts.get_user!(user.id)
    assert updated.status_emoji == nil
    assert updated.status_text == nil
  end
end
