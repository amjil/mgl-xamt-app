defmodule XamtWeb.UserSessionController do
  use XamtWeb, :controller

  alias XamtWeb.UserAuth

  # Sign-in is Mgl ID only (see `XamtWeb.MglAuthController`). This controller
  # just renders the login page and handles logout.
  def new(conn, _params) do
    render(conn, :new)
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
