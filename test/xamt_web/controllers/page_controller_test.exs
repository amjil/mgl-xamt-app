defmodule XamtWeb.PageControllerTest do
  use XamtWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Xamt"
    assert html_response(conn, 200) =~ "Traditional Mongolian"
  end
end
