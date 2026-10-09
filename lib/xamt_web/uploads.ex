defmodule XamtWeb.Uploads do
  @moduledoc """
  Persist LiveView uploads via `Xamt.Storage`.

  Public URLs stay `/uploads/:filename`. Bytes live on local disk or S3
  (SeaweedFS); `UploadController` authorizes before serving.
  """

  require Logger

  alias Xamt.Storage

  @image_exts ~w(.jpg .jpeg .png .gif .webp)
  @audio_exts ~w(.webm .mp4 .mp3 .ogg .wav)
  @audio_alias_exts %{
    ".m4a" => ".mp4",
    ".aac" => ".mp4",
    ".3gp" => ".mp4"
  }
  @thumb_max_edge 180
  # Real MediaRecorder blobs are at least a few KB; 4-byte test stubs are not playable.
  @min_audio_bytes 256

  @doc """
  Absolute directory for the local storage adapter (`priv/uploads`).
  Kept for tests and the migration task.
  """
  def dir, do: Storage.local_dir()

  @doc """
  Absolute disk path when using the local adapter.
  """
  def disk_path(url_or_name) when is_binary(url_or_name) do
    Xamt.Storage.Local.disk_path(Path.basename(url_or_name))
  end

  def consume_images(socket, name) do
    consume(socket, name, &image_ext/1)
  end

  def consume_image(socket, name) do
    List.first(consume_images(socket, name))
  end

  @doc """
  Persist uploaded images as original + thumbnail pairs.

  Returns a list of `%{"thumb" => url, "original" => url}`. On thumbnail
  failure (missing libvips, corrupt file), `thumb` falls back to `original`.
  """
  def consume_gallery_images(socket, name, server_id, user_id) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      case image_ext(entry) do
        ext when is_binary(ext) ->
          {:ok, persist_gallery_image(path, entry.uuid, ext)}

        _ ->
          {:ok, nil}
      end
    end)
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(&grant_gallery_image(&1, server_id, user_id))
  end

  def consume_audio(socket, name, server_id, user_id) do
    case List.first(consume(socket, name, &audio_ext/1, min_bytes: @min_audio_bytes)) do
      url when is_binary(url) ->
        case remember_upload(url, server_id, user_id) do
          {:ok, _} ->
            url

          _ ->
            delete_stored(url)
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Removes files previously persisted under `/uploads/...`.

  Used when `consume_*` succeeded but the following write (message, profile)
  failed, so the stored copy is not left orphaned.
  """
  def delete_stored(entries) when is_list(entries) do
    Enum.each(entries, &delete_stored/1)
  end

  def delete_stored(%{"thumb" => thumb, "original" => original}) do
    delete_stored(thumb)
    delete_stored(original)
  end

  def delete_stored(url) when is_binary(url) do
    name = Path.basename(url)

    if String.starts_with?(url, "/uploads/") and Xamt.Uploads.safe_filename?(name) do
      Storage.delete(name)
      Xamt.Uploads.revoke_server_file(name)
    end

    :ok
  end

  def delete_stored(_), do: :ok

  defp persist_gallery_image(path, uuid, ext) do
    original_name = "#{uuid}#{ext}"

    case Storage.put(original_name, path) do
      :ok ->
        original_url = "/uploads/#{original_name}"

        thumb_url =
          case write_thumbnail(path, uuid, ext) do
            {:ok, thumb_name} -> "/uploads/#{thumb_name}"
            :error -> original_url
          end

        %{"thumb" => thumb_url, "original" => original_url}

      {:error, reason} ->
        Logger.warning("gallery persist failed for #{uuid}: #{inspect(reason)}")
        nil
    end
  end

  defp grant_gallery_image(
         %{"thumb" => thumb, "original" => original} = image,
         server_id,
         user_id
       ) do
    urls = Enum.uniq([original, thumb])

    granted? =
      Enum.reduce_while(urls, true, fn url, true ->
        case remember_upload(url, server_id, user_id) do
          {:ok, _} -> {:cont, true}
          _ -> {:halt, false}
        end
      end)

    if granted? do
      [image]
    else
      delete_stored(image)
      []
    end
  end

  defp remember_upload(url, server_id, user_id) when is_binary(url) do
    Xamt.Uploads.grant_server_file(Path.basename(url), server_id, user_id)
  end

  defp write_thumbnail(original_path, uuid, ext) do
    thumb_name = "thumb_#{uuid}#{ext}"
    thumb_tmp = Path.join(System.tmp_dir!(), "xamt-#{thumb_name}")

    with {:ok, thumb} <- Image.thumbnail(original_path, @thumb_max_edge),
         {:ok, _} <- Image.write(thumb, thumb_tmp),
         :ok <- Storage.put(thumb_name, thumb_tmp) do
      File.rm(thumb_tmp)
      {:ok, thumb_name}
    else
      {:error, reason} ->
        File.rm(thumb_tmp)
        Logger.warning("gallery thumbnail failed for #{uuid}: #{inspect(reason)}")
        :error

      other ->
        File.rm(thumb_tmp)
        Logger.warning("gallery thumbnail failed for #{uuid}: #{inspect(other)}")
        :error
    end
  rescue
    error ->
      Logger.warning("gallery thumbnail crashed for #{uuid}: #{Exception.message(error)}")
      :error
  end

  defp consume(socket, name, ext_fun, opts \\ []) do
    min_bytes = Keyword.get(opts, :min_bytes, 0)

    Phoenix.LiveView.consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      ext = ext_fun.(entry)

      cond do
        not is_binary(ext) ->
          {:ok, nil}

        min_bytes > 0 and (not File.regular?(path) or File.stat!(path).size < min_bytes) ->
          {:ok, nil}

        true ->
          filename = "#{entry.uuid}#{ext}"

          case Storage.put(filename, path) do
            :ok ->
              {:ok, "/uploads/#{filename}"}

            {:error, reason} ->
              Logger.warning("upload persist failed for #{filename}: #{inspect(reason)}")
              {:ok, nil}
          end
      end
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp image_ext(entry) do
    ext = entry.client_name |> Path.extname() |> String.downcase()
    if ext in @image_exts, do: ext
  end

  defp audio_ext(entry) do
    ext = entry.client_name |> Path.extname() |> String.downcase()
    mime = entry.client_type || ""

    cond do
      Map.has_key?(@audio_alias_exts, ext) ->
        Map.fetch!(@audio_alias_exts, ext)

      ext in @audio_exts ->
        ext

      String.contains?(mime, "wav") ->
        ".wav"

      String.contains?(mime, "webm") ->
        ".webm"

      String.contains?(mime, "ogg") ->
        ".ogg"

      String.contains?(mime, "mpeg") or String.contains?(mime, "mp3") ->
        ".mp3"

      String.contains?(mime, "mp4") or String.contains?(mime, "m4a") or
        String.contains?(mime, "aac") or String.contains?(mime, "3gpp") ->
        ".mp4"

      true ->
        nil
    end
  end
end
