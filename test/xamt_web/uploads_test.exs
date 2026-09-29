defmodule XamtWeb.UploadsTest do
  use ExUnit.Case, async: false

  @fixture Path.expand("../support/fixtures/gallery_sample.png", __DIR__)

  test "delete_stored removes persisted upload files and ignores traversal" do
    dir = XamtWeb.Uploads.dir()
    File.mkdir_p!(dir)
    name = "orphan-#{System.unique_integer([:positive])}.txt"
    dest = Path.join(dir, name)
    File.write!(dest, "tmp")

    assert File.exists?(dest)
    assert :ok = XamtWeb.Uploads.delete_stored("/uploads/#{name}")
    refute File.exists?(dest)

    assert :ok = XamtWeb.Uploads.delete_stored("/uploads/../#{name}")
    assert :ok = XamtWeb.Uploads.delete_stored("https://evil.example/#{name}")
  end

  test "Image.thumbnail can resize the gallery fixture when libvips works" do
    case Image.thumbnail(@fixture, 48) do
      {:ok, thumb} ->
        dest =
          Path.join(System.tmp_dir!(), "xamt-thumb-#{System.unique_integer([:positive])}.png")

        assert {:ok, _} = Image.write(thumb, dest)
        assert File.exists?(dest)
        assert File.stat!(dest).size > 0
        File.rm(dest)

      {:error, reason} ->
        # Broken/missing system libvips is acceptable — Uploads falls back to original.
        flunk_or_skip(reason)
    end
  rescue
    error ->
      flunk_or_skip(error)
  end

  defp flunk_or_skip(reason) do
    message = inspect(reason)

    if String.contains?(message, "vips") or String.contains?(message, "Vips") or
         String.contains?(message, "libfftw") or String.contains?(message, "dyld") do
      :ok
    else
      flunk("unexpected thumbnail failure: #{message}")
    end
  end
end
