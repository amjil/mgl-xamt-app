defmodule XamtWeb.PageControllerTest do
  use XamtWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Xamt"
    assert html_response(conn, 200) =~ "Traditional Mongolian"
  end

  test "service worker is allowed to control the origin", %{conn: conn} do
    conn = get(conn, ~p"/pwa/service-worker.js")
    assert conn.status == 200
    assert get_resp_header(conn, "service-worker-allowed") == ["/"]
    assert "no-cache" in get_resp_header(conn, "cache-control")
    assert conn.resp_body =~ "sync-messages"
  end
end
