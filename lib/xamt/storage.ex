defmodule Xamt.Storage do
  @moduledoc """
  Object storage for user uploads.

  Adapters:
  - `Xamt.Storage.Local` — disk under `priv/uploads` (tests / fallback)
  - `Xamt.Storage.S3` — S3-compatible API (SeaweedFS)

  Keys are bare filenames (`uuid.ext`). Public URLs remain `/uploads/:filename`;
  authorization stays in `Xamt.Uploads` / `UploadController`.
  """

  @type key :: String.t()

  @callback put(key, Path.t() | binary(), keyword()) :: :ok | {:error, term()}
  @callback delete(key) :: :ok | {:error, term()}
  @callback exists?(key) :: boolean()
  @callback fetch(key) :: {:ok, binary()} | {:error, :not_found | term()}

  def put(key, data, opts \\ []) when is_binary(key) do
    adapter().put(key, data, opts)
  end

  def delete(key) when is_binary(key), do: adapter().delete(key)

  def exists?(key) when is_binary(key), do: adapter().exists?(key)

  def fetch(key) when is_binary(key), do: adapter().fetch(key)

  @doc """
  Absolute directory used by the local adapter (tests / migration source).
  """
  def local_dir do
    Application.get_env(:xamt, __MODULE__, [])
    |> Keyword.get(:local_dir, Path.join(:code.priv_dir(:xamt), "uploads"))
  end

  defp adapter do
    Application.get_env(:xamt, __MODULE__, [])
    |> Keyword.get(:adapter, Xamt.Storage.Local)
  end
end
