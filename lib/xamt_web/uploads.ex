defmodule XamtWeb.Uploads do
  @moduledoc """
  Persist LiveView image uploads under `priv/static/uploads`.
  """

  @exts ~w(.jpg .jpeg .png .gif .webp)

  def consume_images(socket, name) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      ext = entry.client_name |> Path.extname() |> String.downcase()

      if ext in @exts do
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

  def consume_image(socket, name) do
    List.first(consume_images(socket, name))
  end
end
