defmodule XamtWeb.UserRegistrationControllerTest do
  use XamtWeb.ConnCase, async: true

  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.SiteSettings

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ ~p"/login"
      assert response =~ ~p"/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login when registration is closed", %{conn: conn} do
      SiteSettings.put_registration_enabled!(false)

      conn = get(conn, ~p"/users/register")
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "closed"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end

    test "rejects new accounts when registration is closed", %{conn: conn} do
      SiteSettings.put_registration_enabled!(false)
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)
      refute Accounts.get_user_by_email(email)
    end
  end
end
