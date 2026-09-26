defmodule XamtWeb.UploadController do
  @moduledoc """
  Authenticated (or publicly referenced) file serving for `/uploads/:filename`.

  Files stay on disk under `priv/static/uploads` but are no longer served by
  `Plug.Static`, so membership / avatar checks run before bytes leave the app.
  """

  use XamtWeb, :controller

  alias Xamt.Uploads

  def show(conn, %{"filename" => filename}) do
    user = current_user(conn)
    path = "/uploads/#{filename}"

    with true <- Uploads.safe_filename?(filename),
         disk when is_binary(disk) <- existing_disk_path(filename),
         true <- Uploads.visible_to_user?(path, user) do
      conn
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> put_resp_content_type(content_type(filename), nil)
      |> send_file(200, disk)
    else
      _ ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_status(:not_found)
        |> text("Not Found")
    end
  end

  defp current_user(conn) do
    case conn.assigns[:current_scope] do
      %{user: user} -> user
      _ -> nil
    end
  end

  defp existing_disk_path(filename) do
    disk = Path.join([:code.priv_dir(:xamt), "static", "uploads", filename])

    if File.regular?(disk) do
      disk
    end
  end

  defp content_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
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
end
