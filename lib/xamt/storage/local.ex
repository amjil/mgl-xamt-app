defmodule Xamt.Storage.Local do
  @moduledoc false

  @behaviour Xamt.Storage

  @impl true
  def put(key, source, _opts) when is_binary(source) do
    dest = disk_path(key)
    File.mkdir_p!(Path.dirname(dest))

    if file_path?(source) do
      File.cp!(source, dest)
    else
      File.write!(dest, source)
    end

    :ok
  rescue
    e -> {:error, e}
  end

  # LiveView / migration pass absolute temp paths; tests may pass raw bytes.
  defp file_path?(source) do
    (String.starts_with?(source, "/") or String.match?(source, ~r/^[A-Za-z]:[\\\/]/)) and
      File.regular?(source)
  end

  @impl true
  def delete(key) do
    case File.rm(disk_path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(key), do: File.regular?(disk_path(key))

  @impl true
  def fetch(key) do
    path = disk_path(key)

    if File.regular?(path) do
      File.read(path)
    else
      {:error, :not_found}
    end
  end

  def disk_path(key), do: Path.join(Xamt.Storage.local_dir(), Path.basename(key))
end
