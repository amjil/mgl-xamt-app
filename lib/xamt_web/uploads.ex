defmodule XamtWeb.Uploads do
  @moduledoc """
  Persist LiveView uploads under `priv/static/uploads`.
  """

  @image_exts ~w(.jpg .jpeg .png .gif .webp)
  @audio_exts ~w(.webm .mp4 .mp3 .ogg .wav)
  @audio_alias_exts %{
    ".m4a" => ".mp4",
    ".aac" => ".mp4",
    ".3gp" => ".mp4"
  }

  def consume_images(socket, name) do
    consume(socket, name, &image_ext/1)
  end

  def consume_image(socket, name) do
    List.first(consume_images(socket, name))
  end

  def consume_audio(socket, name) do
    List.first(consume(socket, name, &audio_ext/1))
  end

  defp consume(socket, name, ext_fun) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      ext = ext_fun.(entry)

      if is_binary(ext) do
        filename = "#{entry.uuid}#{ext}"
        dest = Path.join([:code.priv_dir(:xamt), "static", "uploads", filename])
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/#{filename}"}
      else
        {:ok, nil}
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
