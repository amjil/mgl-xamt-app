defmodule XamtWeb.UserRegistrationController do
  use XamtWeb, :controller

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.SiteSettings

  plug :require_registration_enabled

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Xamt.AuthRateLimit.check(:register, Xamt.AuthRateLimit.client_key(conn)) do
      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, gettext("Too many attempts. Try again shortly."))
        |> render(:new, changeset: Accounts.change_user_registration(%User{}, user_params))

      :ok ->
        case Accounts.register_user(user_params) do
          {:ok, user} ->
            {:ok, _} =
              Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

            conn
            |> put_flash(
              :info,
              gettext("Check your email to confirm your account before logging in.")
            )
            |> redirect(to: ~p"/login")

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :new, changeset: changeset)
        end
    end
  end

  defp require_registration_enabled(conn, _opts) do
    if SiteSettings.registration_enabled?() do
      conn
    else
      conn
      |> put_flash(:error, gettext("Registration is currently closed."))
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end
end
