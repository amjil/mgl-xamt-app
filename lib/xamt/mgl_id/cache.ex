defmodule Xamt.MglId.Cache do
  @moduledoc false
  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def get(key) do
    GenServer.call(@name, {:get, key})
  end

  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    GenServer.call(@name, {:put, key, value, ttl_ms})
  end

  def delete(key) do
    GenServer.call(@name, {:delete, key})
  end

  def clear do
    GenServer.call(@name, :clear)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state, key) do
      {value, expires_at} when expires_at > now ->
        {:reply, {:ok, value}, state}

      {_value, _expired} ->
        {:reply, :miss, Map.delete(state, key)}

      nil ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:put, key, value, ttl_ms}, _from, state) do
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    {:reply, :ok, Map.put(state, key, {value, expires_at})}
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end
end
