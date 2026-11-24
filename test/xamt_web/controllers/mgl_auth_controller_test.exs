defmodule XamtWeb.MglAuthControllerTest do
  use XamtWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Xamt.AccountsFixtures

  alias Xamt.Accounts
  alias Xamt.MglId
  alias Xamt.MglId.Transactions
  alias Xamt.MglIdHelpers
  alias Xamt.SiteSettings

  setup do
    MglIdHelpers.clear_cache!()
    MglIdHelpers.put_discovery!()
    jwk = MglIdHelpers.rsa_keypair!()
    MglIdHelpers.put_jwks!(MglIdHelpers.jwks_for(jwk))
    SiteSettings.put_registration_enabled!(true)
    {:ok, jwk: jwk}
  end

  test "start redirects to Mgl authorize URL", %{conn: conn} do
    conn = get(conn, ~p"/auth/mgl")

    assert redirected_to(conn, 302) =~ "/oauth/authorize?"
    assert redirected_to(conn) =~ "client_id=#{MglId.client_id()}"
    assert redirected_to(conn) =~ "code_challenge_method=S256"

    txns = get_session(conn, Transactions.session_key())
    assert length(txns) == 1
    assert hd(txns)["purpose"] == "login"
  end

  test "callback with bad state is rejected", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> get(~p"/auth/mgl/callback", %{"code" => "x", "state" => "nope"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "state"
  end

  test "callback logs in an already-linked user", %{conn: conn, jwk: jwk} do
    claims = MglIdHelpers.default_claims(%{"nonce" => "n1"})
    {:ok, user} = Accounts.provision_user_from_mgl(claims)
    id_token = MglIdHelpers.sign_id_token(jwk, claims)
    stub_token_endpoint(id_token)

    conn =
      conn
      |> put_login_txn("s1", "n1")
      |> get(~p"/auth/mgl/callback", %{"code" => "auth-code", "state" => "s1"})

    assert redirected_to(conn) == ~p"/"
    token = get_session(conn, :user_token)
    assert token
    {logged_in, _} = Accounts.get_user_by_session_token(token)
    assert logged_in.id == user.id
  end

  test "callback provisions a new user on first login", %{conn: conn, jwk: jwk} do
    claims = MglIdHelpers.default_claims(%{"nonce" => "n2"})
    id_token = MglIdHelpers.sign_id_token(jwk, claims)
    stub_token_endpoint(id_token)

    conn =
      conn
      |> put_login_txn("s2", "n2")
      |> get(~p"/auth/mgl/callback", %{"code" => "auth-code", "state" => "s2"})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)

    identity = Accounts.get_user_by_mgl_identity(MglId.issuer(), claims["sub"])
    assert identity
    assert identity.user.email == claims["email"]
  end

  test "callback rejects first login when registration is closed", %{conn: conn, jwk: jwk} do
    SiteSettings.put_registration_enabled!(false)
    claims = MglIdHelpers.default_claims(%{"nonce" => "n3"})
    id_token = MglIdHelpers.sign_id_token(jwk, claims)
    stub_token_endpoint(id_token)

    conn =
      conn
      |> put_login_txn("s3", "n3")
      |> get(~p"/auth/mgl/callback", %{"code" => "auth-code", "state" => "s3"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Registration"
    refute get_session(conn, :user_token)
  end

  test "login page shows Mgl ID button when enabled", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ ~s(id="mgl-id-login")
    assert html_response(conn, 200) =~ "Continue with Mgl ID"
  end

  test "link_start requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/settings/account/identities/mgl/connect")
    assert redirected_to(conn) in [~p"/users/log-in", ~p"/login"]
  end

  test "link_callback connects Mgl ID to current user", %{conn: conn, jwk: jwk} do
    user = user_fixture()
    claims = MglIdHelpers.default_claims(%{"nonce" => "link-n"})
    id_token = MglIdHelpers.sign_id_token(jwk, claims)
    stub_token_endpoint(id_token)

    txn = %{
      "state" => "link-s",
      "nonce" => "link-n",
      "code_verifier" => "verifier",
      "redirect_uri" => MglId.link_redirect_uri(),
      "purpose" => "link",
      "user_id" => to_string(user.id),
      "expires_at" => DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.to_iso8601()
    }

    token = Accounts.generate_user_session_token(user)

    conn =
      conn
      |> init_test_session(%{
        :user_token => token,
        Transactions.session_key() => [txn]
      })
      |> get(~p"/settings/account/identities/mgl/callback", %{
        "code" => "auth-code",
        "state" => "link-s"
      })

    assert redirected_to(conn) == ~p"/settings"
    assert Accounts.get_mgl_identity(user)
  end

  test "settings shows connect button when not linked", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/settings")
    assert has_element?(view, "#mgl-id-connect")
  end

  test "account_link requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/account/link", %{"token" => "t", "provider" => "xamt"})
    assert redirected_to(conn) in [~p"/users/log-in", ~p"/login"]
  end

  test "account_link confirms with mgl-id and stores local identity", %{conn: conn} do
    user = user_fixture()
    amjil_user_id = Ecto.UUID.generate()
    stub_account_link_confirm(amjil_user_id)

    token = Accounts.generate_user_session_token(user)

    conn =
      conn
      |> init_test_session(%{:user_token => token})
      |> get(~p"/account/link", %{"token" => "init-token", "provider" => "xamt"})

    assert redirected_to(conn) == ~p"/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "connected"

    identity = Accounts.get_mgl_identity(user)
    assert identity
    assert identity.subject == amjil_user_id
    assert identity.issuer == String.trim_trailing(MglId.issuer(), "/")
  end

  test "account_link rejects when user already linked", %{conn: conn} do
    user = user_fixture()
    claims = MglIdHelpers.default_claims()
    assert {:ok, _} = Accounts.link_mgl_identity(user, claims)

    token = Accounts.generate_user_session_token(user)

    conn =
      conn
      |> init_test_session(%{:user_token => token})
      |> get(~p"/account/link", %{"token" => "init-token", "provider" => "xamt"})

    assert redirected_to(conn) == ~p"/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already connected"
  end

  test "account_link rejects missing token", %{conn: conn} do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    conn =
      conn
      |> init_test_session(%{:user_token => token})
      |> get(~p"/account/link", %{"provider" => "xamt"})

    assert redirected_to(conn) == ~p"/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
  end

  defp put_login_txn(conn, state, nonce) do
    txn = %{
      "state" => state,
      "nonce" => nonce,
      "code_verifier" => "verifier",
      "redirect_uri" => MglId.redirect_uri(),
      "purpose" => "login",
      "expires_at" => DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.to_iso8601()
    }

    init_test_session(conn, %{Transactions.session_key() => [txn]})
  end

  defp stub_token_endpoint(id_token) do
    Req.Test.stub(Xamt.MglId, fn conn ->
      case conn.method do
        "POST" ->
          Req.Test.json(conn, %{
            "access_token" => "access",
            "id_token" => id_token,
            "token_type" => "Bearer",
            "expires_in" => 600
          })

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)
  end

  defp stub_account_link_confirm(amjil_user_id) do
    Req.Test.stub(Xamt.MglId, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/v1/account-links/confirm"} ->
          Req.Test.json(conn, %{
            "data" => %{
              "user_id" => amjil_user_id,
              "amjil_user_id" => amjil_user_id,
              "link" => %{
                "id" => Ecto.UUID.generate(),
                "provider" => "xamt",
                "external_user_id" => "ignored"
              }
            },
            "meta" => %{}
          })

        _ ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end
    end)
  end
end
