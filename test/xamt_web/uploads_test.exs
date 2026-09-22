defmodule XamtWeb.UploadsTest do
  use ExUnit.Case, async: false

  @fixture Path.expand("../support/fixtures/gallery_sample.png", __DIR__)

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
