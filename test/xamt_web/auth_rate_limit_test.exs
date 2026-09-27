defmodule XamtWeb.AuthRateLimitTest do
  use XamtWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.AuthRateLimit
  alias Xamt.Messages.RateLimiter
  alias Xamt.Servers

  setup do
    previous = Application.get_env(:xamt, AuthRateLimit)

    on_exit(fn ->
      Application.put_env(:xamt, AuthRateLimit, previous)
      RateLimiter.reset()
    end)

    RateLimiter.reset()
    :ok
  end

  test "password login is rate limited", %{conn: conn} do
    user = set_password(user_fixture())

    Application.put_env(:xamt, AuthRateLimit,
      login: [limit: 2, window_seconds: 60],
      magic_link: [limit: :infinity, window_seconds: 60],
      register: [limit: :infinity, window_seconds: 60],
      invite: [limit: :infinity, window_seconds: 60]
    )

    params = %{"user" => %{"email" => user.email, "password" => "wrong-password"}}

    conn = post(conn, ~p"/users/log-in?mode=password", params)
    assert html_response(conn, 200) =~ "Invalid email or password"

    conn = post(recycle(conn), ~p"/users/log-in?mode=password", params)
    assert html_response(conn, 200) =~ "Invalid email or password"

    conn = post(recycle(conn), ~p"/users/log-in?mode=password", params)
    assert html_response(conn, 200) =~ "Too many attempts"
  end

  test "registration is rate limited", %{conn: conn} do
    Application.put_env(:xamt, AuthRateLimit,
      login: [limit: :infinity, window_seconds: 60],
      magic_link: [limit: :infinity, window_seconds: 60],
      register: [limit: 1, window_seconds: 60],
      invite: [limit: :infinity, window_seconds: 60]
    )

    conn = post(conn, ~p"/users/register", %{"user" => valid_user_attributes()})
    assert redirected_to(conn) == ~p"/login"

    conn = post(recycle(conn), ~p"/users/register", %{"user" => valid_user_attributes()})
    assert html_response(conn, 200) =~ "Too many attempts"
  end

  test "invite redeem is rate limited" do
    owner = creator_fixture()
    scope = Accounts.Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Rate Hall"})
    {:ok, invite} = Servers.create_invite(scope, server.id)

    Application.put_env(:xamt, AuthRateLimit,
      login: [limit: :infinity, window_seconds: 60],
      magic_link: [limit: :infinity, window_seconds: 60],
      register: [limit: :infinity, window_seconds: 60],
      invite: [limit: 1, window_seconds: 60]
    )

    stranger = user_fixture()
    conn = log_in_user(build_conn(), stranger)
    {:ok, view, _html} = live(conn, ~p"/invite/#{invite.code}")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#accept-invite") |> render_click()

    assert to =~ "/servers/#{server.slug}"

    {:ok, view, _html} = live(conn, ~p"/invite/#{invite.code}")
    html = view |> element("#accept-invite") |> render_click()
    assert html =~ "Too many attempts"
  end
end
