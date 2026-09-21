defmodule Xamt.Messages.LinkPreviewTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Servers}
  alias Xamt.Messages.LinkPreview

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Preview"})
    channel = hd(Channels.list_channels(server.id))
    previous = Application.get_env(:xamt, LinkPreview)

    on_exit(fn -> Application.put_env(:xamt, LinkPreview, previous) end)

    %{scope: scope, channel: channel}
  end

  test "fetches Open Graph tags and broadcasts the updated message", %{
    scope: scope,
    channel: channel
  } do
    enable_preview!("""
    <html>
      <head>
        <meta property="og:title" content="OG Title">
        <meta property="og:description" content="OG Description">
        <meta property="og:image" content="/hero.png">
      </head>
    </html>
    """)

    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>see https://example.com/article</p>),
        "content" => %{"type" => "rich_text"}
      })

    assert_receive {:new_message, _}
    assert_receive {:updated_message, updated}

    assert updated.id == message.id
    assert updated.link_preview["url"] == "https://example.com/article"
    assert updated.link_preview["title"] == "OG Title"
    assert updated.link_preview["description"] == "OG Description"
    assert updated.link_preview["image"] == "https://example.com/hero.png"

    loaded = Messages.get_message!(message.id)
    assert loaded.link_preview == updated.link_preview
    assert DateTime.compare(loaded.updated_at, message.updated_at) == :eq
  end

  test "falls back to twitter and title tags", %{scope: scope, channel: channel} do
    enable_preview!("""
    <html>
      <head>
        <title>  Page Title  </title>
        <meta name="twitter:description" content="From twitter">
      </head>
    </html>
    """)

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p><a href="https://news.example">link</a></p>),
        "content" => %{"type" => "rich_text"}
      })

    preview = Messages.get_message!(message.id).link_preview
    assert preview["title"] == "Page Title"
    assert preview["description"] == "From twitter"
  end

  test "silently ignores fetch failures and private URLs", %{scope: scope, channel: channel} do
    enable_preview!("nope", status: 500)

    {:ok, failed} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://example.com/down</p>),
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.get_message!(failed.id).link_preview == nil

    {:ok, local} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>http://127.0.0.1/secret</p>),
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.get_message!(local.id).link_preview == nil
  end

  test "clears a preview when the URL is edited out", %{scope: scope, channel: channel} do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>no url yet</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, message} =
      Messages.put_link_preview(message, %{
        "url" => "https://example.com",
        "title" => "Stale"
      })

    enable_preview!("<html></html>")

    {:ok, _} =
      Messages.update_message(scope, message.id, %{
        "content_html" => "<p>url removed</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.get_message!(message.id).link_preview == nil
  end

  test "does not mark a message as edited when only the preview is stored", %{
    scope: scope,
    channel: channel
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>plain</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, updated} =
      Messages.put_link_preview(message, %{
        "url" => "https://example.com",
        "title" => "Card"
      })

    assert updated.link_preview["title"] == "Card"
    assert DateTime.compare(updated.updated_at, message.updated_at) == :eq
  end

  defp enable_preview!(body, opts \\ []) do
    status = Keyword.get(opts, :status, 200)

    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(status, body)
    end

    Application.put_env(:xamt, LinkPreview,
      enabled: true,
      async: false,
      req_options: [plug: plug]
    )
  end
end
