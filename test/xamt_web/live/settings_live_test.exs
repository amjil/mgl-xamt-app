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

    view
    |> element("#settings-status-preset-2")
    |> render_click()

    updated = Accounts.get_user!(user.id)
    assert updated.status_emoji == "🎧"
    assert updated.status_text == "Listening to an audiobook"
    assert render(view) =~ "🎧"
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
