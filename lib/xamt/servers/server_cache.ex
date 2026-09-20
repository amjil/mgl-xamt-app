defmodule Xamt.Servers.ServerCache do
  @moduledoc """
  ETS-backed cache of server configuration keyed by id and slug.

  Hot reconnect paths (`get_server_by_slug!`) read here instead of Postgres.
  Associations like members are not cached — those change too often.
  """

  use GenServer

  alias Xamt.Repo
  alias Xamt.Servers.Server

  @table :xamt_server_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ref ->
        @table
    end

    send(self(), :load_initial_data)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load_initial_data, state) do
    if Application.get_env(:xamt, :ets_cache_warmup, true) do
      Enum.each(Repo.all(Server), &put/1)
    end

    {:noreply, state}
  end

  @doc "Stores a server under both id and slug keys."
  def put(%Server{} = server, opts \\ []) do
    case Keyword.get(opts, :old_slug) do
      slug when is_binary(slug) and slug != server.slug ->
        :ets.delete(@table, {:slug, slug})

      _ ->
        :ok
    end

    cached = strip(server)
    :ets.insert(@table, {{:id, cached.id}, cached})
    :ets.insert(@table, {{:slug, cached.slug}, cached.id})
    server
  end

  @doc "Removes a server from the cache."
  def delete(%Server{id: id, slug: slug}) do
    delete(id, slug)
  end

  def delete(server_id, slug) when is_binary(server_id) and is_binary(slug) do
    :ets.delete(@table, {:id, server_id})
    :ets.delete(@table, {:slug, slug})
    :ok
  end

  @doc "Returns the cached server for `id`, or `nil`."
  def get(server_id) when is_binary(server_id) do
    case :ets.lookup(@table, {:id, server_id}) do
      [{{:id, ^server_id}, server}] -> server
      [] -> nil
    end
  end

  @doc "Returns the cached server for `slug`, or `nil`."
  def get_by_slug(slug) when is_binary(slug) do
    case :ets.lookup(@table, {:slug, slug}) do
      [{{:slug, ^slug}, server_id}] -> get(server_id)
      [] -> nil
    end
  end

  @doc false
  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp strip(%Server{} = server) do
    %Server{
      id: server.id,
      name: server.name,
      slug: server.slug,
      description: server.description,
      icon: server.icon,
      visibility: server.visibility,
      owner_id: server.owner_id,
      inserted_at: server.inserted_at,
      updated_at: server.updated_at
    }
  end
end
