defmodule XamtWeb.MglAuthController do
  use XamtWeb, :controller

  alias Xamt.Accounts
  alias Xamt.MglId
  alias Xamt.MglId.{Auth, Client, Transactions}
  alias XamtWeb.UserAuth

  def start(conn, _params) do
    if MglId.enabled?() do
      case Client.authorize_url(purpose: "login", redirect_uri: MglId.redirect_uri()) do
        {:ok, url, txn} ->
          :telemetry.execute([:xamt, :mgl_id, :auth], %{count: 1}, %{
            event: "auth.mgl.login.started"
          })

          conn
          |> Transactions.put(txn)
          |> redirect(external: url)

        {:error, _reason} ->
          conn
          |> put_flash(:error, gettext("Mgl ID is temporarily unavailable. Try again later."))
          |> redirect(to: ~p"/login")
      end
    else
      conn
      |> put_flash(:error, gettext("Mgl ID login is disabled."))
      |> redirect(to: ~p"/login")
    end
  end

  def callback(conn, params) do
    cond do
      not MglId.enabled?() ->
        conn
        |> put_flash(:error, gettext("Mgl ID login is disabled."))
        |> redirect(to: ~p"/login")

      error = params["error"] ->
        conn
        |> put_flash(:error, oauth_error_message(error, params["error_description"]))
        |> redirect(to: ~p"/login")

      is_binary(params["code"]) and is_binary(params["state"]) ->
        finish_login(conn, params["code"], params["state"])

      true ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID login response."))
        |> redirect(to: ~p"/login")
    end
  end

  def link_start(conn, _params) do
    user = current_user(conn)

    cond do
      not MglId.enabled?() ->
        conn
        |> put_flash(:error, gettext("Mgl ID login is disabled."))
        |> redirect(to: ~p"/settings")

      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("You must log in before connecting Mgl ID."))
        |> redirect(to: ~p"/login")

      true ->
        case Client.authorize_url(
               purpose: "link",
               redirect_uri: MglId.link_redirect_uri(),
               user_id: user.id
             ) do
          {:ok, url, txn} ->
            conn
            |> Transactions.put(txn)
            |> redirect(external: url)

          {:error, _reason} ->
            conn
            |> put_flash(:error, gettext("Mgl ID is temporarily unavailable. Try again later."))
            |> redirect(to: ~p"/settings")
        end
    end
  end

  def link_callback(conn, params) do
    user = current_user(conn)

    cond do
      not MglId.enabled?() ->
        conn
        |> put_flash(:error, gettext("Mgl ID login is disabled."))
        |> redirect(to: ~p"/settings")

      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("You must log in before connecting Mgl ID."))
        |> redirect(to: ~p"/login")

      error = params["error"] ->
        conn
        |> put_flash(:error, oauth_error_message(error, params["error_description"]))
        |> redirect(to: ~p"/settings")

      is_binary(params["code"]) and is_binary(params["state"]) ->
        finish_link(conn, user, params["code"], params["state"])

      true ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID link response."))
        |> redirect(to: ~p"/settings")
    end
  end

  @pending_link_session_key :mgl_pending_account_link
  @pending_link_ttl_seconds 300

  @doc """
  GET `/account/link?token=...&provider=xamt`

  Validates preconditions, stores the initiation token in the session bound to
  the signed-in user, and renders a confirmation scroll so a cross-site GET
  cannot silently link an attacker's Mgl ID.
  """
  def account_link_confirm(conn, params) do
    user = current_user(conn)
    token = params["token"]
    provider = params["provider"] || "xamt"

    cond do
      not MglId.enabled?() ->
        conn
        |> put_flash(:error, gettext("Mgl ID login is disabled."))
        |> redirect(to: ~p"/settings")

      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("You must log in before connecting Mgl ID."))
        |> redirect(to: ~p"/login")

      provider != "xamt" or not is_binary(token) or token == "" ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID link request."))
        |> redirect(to: ~p"/settings")

      Accounts.get_mgl_identity(user) ->
        # Common after first-time Mgl ID login with return_to=/account/link:
        # provisioning already linked this account. Treat as done.
        conn
        |> put_flash(:info, gettext("This Xamt account is already connected to Mgl ID."))
        |> redirect(to: ~p"/settings")

      true ->
        link_nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

        pending = %{
          "nonce" => link_nonce,
          "token" => token,
          "provider" => provider,
          "user_id" => to_string(user.id),
          "expires_at" =>
            DateTime.utc_now()
            |> DateTime.add(@pending_link_ttl_seconds, :second)
            |> DateTime.to_iso8601()
        }

        conn
        |> put_session(@pending_link_session_key, pending)
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("referrer-policy", "no-referrer")
        |> render(:account_link_confirm,
          page_title: gettext("Connect Mgl ID"),
          current_user: user,
          link_nonce: link_nonce
        )
    end
  end

  @doc """
  POST `/account/link`

  Consumes the session-bound initiation token after CSRF verification and
  completes the Mgl ID → Xamt account link.
  """
  def account_link(conn, params) do
    user = current_user(conn)
    pending = get_session(conn, @pending_link_session_key)
    conn = delete_session(conn, @pending_link_session_key)

    cond do
      not MglId.enabled?() ->
        conn
        |> put_flash(:error, gettext("Mgl ID login is disabled."))
        |> redirect(to: ~p"/settings")

      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("You must log in before connecting Mgl ID."))
        |> redirect(to: ~p"/login")

      not valid_pending_link?(pending, user, params["link_nonce"]) ->
        conn
        |> put_flash(:error, gettext("Mgl ID link expired. Please try again."))
        |> redirect(to: ~p"/settings")

      true ->
        case Auth.complete_account_link(user, pending["token"], pending["provider"]) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, gettext("Mgl ID connected successfully."))
            |> redirect(to: ~p"/settings")

          {:error, :user_already_linked} ->
            conn
            |> put_flash(:error, gettext("This Xamt account is already connected to Mgl ID."))
            |> redirect(to: ~p"/settings")

          {:error, :already_linked_other_user} ->
            conn
            |> put_flash(
              :error,
              gettext("This Mgl ID account is already connected to another Xamt account.")
            )
            |> redirect(to: ~p"/settings")

          {:error, :invalid_provider} ->
            conn
            |> put_flash(:error, gettext("Invalid Mgl ID link request."))
            |> redirect(to: ~p"/settings")

          {:error, {:account_link_confirm, status, _body}} when status in [410, 404] ->
            conn
            |> put_flash(:error, gettext("Mgl ID link expired. Please try again."))
            |> redirect(to: ~p"/settings")

          {:error, _reason} ->
            conn
            |> put_flash(:error, gettext("Could not connect Mgl ID."))
            |> redirect(to: ~p"/settings")
        end
    end
  end

  defp finish_login(conn, code, state) do
    {conn, result} = Transactions.take(conn, state)

    case result do
      {:ok, %{"purpose" => "login"} = txn} ->
        case Auth.complete_login(code, txn) do
          {:ok, user} ->
            conn
            |> put_flash(:info, gettext("Welcome back!"))
            |> UserAuth.log_in_user(user)

          {:error, _reason} ->
            conn
            |> put_flash(:error, gettext("Could not complete Mgl ID login."))
            |> redirect(to: ~p"/login")
        end

      {:ok, _other} ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID login transaction."))
        |> redirect(to: ~p"/login")

      {:error, :expired} ->
        conn
        |> put_flash(:error, gettext("Mgl ID login expired. Please try again."))
        |> redirect(to: ~p"/login")

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID login state."))
        |> redirect(to: ~p"/login")
    end
  end

  defp finish_link(conn, user, code, state) do
    {conn, result} = Transactions.take(conn, state)

    case result do
      {:ok, %{"purpose" => "link"} = txn} ->
        case Auth.complete_link(code, txn, user) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, gettext("Mgl ID connected successfully."))
            |> redirect(to: ~p"/settings")

          {:error, :already_linked_other_user} ->
            conn
            |> put_flash(
              :error,
              gettext("This Mgl ID account is already connected to another Xamt account.")
            )
            |> redirect(to: ~p"/settings")

          {:error, :user_already_linked} ->
            conn
            |> put_flash(:error, gettext("This Xamt account is already connected to Mgl ID."))
            |> redirect(to: ~p"/settings")

          {:error, _reason} ->
            conn
            |> put_flash(:error, gettext("Could not connect Mgl ID."))
            |> redirect(to: ~p"/settings")
        end

      {:ok, _other} ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID link transaction."))
        |> redirect(to: ~p"/settings")

      {:error, :expired} ->
        conn
        |> put_flash(:error, gettext("Mgl ID link expired. Please try again."))
        |> redirect(to: ~p"/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID link state."))
        |> redirect(to: ~p"/settings")
    end
  end

  defp current_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: user} -> user
      _ -> nil
    end
  end

  defp valid_pending_link?(
         %{
           "nonce" => expected_nonce,
           "token" => token,
           "provider" => provider,
           "user_id" => expected_user_id,
           "expires_at" => iso
         },
         user,
         submitted_nonce
       )
       when is_binary(token) and token != "" and is_binary(provider) and
              is_binary(submitted_nonce) do
    nonce_ok? =
      byte_size(expected_nonce) == byte_size(submitted_nonce) and
        Plug.Crypto.secure_compare(expected_nonce, submitted_nonce)

    user_ok? = expected_user_id == to_string(user.id)

    not_expired? =
      case DateTime.from_iso8601(iso) do
        {:ok, expires_at, _} -> DateTime.compare(DateTime.utc_now(), expires_at) != :gt
        _ -> false
      end

    nonce_ok? and user_ok? and not_expired?
  end

  defp valid_pending_link?(_, _, _), do: false

  defp oauth_error_message("access_denied", _),
    do: gettext("Mgl ID login was cancelled.")

  defp oauth_error_message(_error, description) when is_binary(description) and description != "",
    do: gettext("Mgl ID login failed: %{reason}", reason: description)

  defp oauth_error_message(_, _),
    do: gettext("Mgl ID login failed.")
end
