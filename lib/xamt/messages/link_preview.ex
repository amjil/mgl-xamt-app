defmodule Xamt.Messages.LinkPreview do
  @moduledoc """
  Extracts the first URL from a message and fetches Open Graph metadata.

  Work runs under `Xamt.TaskSupervisor` so `create_message/3` is not blocked
  by slow or failing remote sites. Fetch failures are silent: the original
  message stays visible without a card.
  """

  alias Xamt.Messages
  alias Xamt.Messages.Message

  @max_bytes 2_000_000
  @max_text 150
  @receive_timeout 5_000
  @max_redirects 3

  @url_re ~r/https?:\/\/[^\s<>"'\\]+/i

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
  Enqueues an OG fetch for the first public URL in the message, or clears a
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
        run(fn -> fetch_og_data(message, url) end)
    end
  end

  def maybe_fetch_and_update(_), do: :ok

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

  defp fetch_og_data(message, url) do
    with {:ok, %{status: 200, body: body} = resp} <- http_get(url),
         true <- html_response?(resp),
         true <- binary_body?(body),
         preview when map_size(preview) > 0 <- parse_html(body, url) do
      Messages.put_link_preview(message, preview)
    else
      _ ->
        if stale_preview?(message, url) do
          Messages.put_link_preview(message, nil)
        else
          :error
        end
    end
  end

  defp stale_preview?(%Message{link_preview: %{"url" => existing}}, url)
       when is_binary(existing) and existing != url,
       do: true

  defp stale_preview?(_, _), do: false

  defp http_get(url) do
    opts =
      [
        receive_timeout: @receive_timeout,
        connect_options: [timeout: @receive_timeout],
        retry: false,
        max_redirects: @max_redirects,
        redirect_log_level: false,
        headers: [{"accept", "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"}]
      ]
      |> Keyword.merge(req_options())

    opts =
      if Keyword.has_key?(opts, :plug) do
        opts
      else
        Keyword.put(opts, :into, &collect_limited/2)
      end

    Req.get(url, opts)
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

  defp html_response?(resp) do
    case Req.Response.get_header(resp, "content-type") do
      [] ->
        true

      [type | _] ->
        type = String.downcase(type)
        String.contains?(type, "html") or String.starts_with?(type, "text/plain")
    end
  end

  defp parse_html(html, source_url) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
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
          "url" => source_url,
          "title" => clean_text(title),
          "description" => clean_text(desc),
          "image" => absolutize_image(image, source_url)
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
        |> Map.new()
        |> keep_if_useful()

      _ ->
        %{}
    end
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
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_text)
    |> blank_to_nil()
  end

  defp absolutize_image(nil, _source_url), do: nil

  defp absolutize_image(image, source_url) when is_binary(image) do
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

  defp enabled?, do: Keyword.get(config(), :enabled, true)
  defp async?, do: Keyword.get(config(), :async, true)
  defp req_options, do: Keyword.get(config(), :req_options, [])
  defp config, do: Application.get_env(:xamt, __MODULE__, [])
end
