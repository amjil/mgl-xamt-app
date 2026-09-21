defmodule Xamt.Messages.HtmlSanitizerTest do
  use ExUnit.Case, async: true

  alias Xamt.Messages.HtmlSanitizer

  test "strips script tags and event handlers" do
    html =
      ~s|<p>hi<img src=x onerror="alert(1)"><script>alert(1)</script></p>|

    cleaned = HtmlSanitizer.sanitize(html)

    refute cleaned =~ "script"
    refute cleaned =~ "onerror"
    refute cleaned =~ "alert"
    assert cleaned =~ "hi"
  end

  test "keeps safe formatting and upload images" do
    html =
      ~s(<div class="editor-image"><img src="/uploads/abc.png" alt="pic"></div><p><strong>bold</strong></p>)

    cleaned = HtmlSanitizer.sanitize(html)

    assert cleaned =~ ~s(src="/uploads/abc.png")
    assert cleaned =~ "bold"
    assert cleaned =~ "strong"
    assert cleaned =~ "editor-image"
  end

  test "drops javascript hrefs and path traversal uploads" do
    html =
      ~s|<a href="javascript:alert(1)">x</a><img src="/uploads/../secret">|

    cleaned = HtmlSanitizer.sanitize(html)

    refute cleaned =~ "javascript"
    refute cleaned =~ "src="
  end

  test "preserves mention data attributes for later rewriting" do
    id = Ecto.UUID.generate()

    html =
      ~s(<p><span class="xamt-mention" data-mention-id="#{id}" data-mention-username="bob">@bob</span></p>)

    cleaned = HtmlSanitizer.sanitize(html)

    assert cleaned =~ ~s(data-mention-id="#{id}")
    assert cleaned =~ ~s(data-mention-username="bob")
  end
end
