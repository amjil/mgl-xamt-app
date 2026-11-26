defmodule XamtWeb.MglAuthController do
  use XamtWeb, :controller

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

  @doc """
  Receives Mgl ID → Xamt account-link redirects (`?token=&provider=xamt`).

  Placed behind `require_authenticated_user` so ownership is proven by the
  existing Xamt session; unauthenticated users are sent to login with return_to.
  """
  def account_link(conn, params) do
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

      not is_binary(token) or token == "" ->
        conn
        |> put_flash(:error, gettext("Invalid Mgl ID link request."))
        |> redirect(to: ~p"/settings")

      true ->
        case Auth.complete_account_link(user, token, provider) do
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

  defp oauth_error_message("access_denied", _),
    do: gettext("Mgl ID login was cancelled.")

  defp oauth_error_message(_error, description) when is_binary(description) and description != "",
    do: gettext("Mgl ID login failed: %{reason}", reason: description)

  defp oauth_error_message(_, _),
    do: gettext("Mgl ID login failed.")
end
