defmodule XamtWeb.ErrorHTMLTest do
  use XamtWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(XamtWeb.ErrorHTML, "404", "html", [])
    assert html =~ "Not Found"
    assert html =~ "error-404-canvas"
  end

  test "renders 500.html" do
    html = render_to_string(XamtWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Internal Server Error"
    assert html =~ "error-500-canvas"
  end
end
