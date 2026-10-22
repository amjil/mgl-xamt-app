defmodule Xamt.StorageTest do
  use ExUnit.Case, async: false

  alias Xamt.Storage

  setup do
    assert Keyword.get(Application.get_env(:xamt, Storage, []), :adapter, Storage.Local) ==
             Storage.Local

    :ok
  end

  test "local put/fetch/exists?/delete round-trip" do
    key = "storage-#{System.unique_integer([:positive])}.txt"
    assert :ok = Storage.put(key, "payload")
    assert Storage.exists?(key)
    assert {:ok, "payload"} = Storage.fetch(key)
    assert :ok = Storage.delete(key)
    refute Storage.exists?(key)
    assert {:error, :not_found} = Storage.fetch(key)
  end

  test "local put accepts a file path" do
    key = "storage-file-#{System.unique_integer([:positive])}.txt"
    tmp = Path.join(System.tmp_dir!(), key)
    File.write!(tmp, "from-disk")

    assert :ok = Storage.put(key, tmp)
    assert {:ok, "from-disk"} = Storage.fetch(key)
    assert :ok = Storage.delete(key)
    File.rm(tmp)
  end
end
