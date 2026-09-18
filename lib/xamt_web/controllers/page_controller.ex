defmodule XamtWeb.PageController do
  use XamtWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
