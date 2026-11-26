defmodule XamtWeb.UserSettingsController do
  use XamtWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Xamt.Accounts

  import XamtWeb.UserAuth, only: [require_sudo_mode: 2]

  plug :require_sudo_mode when action in [:edit, :update, :confirm_email]
  plug :assign_email_changeset when action in [:edit, :update]

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/users/settings")

      changeset ->
        render(conn, :edit, email_form: to_form(%{changeset | action: :insert}, as: :user))
    end
  end

  # Password updates were removed; any other action (e.g. a stale form) is a no-op.
  def update(conn, _params) do
    redirect(conn, to: ~p"/users/settings")
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_email_changeset(conn, _opts) do
    user = conn.assigns.current_scope.user

    assign(conn, :email_form, to_form(Accounts.change_user_email(user), as: :user))
  end
end
