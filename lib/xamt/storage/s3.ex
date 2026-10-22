defmodule Xamt.Storage.S3 do
  @moduledoc false

  @behaviour Xamt.Storage

  require Logger

  alias Xamt.Storage.S3.Auth

  @impl true
  def put(key, source, opts) when is_binary(source) do
    body =
      if file_path?(source) do
        File.read!(source)
      else
        source
      end

    content_type = Keyword.get(opts, :content_type) || content_type_for(key)
    config = config!()
    url = object_url(config, key)

    headers =
      Auth.sign(:put, url, body, config, [
        {"content-type", content_type}
      ])

    case Req.put(url, body: body, headers: headers, decode_body: false, redirect: false) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: resp}} ->
        Logger.warning("S3 put failed status=#{status} key=#{key} body=#{inspect_body(resp)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("S3 put error key=#{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    config = config!()
    url = object_url(config, key)
    headers = Auth.sign(:delete, url, "", config, [])

    case Req.delete(url, headers: headers, decode_body: false, redirect: false) do
      {:ok, %{status: status}} when status in [200, 204, 404] ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def exists?(key) do
    config = config!()
    url = object_url(config, key)
    headers = Auth.sign(:head, url, "", config, [])

    case Req.head(url, headers: headers, decode_body: false, redirect: false) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  @impl true
  def fetch(key) do
    config = config!()
    url = object_url(config, key)
    headers = Auth.sign(:get, url, "", config, [])

    case Req.get(url, headers: headers, decode_body: false, redirect: false) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp object_url(config, key) do
    endpoint = String.trim_trailing(config.endpoint, "/")
    bucket = config.bucket
    # Filenames are already restricted to [A-Za-z0-9._-].
    "#{endpoint}/#{bucket}/#{key}"
  end

  defp config! do
    cfg = Application.get_env(:xamt, Xamt.Storage, [])

    %{
      endpoint: Keyword.fetch!(cfg, :endpoint),
      bucket: Keyword.fetch!(cfg, :bucket),
      access_key: Keyword.fetch!(cfg, :access_key),
      secret_key: Keyword.fetch!(cfg, :secret_key),
      region: Keyword.get(cfg, :region, "us-east-1")
    }
  end

  defp file_path?(source) do
    (String.starts_with?(source, "/") or String.match?(source, ~r/^[A-Za-z]:[\\\/]/)) and
      File.regular?(source)
  end

  defp content_type_for(key) do
    case key |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".webm" -> "audio/webm"
      ".mp4" -> "audio/mp4"
      ".mp3" -> "audio/mpeg"
      ".ogg" -> "audio/ogg"
      ".wav" -> "audio/wav"
      _ -> "application/octet-stream"
    end
  end

  defp inspect_body(body) when is_binary(body), do: String.slice(body, 0, 200)
  defp inspect_body(body), do: inspect(body)
end
