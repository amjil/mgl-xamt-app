defmodule XamtWeb.UserRegistrationController do
  use XamtWeb, :controller

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.SiteSettings
  alias XamtWeb.UserAuth

  plug :require_registration_enabled

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome to Xamt!")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
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
