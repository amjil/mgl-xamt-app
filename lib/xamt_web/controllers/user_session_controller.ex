defmodule XamtWeb.UserSessionController do
  use XamtWeb, :controller

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.AuthRateLimit
  alias Xamt.SiteSettings
  alias XamtWeb.UserAuth

  def new(conn, _params) do
    email = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    form = Phoenix.Component.to_form(%{"email" => email}, as: "user")

    render(conn, :new, form: form)
  end

  # magic link login
  def create(conn, %{"user" => %{"token" => token} = user_params} = params) do
    info =
      case params do
        %{"_action" => "confirmed"} -> "User confirmed successfully."
        _ -> "Welcome back!"
      end

    case AuthRateLimit.check(:login, AuthRateLimit.client_key(conn)) do
      {:error, :rate_limited} ->
        rate_limited(conn, :new, form: Phoenix.Component.to_form(%{}, as: "user"))

      :ok ->
        case Accounts.get_user_by_magic_link_token(token) do
          %User{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
            if SiteSettings.magic_link_enabled?() do
              complete_magic_link_login(conn, token, user_params, info)
            else
              magic_link_login_closed(conn)
            end

          %User{} ->
            complete_magic_link_login(conn, token, user_params, info)

          nil ->
            conn
            |> put_flash(:error, "The link is invalid or it has expired.")
            |> render(:new, form: Phoenix.Component.to_form(%{}, as: "user"))
        end
    end
  end

  # email + password login
  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    form = Phoenix.Component.to_form(user_params, as: "user")

    case AuthRateLimit.check(:login, AuthRateLimit.client_key(conn)) do
      {:error, :rate_limited} ->
        rate_limited(conn, :new, form: form)

      :ok ->
        case Accounts.get_user_by_email_and_password(email, password) do
          %User{confirmed_at: confirmed} = user when not is_nil(confirmed) ->
            conn
            |> put_flash(:info, "Welcome back!")
            |> UserAuth.log_in_user(user, user_params)

          _ ->
            # Same copy for unknown, wrong password, and unconfirmed accounts.
            conn
            |> put_flash(:error, "Invalid email or password")
            |> render(:new, form: form)
        end
    end
  end

  # magic link request
  def create(conn, %{"user" => %{"email" => email}}) do
    if SiteSettings.magic_link_enabled?() do
      case AuthRateLimit.check(:magic_link, AuthRateLimit.client_key(conn)) do
        {:error, :rate_limited} ->
          conn
          |> put_flash(:error, gettext("Too many attempts. Try again shortly."))
          |> redirect(to: ~p"/users/log-in")

        :ok ->
          if user = Accounts.get_user_by_email(email) do
            Accounts.deliver_login_instructions(
              user,
              &url(~p"/users/log-in/#{&1}")
            )
          end

          info =
            "If your email is in our system, you will receive instructions for logging in shortly."

          conn
          |> put_flash(:info, info)
          |> redirect(to: ~p"/users/log-in")
      end
    else
      magic_link_login_closed(conn)
    end
  end

  def confirm(conn, %{"token" => token}) do
    case Accounts.get_user_by_magic_link_token(token) do
      %User{confirmed_at: confirmed_at} = user when not is_nil(confirmed_at) ->
        if SiteSettings.magic_link_enabled?() do
          render_magic_link_confirm(conn, user, token)
        else
          magic_link_login_closed(conn)
        end

      %User{} = user ->
        render_magic_link_confirm(conn, user, token)

      nil ->
        conn
        |> put_flash(:error, "Magic link is invalid or it has expired.")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp complete_magic_link_login(conn, token, user_params, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> render(:new, form: Phoenix.Component.to_form(%{}, as: "user"))
    end
  end

  defp render_magic_link_confirm(conn, user, token) do
    form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

    conn
    |> assign(:user, user)
    |> assign(:form, form)
    |> render(:confirm)
  end

  defp magic_link_login_closed(conn) do
    conn
    |> put_flash(:error, gettext("Magic link login is currently closed."))
    |> redirect(to: ~p"/login")
  end

  defp rate_limited(conn, template, assigns) do
    conn
    |> put_flash(:error, gettext("Too many attempts. Try again shortly."))
    |> render(template, assigns)
  end
end
