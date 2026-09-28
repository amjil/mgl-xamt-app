defmodule XamtWeb.SavedLiveTest do
  use XamtWeb.ConnCase

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.{Accounts, Channels, Messages, Servers}

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/saved")
  end

  test "lists and removes bookmarked messages", %{conn: conn} do
    user = creator_fixture()
    scope = Accounts.Scope.for_user(user)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Keepers"})
    channel = hd(Channels.list_channels(server.id))

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>saved-needle</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:ok, _} = Messages.toggle_bookmark(scope, message.id)

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/saved")
    assert has_element?(view, "#saved-page")
    assert has_element?(view, "#saved-msg-#{message.id}")
    assert has_element?(view, "#saved-open-search")

    view |> element("#unsave-message-#{message.id}") |> render_click()
    refute has_element?(view, "#saved-msg-#{message.id}")
    assert has_element?(view, "#saved-empty")
  end
end
