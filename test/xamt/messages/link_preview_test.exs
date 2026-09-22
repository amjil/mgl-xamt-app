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
    assert preview["type"] == "article"
    assert preview["provider"] == "OpenGraph"
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

  test "builds iframe urls only for allowlisted video ids" do
    youtube = %{
      "type" => "video",
      "provider" => "YouTube",
      "video_id" => "dQw4w9WgXcQ",
      "iframe_url" => "javascript:alert(1)"
    }

    assert LinkPreview.iframe_src(youtube) ==
             "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0"

    assert LinkPreview.iframe_src(%{youtube | "video_id" => "short"}) == nil
    assert LinkPreview.iframe_src(%{youtube | "video_id" => "dQw4w9WgXcQ/evil"}) == nil

    assert LinkPreview.iframe_src(%{
             "type" => "video",
             "provider" => "Bilibili",
             "video_id" => "BV1NgY5zUEiM"
           }) ==
             "https://player.bilibili.com/player.html?isOutside=true&bvid=BV1NgY5zUEiM&p=1&high_quality=1&danmaku=0&autoplay=0"

    assert LinkPreview.iframe_src(%{
             "type" => "video",
             "provider" => "Bilibili",
             "video_id" => "av170001"
           }) =~ "isOutside=true&aid=170001"

    assert LinkPreview.audio_sample_url(%{
             "type" => "audio_book",
             "audio_sample_url" => "javascript:alert(1)"
           }) == nil

    assert LinkPreview.audio_sample_url(%{
             "type" => "audio_book",
             "audio_sample_url" => "https://127.0.0.1/sample.m4a"
           }) == nil

    assert LinkPreview.preview_image(%{"image" => "javascript:alert(1)"}) == nil

    assert LinkPreview.page_url(%{"url" => "javascript:alert(1)"}) == nil

    assert LinkPreview.page_url(%{"url" => "https://example.com/story"}) ==
             "https://example.com/story"
  end

  test "routes YouTube links to a video card and ignores lookalike hosts", %{
    scope: scope,
    channel: channel
  } do
    enable_provider_preview!()

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://www.youtube.com/watch?v=dQw4w9WgXcQ</p>),
        "content" => %{"type" => "rich_text"}
      })

    preview = Messages.get_message!(message.id).link_preview
    assert preview["type"] == "video"
    assert preview["provider"] == "YouTube"
    assert preview["video_id"] == "dQw4w9WgXcQ"
    assert preview["title"] == "Jangar episode"
    assert preview["image"] == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
    refute Map.has_key?(preview, "iframe_url")

    {:ok, short} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://youtu.be/abcdefghijk</p>),
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.get_message!(short.id).link_preview["video_id"] == "abcdefghijk"

    {:ok, lookalike} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://notyoutube.com/watch?v=dQw4w9WgXcQ</p>),
        "content" => %{"type" => "rich_text"}
      })

    lookalike = Messages.get_message!(lookalike.id).link_preview
    assert lookalike["type"] == "article"
    refute Map.has_key?(lookalike, "video_id")
  end

  test "routes Bilibili pages and b23 short links to a video card", %{
    scope: scope,
    channel: channel
  } do
    enable_provider_preview!()

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" =>
          ~s(<p> https://www.bilibili.com/video/BV1NgY5zUEiM/?share_source=copy_web&amp;vd_source=afac77442229c491cfe53a1ce797831d</p>),
        "content" => %{"type" => "rich_text"}
      })

    preview = Messages.get_message!(message.id).link_preview
    assert preview["type"] == "video"
    assert preview["provider"] == "Bilibili"
    assert preview["video_id"] == "BV1NgY5zUEiM"
    assert preview["title"] == "Bilibili Title"

    {:ok, legacy} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://www.bilibili.com/video/av170001</p>),
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.get_message!(legacy.id).link_preview["video_id"] == "av170001"

    {:ok, short} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://b23.tv/abcd</p>),
        "content" => %{"type" => "rich_text"}
      })

    short = Messages.get_message!(short.id).link_preview
    assert short["type"] == "video"
    assert short["video_id"] == "BV1xx411c7mD"
    assert short["url"] == "https://b23.tv/abcd"
  end

  test "unfurls a configured audiobook URL and drops private media", %{
    scope: scope,
    channel: channel
  } do
    enable_provider_preview!()

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://audio-app-domain.com/books/jangar</p>),
        "content" => %{"type" => "rich_text"}
      })

    preview = Messages.get_message!(message.id).link_preview
    assert preview["type"] == "audio_book"
    assert preview["provider"] == "MyAudioApp"
    assert preview["title"] == "江格尔"
    assert preview["cover_url"] == "https://audio-app-domain.com/cover.jpg"
    assert preview["audio_sample_url"] == "https://cdn.example/sample.m4a"

    {:ok, poisoned} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => ~s(<p>https://audio-app-domain.com/books/secret</p>),
        "content" => %{"type" => "rich_text"}
      })

    poisoned = Messages.get_message!(poisoned.id).link_preview
    assert poisoned["title"] == "Secret"
    refute Map.has_key?(poisoned, "audio_sample_url")
  end

  defp enable_provider_preview! do
    plug = fn conn ->
      cond do
        String.contains?(conn.request_path, "/oembed") ->
          body =
            Jason.encode!(%{
              "title" => "Jangar episode",
              "thumbnail_url" => "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
            })

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, body)

        conn.host == "b23.tv" ->
          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "https://www.bilibili.com/video/BV1xx411c7mD"
          )
          |> Plug.Conn.send_resp(302, "")

        conn.host == "audio-app-domain.com" and conn.request_path == "/books/secret" ->
          body =
            Jason.encode!(%{
              "title" => "Secret",
              "audio_sample_url" => "http://127.0.0.1/sample.m4a",
              "cover_url" => "https://127.0.0.1/cover.jpg"
            })

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, body)

        conn.host == "audio-app-domain.com" ->
          body =
            Jason.encode!(%{
              "title" => "江格尔",
              "cover_url" => "/cover.jpg",
              "audio_sample_url" => "https://cdn.example/sample.m4a"
            })

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, body)

        true ->
          conn
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.send_resp(200, """
          <html>
            <head>
              <meta property="og:title" content="Bilibili Title">
              <meta property="og:description" content="A video page">
              <meta property="og:image" content="https://i0.hdslb.com/cover.jpg">
            </head>
          </html>
          """)
      end
    end

    Application.put_env(:xamt, LinkPreview,
      enabled: true,
      async: false,
      req_options: [plug: plug]
    )
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
