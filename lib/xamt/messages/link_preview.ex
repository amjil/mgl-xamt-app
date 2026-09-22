defmodule Xamt.Messages.LinkPreview do
  @moduledoc """
  Unfurls the first URL in a message into a typed embed.

  Provider routing is a host allowlist, not a substring search: YouTube and
  Bilibili become video cards, configured audiobook hosts become player
  cards, and everything else stays an Open Graph article. Work runs under
  `Xamt.TaskSupervisor` so `create_message/3` is not blocked by slow or
  failing remote sites. Fetch failures are silent: the original message
  stays visible without a card.

  Video iframes are never stored. `iframe_src/1` rebuilds them at render
  time and only returns `youtube-nocookie.com` or `player.bilibili.com`.
  Those hosts are cross-origin, so a sandbox of `allow-scripts` plus
  `allow-same-origin` can run the player without granting it the Xamt
  origin's cookies.
  """

  alias Xamt.Messages
  alias Xamt.Messages.Message

  @max_bytes 2_000_000
  @max_text 150
  @receive_timeout 5_000
  @max_redirects 3
  @short_hops 3

  @url_re ~r/https?:\/\/[^\s<>"'\\]+/i
  @youtube_id_re ~r/^[A-Za-z0-9_-]{11}$/
  @bvid_re ~r/^BV[0-9A-Za-z]{10}$/
  @aid_re ~r/^[0-9]{1,16}$/
  @book_path_re ~r/^\/books\/([A-Za-z0-9_-]{1,64})\/?$/

  @iframe_sandbox "allow-scripts allow-same-origin allow-presentation"
  @iframe_allow "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen"

  @blocked_hosts MapSet.new([
                   "localhost",
                   "localhost.localdomain",
                   "127.0.0.1",
                   "0.0.0.0",
                   "::1",
                   "[::1]",
                   "metadata.google.internal"
                 ])

  @doc """
  Sandbox token list for third-party video iframes.

  `allow-scripts` with `allow-same-origin` is safe only because `iframe_src/1`
  never points at the application host.
  """
  def iframe_sandbox, do: @iframe_sandbox

  @doc """
  Feature policy for the video player. Playback only; no navigation or forms.
  """
  def iframe_allow, do: @iframe_allow

  @doc """
  Builds a video iframe URL from a stored preview.

  Returns `nil` unless `provider` and `video_id` match the allowlist. A stored
  `iframe_url` is ignored so a poisoned `link_preview` map cannot point the
  frame at `javascript:` or this application's origin.
  """
  def iframe_src(%{"type" => "video", "provider" => "YouTube", "video_id" => id}) do
    if youtube_id?(id) do
      "https://www.youtube-nocookie.com/embed/#{id}"
    end
  end

  def iframe_src(%{"type" => "video", "provider" => "Bilibili", "video_id" => "BV" <> _ = bvid}) do
    if Regex.match?(@bvid_re, bvid) do
      "https://player.bilibili.com/player.html?bvid=#{bvid}&high_quality=1&danmaku=0&autoplay=0"
    end
  end

  def iframe_src(%{"type" => "video", "provider" => "Bilibili", "video_id" => "av" <> aid}) do
    if Regex.match?(@aid_re, aid) do
      "https://player.bilibili.com/player.html?aid=#{aid}&high_quality=1&danmaku=0&autoplay=0"
    end
  end

  def iframe_src(_), do: nil

  @doc """
  HTTPS sample URL for an audiobook card, or `nil` when the value is not a
  public `https` URL.
  """
  def audio_sample_url(%{"type" => "audio_book", "audio_sample_url" => url}) do
    safe_remote_url(url, ["https"])
  end

  def audio_sample_url(_), do: nil

  @doc """
  Cover or article image that is safe to put in an `<img src>`.
  """
  def preview_image(%{"type" => "audio_book"} = preview) do
    safe_remote_url(preview["cover_url"] || preview["image"], ["https"])
  end

  def preview_image(%{"image" => url}), do: safe_remote_url(url, ["http", "https"])
  def preview_image(_), do: nil

  @doc """
  Public `http`/`https` page URL for a card link, or `nil`.
  """
  def page_url(%{"url" => url}), do: safe_remote_url(url, ["http", "https"])
  def page_url(_), do: nil

  @doc """
  Enqueues an unfurl for the first public URL in the message, or clears a
  stale preview when the message no longer contains a URL.
  """
  def maybe_fetch_and_update(%Message{} = message) do
    url = first_url(message.content_html)

    cond do
      not enabled?() ->
        :ok

      is_nil(url) ->
        clear_if_needed(message)

      same_preview_url?(message, url) ->
        :ok

      true ->
        run(fn -> unfurl(message, url) end)
    end
  end

  def maybe_fetch_and_update(_), do: :ok

  defp unfurl(message, url) do
    case classify(url) do
      {:video, provider, video_id} ->
        put_preview(message, video_preview(url, provider, video_id))

      :b23 ->
        case resolve_bilibili_short(url, @short_hops) do
          {:video, provider, video_id} ->
            put_preview(message, video_preview(url, provider, video_id))

          _ ->
            fetch_opengraph(message, url)
        end

      {:audio_book, book_id} ->
        fetch_audio_book(message, url, book_id)

      :opengraph ->
        fetch_opengraph(message, url)
    end
  end

  defp classify(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host && String.downcase(uri.host)

    cond do
      youtube_host?(host) ->
        case capture_youtube_id(uri) do
          id when is_binary(id) -> {:video, "YouTube", id}
          _ -> :opengraph
        end

      bilibili_host?(host) ->
        case capture_bilibili_id(uri) do
          id when is_binary(id) -> {:video, "Bilibili", id}
          _ -> :opengraph
        end

      b23_host?(host) ->
        :b23

      audio_book_host?(host) ->
        case capture_book_id(uri.path) do
          id when is_binary(id) -> {:audio_book, id}
          _ -> :opengraph
        end

      true ->
        :opengraph
    end
  end

  defp video_preview(url, "YouTube" = provider, video_id) do
    %{
      "type" => "video",
      "provider" => provider,
      "video_id" => video_id,
      "url" => url
    }
    |> merge_text_fields(youtube_oembed(url))
  end

  defp video_preview(url, provider, video_id) do
    %{
      "type" => "video",
      "provider" => provider,
      "video_id" => video_id,
      "url" => url
    }
    |> merge_text_fields(opengraph_fields(url))
  end

  defp merge_text_fields(base, fields) when is_map(fields) do
    Map.merge(base, Map.take(fields, ["title", "description", "image"]))
  end

  defp youtube_oembed(url) do
    oembed_url = "https://www.youtube.com/oembed?format=json&url=" <> URI.encode_www_form(url)

    with {:ok, %{status: 200, body: body} = resp} <-
           http_get(oembed_url, accept: "application/json"),
         true <- json_response?(resp),
         {:ok, map} when is_map(map) <- decode_json(body) do
      %{}
      |> maybe_put("title", map |> string_field(["title"]) |> clean_text())
      |> maybe_put("image", map |> string_field(["thumbnail_url"]) |> https_media_url())
    else
      _ -> %{}
    end
  end

  defp resolve_bilibili_short(_url, hops) when hops <= 0, do: nil

  defp resolve_bilibili_short(url, hops) do
    case http_get(url, redirect: false) do
      {:ok, %{status: status} = resp} when status in [301, 302, 303, 307, 308] ->
        with [location | _] <- Req.Response.get_header(resp, "location"),
             next when is_binary(next) <- expand_location(url, location),
             true <- fetchable_url?(next) do
          case classify(next) do
            {:video, provider, video_id} -> {:video, provider, video_id}
            :b23 -> resolve_bilibili_short(next, hops - 1)
            _ -> nil
          end
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp expand_location(base, location) when is_binary(location) do
    base
    |> URI.parse()
    |> URI.merge(String.trim(location))
    |> URI.to_string()
  rescue
    ArgumentError -> nil
  end

  defp fetch_audio_book(message, url, _book_id) do
    case audio_book_fields(url) do
      fields when map_size(fields) > 0 ->
        put_preview(message, fields)

      _ ->
        clear_stale_or_error(message, url)
    end
  end

  defp audio_book_fields(url) do
    with {:ok, %{status: 200, body: body} = resp} <-
           http_get(url, accept: "application/json, text/html;q=0.9, */*;q=0.8"),
         true <- body_within_limit?(body) do
      cond do
        json_response?(resp) ->
          case decode_json(body) do
            {:ok, map} when is_map(map) -> audio_book_from_map(map, url)
            _ -> %{}
          end

        html_response?(resp) and is_binary(body) ->
          audio_book_from_html(body, url)

        true ->
          %{}
      end
    else
      _ -> %{}
    end
  end

  defp audio_book_from_map(map, url) when is_map(map) do
    title = map |> string_field(["title", "name"]) |> clean_text()
    description = map |> string_field(["description", "desc", "summary"]) |> clean_text()

    cover =
      map
      |> string_field(["cover_url", "cover", "image", "image_url"])
      |> absolutize_url(url)
      |> https_media_url()

    audio =
      map
      |> string_field(["audio_sample_url", "audio_url", "sample_url", "audio"])
      |> absolutize_url(url)
      |> https_media_url()

    pack_audio_book(url, title, description, cover, audio)
  end

  defp audio_book_from_html(html, url) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        fields = doc_fields(doc, url)

        audio =
          (meta(doc, "og:audio:secure_url") ||
             meta(doc, "og:audio") ||
             meta(doc, "twitter:player:stream"))
          |> absolutize_url(url)
          |> https_media_url()

        cover = https_media_url(fields["image"])

        pack_audio_book(url, fields["title"], fields["description"], cover, audio)

      _ ->
        %{}
    end
  end

  defp pack_audio_book(url, title, description, cover, audio) do
    %{
      "type" => "audio_book",
      "provider" => audio_book_provider(),
      "url" => url,
      "title" => title,
      "description" => description,
      "cover_url" => cover,
      "image" => cover,
      "audio_sample_url" => audio
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
    |> keep_audio_book()
  end

  defp keep_audio_book(preview) do
    if Map.has_key?(preview, "title") or Map.has_key?(preview, "cover_url") or
         Map.has_key?(preview, "audio_sample_url") do
      preview
    else
      %{}
    end
  end

  defp fetch_opengraph(message, url) do
    case opengraph_fields(url) do
      fields when map_size(fields) > 0 ->
        preview =
          fields
          |> Map.put("type", "article")
          |> Map.put("provider", "OpenGraph")
          |> Map.put("url", url)

        put_preview(message, preview)

      _ ->
        clear_stale_or_error(message, url)
    end
  end

  defp opengraph_fields(url) do
    with {:ok, %{status: 200, body: body} = resp} <- http_get(url),
         true <- html_response?(resp),
         true <- binary_body?(body) do
      parse_html(body, url)
    else
      _ -> %{}
    end
  end

  defp put_preview(message, preview) when is_map(preview) and map_size(preview) > 0 do
    Messages.put_link_preview(message, preview)
  end

  defp put_preview(message, _) do
    clear_stale_or_error(message, nil)
  end

  defp clear_stale_or_error(message, url) do
    if stale_preview?(message, url) do
      Messages.put_link_preview(message, nil)
    else
      :error
    end
  end

  defp first_url(html) when is_binary(html) do
    @url_re
    |> Regex.scan(html)
    |> Enum.map(fn [raw | _] -> normalize_url(raw) end)
    |> Enum.find(&fetchable_url?/1)
  end

  defp first_url(_), do: nil

  defp normalize_url(url) do
    url
    |> String.replace("&amp;", "&")
    |> String.trim_trailing(".,);]!?'\"")
  end

  defp same_preview_url?(%Message{link_preview: %{"url" => url}}, url), do: true
  defp same_preview_url?(_, _), do: false

  defp clear_if_needed(%Message{link_preview: preview} = message)
       when is_map(preview) and map_size(preview) > 0 do
    Messages.put_link_preview(message, nil)
  end

  defp clear_if_needed(_), do: :ok

  defp stale_preview?(%Message{link_preview: %{"url" => existing}}, url)
       when is_binary(existing) and existing != url,
       do: true

  defp stale_preview?(_, _), do: false

  defp http_get(url, opts \\ []) do
    accept =
      Keyword.get(opts, :accept, "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8")

    req_opts =
      [
        receive_timeout: @receive_timeout,
        connect_options: [timeout: @receive_timeout],
        retry: false,
        redirect: Keyword.get(opts, :redirect, true),
        max_redirects: Keyword.get(opts, :max_redirects, @max_redirects),
        redirect_log_level: false,
        headers: [
          {"accept", accept},
          {"user-agent", "XamtLinkPreview/1.0"}
        ]
      ]
      |> Keyword.merge(req_options())

    req_opts =
      if Keyword.has_key?(req_opts, :plug) do
        req_opts
      else
        Keyword.put(req_opts, :into, &collect_limited/2)
      end

    Req.get(url, req_opts)
  end

  defp collect_limited({:data, chunk}, {req, resp}) do
    body = IO.iodata_to_binary([resp.body || "", chunk])

    if byte_size(body) > @max_bytes do
      {:halt, {req, %{resp | body: :too_large}}}
    else
      {:cont, {req, %{resp | body: body}}}
    end
  end

  defp binary_body?(body) when is_binary(body), do: byte_size(body) <= @max_bytes
  defp binary_body?(_), do: false

  defp body_within_limit?(body) when is_binary(body), do: byte_size(body) <= @max_bytes
  defp body_within_limit?(body) when is_map(body), do: true
  defp body_within_limit?(_), do: false

  # Req decodes JSON itself when the plug (or the server) sends application/json.
  defp decode_json(body) when is_map(body), do: {:ok, body}

  defp decode_json(body) when is_binary(body) do
    if byte_size(body) <= @max_bytes, do: Jason.decode(body), else: :error
  end

  defp decode_json(_), do: :error

  defp html_response?(resp) do
    case Req.Response.get_header(resp, "content-type") do
      [] ->
        true

      [type | _] ->
        type = String.downcase(type)
        String.contains?(type, "html") or String.starts_with?(type, "text/plain")
    end
  end

  defp json_response?(resp) do
    case Req.Response.get_header(resp, "content-type") do
      [type | _] -> String.contains?(String.downcase(type), "json")
      _ -> false
    end
  end

  defp parse_html(html, source_url) do
    case Floki.parse_document(html) do
      {:ok, doc} -> doc_fields(doc, source_url)
      _ -> %{}
    end
  end

  defp doc_fields(doc, source_url) do
    title =
      meta(doc, "og:title") ||
        meta(doc, "twitter:title") ||
        document_title(doc)

    desc =
      meta(doc, "og:description") ||
        meta(doc, "twitter:description") ||
        meta(doc, "description")

    image =
      meta(doc, "og:image") ||
        meta(doc, "og:image:secure_url") ||
        meta(doc, "twitter:image") ||
        meta(doc, "twitter:image:src")

    %{
      "title" => clean_text(title),
      "description" => clean_text(desc),
      "image" => absolutize_url(image, source_url)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
    |> keep_if_useful()
  end

  defp keep_if_useful(preview) do
    if Map.has_key?(preview, "title") or Map.has_key?(preview, "description") or
         Map.has_key?(preview, "image") do
      preview
    else
      %{}
    end
  end

  defp meta(doc, key) do
    extract_meta(doc, key, "property") || extract_meta(doc, key, "name")
  end

  defp extract_meta(doc, property, attr) do
    doc
    |> Floki.find("meta[#{attr}='#{property}']")
    |> Floki.attribute("content")
    |> List.first()
    |> blank_to_nil()
  end

  defp document_title(doc) do
    case Floki.find(doc, "title") do
      [] -> nil
      nodes -> nodes |> Floki.text() |> blank_to_nil()
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp clean_text(nil), do: nil

  defp clean_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]*>/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_text)
    |> blank_to_nil()
  end

  defp clean_text(_), do: nil

  defp absolutize_url(nil, _source_url), do: nil

  defp absolutize_url(image, source_url) when is_binary(image) do
    image = String.trim(image)

    with true <- image != "",
         %URI{} = source <- URI.parse(source_url),
         %URI{} = resolved <- URI.merge(source, image),
         true <- resolved.scheme in ["http", "https"],
         true <- is_binary(resolved.host) and resolved.host != "" do
      URI.to_string(resolved)
    else
      _ -> nil
    end
  end

  defp https_media_url(url), do: safe_remote_url(url, ["https"])

  defp safe_remote_url(url, schemes) when is_binary(url) and is_list(schemes) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, userinfo: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if scheme in schemes and not blocked_host?(String.downcase(host)) do
          url
        end

      _ ->
        nil
    end
  end

  defp safe_remote_url(_, _), do: nil

  defp string_field(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_binary(value) ->
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end

        _ ->
          nil
      end
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp youtube_host?(nil), do: false

  defp youtube_host?(host) do
    host in ["youtube.com", "youtu.be", "youtube-nocookie.com"] or
      String.ends_with?(host, ".youtube.com") or
      String.ends_with?(host, ".youtube-nocookie.com")
  end

  defp bilibili_host?(host) when is_binary(host) do
    host == "bilibili.com" or String.ends_with?(host, ".bilibili.com")
  end

  defp bilibili_host?(_), do: false

  defp b23_host?(host) when is_binary(host) do
    host == "b23.tv" or String.ends_with?(host, ".b23.tv")
  end

  defp b23_host?(_), do: false

  defp audio_book_host?(host) when is_binary(host) do
    Enum.any?(audio_book_hosts(), fn allowed ->
      host == allowed or host == "www." <> allowed
    end)
  end

  defp audio_book_host?(_), do: false

  defp capture_youtube_id(%URI{host: host, path: path, query: query}) do
    host = host && String.downcase(host)

    cond do
      host == "youtu.be" ->
        path |> path_head() |> youtube_id()

      youtube_host?(host) ->
        from_query = query && query |> URI.decode_query() |> Map.get("v") |> youtube_id()
        from_query || youtube_path_id(path)

      true ->
        nil
    end
  end

  defp youtube_path_id(path) do
    case String.split(path || "", "/", trim: true) do
      [kind, id | _] when kind in ["embed", "shorts", "live", "v"] -> youtube_id(id)
      _ -> nil
    end
  end

  defp path_head(nil), do: nil

  defp path_head(path) do
    path
    |> String.split("/", trim: true)
    |> List.first()
  end

  defp youtube_id(id) when is_binary(id) do
    id =
      id
      |> String.split(["?", "&", "#"], parts: 2)
      |> hd()
      |> String.trim()

    if Regex.match?(@youtube_id_re, id), do: id, else: nil
  end

  defp youtube_id(_), do: nil

  defp youtube_id?(id) when is_binary(id), do: Regex.match?(@youtube_id_re, id)
  defp youtube_id?(_), do: false

  defp capture_bilibili_id(%URI{path: path, query: query}) do
    from_query =
      if is_binary(query) do
        params = URI.decode_query(query)
        bvid_id(params["bvid"]) || aid_id(params["aid"])
      end

    from_query || bvid_from_path(path) || aid_from_path(path)
  end

  defp bvid_from_path(path) do
    case Regex.run(~r"/video/(BV[0-9A-Za-z]{10})(?:/|$|\?)", path || "") do
      [_, bvid] -> bvid_id(bvid)
      _ -> nil
    end
  end

  defp aid_from_path(path) do
    case Regex.run(~r"/video/av([0-9]{1,16})(?:/|$|\?)", path || "") do
      [_, aid] -> aid_id(aid)
      _ -> nil
    end
  end

  defp bvid_id(id) when is_binary(id) do
    if Regex.match?(@bvid_re, id), do: id, else: nil
  end

  defp bvid_id(_), do: nil

  defp aid_id(id) when is_binary(id) do
    if Regex.match?(@aid_re, id), do: "av" <> id, else: nil
  end

  defp aid_id(_), do: nil

  defp capture_book_id(path) do
    case Regex.run(@book_path_re, path || "") do
      [_, id] -> id
      _ -> nil
    end
  end

  defp fetchable_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host = String.downcase(host)

        cond do
          blocked_host?(host) -> false
          Keyword.has_key?(req_options(), :plug) -> true
          true -> public_dns?(host)
        end

      _ ->
        false
    end
  end

  defp blocked_host?(host) do
    MapSet.member?(@blocked_hosts, host) or private_ip_literal?(host) or
      String.ends_with?(host, ".localhost") or String.ends_with?(host, ".local")
  end

  defp private_ip_literal?(host) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]")

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, addr} -> not public_ip?(addr)
      {:error, _} -> false
    end
  end

  defp public_dns?(host) do
    host_c = String.to_charlist(host)

    case :inet.getaddrs(host_c, :inet) do
      {:ok, addrs} when addrs != [] ->
        Enum.all?(addrs, &public_ip?/1)

      _ ->
        case :inet.getaddrs(host_c, :inet6) do
          {:ok, addrs} when addrs != [] -> Enum.all?(addrs, &public_ip?/1)
          _ -> false
        end
    end
  end

  defp public_ip?({a, b, _, _}) do
    not (a == 0 or a == 10 or a == 127 or (a == 169 and b == 254) or
           (a == 172 and b in 16..31) or (a == 192 and b == 168) or
           (a == 100 and b in 64..127))
  end

  defp public_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  defp public_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: false

  defp public_ip?({0, 0, 0, 0, 0, 65535, hi, lo}) do
    public_ip?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})
  end

  defp public_ip?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF, do: false
  defp public_ip?({a, _, _, _, _, _, _, _}) when a in 0xFE80..0xFEBF, do: false
  defp public_ip?({_, _, _, _, _, _, _, _}), do: true

  defp run(fun) do
    if async?() do
      Task.Supervisor.start_child(Xamt.TaskSupervisor, fun)
    else
      fun.()
    end
  end

  defp audio_book_hosts do
    hosts = Keyword.get(config(), :audio_book_hosts, ["audio-app-domain.com"])

    Enum.flat_map(hosts, fn host ->
      case host |> to_string() |> String.trim() |> String.downcase() do
        "" -> []
        trimmed -> [trimmed]
      end
    end)
  end

  defp audio_book_provider do
    case Keyword.get(config(), :audio_book_provider, "MyAudioApp") do
      name when is_binary(name) ->
        case String.trim(name) do
          "" -> "MyAudioApp"
          trimmed -> String.slice(trimmed, 0, 40)
        end

      _ ->
        "MyAudioApp"
    end
  end

  defp enabled?, do: Keyword.get(config(), :enabled, true)
  defp async?, do: Keyword.get(config(), :async, true)
  defp req_options, do: Keyword.get(config(), :req_options, [])
  defp config, do: Application.get_env(:xamt, __MODULE__, [])
end
