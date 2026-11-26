defmodule XamtWeb.UserSessionControllerTest do
  use XamtWeb.ConnCase, async: true

  import Xamt.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log-in" do
    test "renders the Mgl ID login page without other sign-in forms", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      response = html_response(conn, 200)

      assert response =~ "Log in"
      assert response =~ "Sign in with your Mgl ID account."
      refute response =~ ~s(id="login_form_password")
      refute response =~ ~s(id="login_form_magic")
      refute response =~ ~s(type="password")
      refute response =~ "/register"
    end

    test "shows the reauthentication message for a logged-in user", %{conn: conn, user: user} do
      html =
        conn
        |> log_in_user(user)
        |> get(~p"/users/log-in")
        |> html_response(200)

      assert html =~ "You need to reauthenticate"
    end
  end

  describe "removed auth routes" do
    test "public registration is no longer served", %{conn: conn} do
      assert get(conn, "/register").status == 404
      assert get(recycle(conn), "/users/register").status == 404
    end

    test "magic link confirmation is no longer served", %{conn: conn} do
      assert get(conn, "/users/log-in/some-token").status == 404
    end

    test "password and magic link POSTs are no longer served", %{conn: conn, user: user} do
      params = %{"user" => %{"username" => user.username, "password" => "x"}}

      assert post(conn, "/users/log-in", params).status == 404
      assert post(recycle(conn), "/login", params).status == 404
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
