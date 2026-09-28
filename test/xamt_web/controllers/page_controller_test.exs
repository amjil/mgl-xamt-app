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
    assert conn.resp_body =~ "/fonts/OyunQaganTig.ttf"
    assert conn.resp_body =~ "/offline.html"
    assert conn.resp_body =~ "cacheFirst"
    assert conn.resp_body =~ ~s(addEventListener("push")
    assert conn.resp_body =~ ~s(addEventListener("notificationclick")
  end

  test "serves the static offline fallback page", %{conn: conn} do
    conn = get(conn, ~p"/offline.html")
    assert html_response(conn, 200) =~ "xamt-offline-page"
    assert html_response(conn, 200) =~ "/fonts/OyunQaganTig.ttf"
  end

  test "root layout mounts the reconnect banner", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "xamt-offline-banner"
    assert html_response(conn, 200) =~ "Network disconnected, reconnecting"
  end
end
