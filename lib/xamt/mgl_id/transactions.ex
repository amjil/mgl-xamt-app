defmodule Xamt.MglId.Transactions do
  @moduledoc """
  Server-side OIDC login/link transaction helpers stored in the Plug session.

  Multiple concurrent transactions are kept so multi-tab login does not
  overwrite an earlier `state` / PKCE verifier.
  """

  @session_key :mgl_oidc_txns
  # Keep this small: each txn holds a PKCE verifier + nonce in the cookie session.
  @max_txns 4

  def session_key, do: @session_key

  def put(conn, txn) when is_map(txn) do
    txns =
      conn
      |> Plug.Conn.get_session(@session_key, [])
      |> prune_expired()
      |> Kernel.++([txn])
      |> Enum.take(-@max_txns)

    Plug.Conn.put_session(conn, @session_key, txns)
  end

  @doc """
  Pops a matching unused transaction by `state`. Marks it consumed by removal.
  """
  def take(conn, state) when is_binary(state) do
    now = DateTime.utc_now()
    txns = Plug.Conn.get_session(conn, @session_key, []) |> prune_expired(now)

    case Enum.split_with(txns, fn txn -> txn["state"] == state end) do
      {[txn | _], rest} ->
        if expired?(txn, now) do
          conn = Plug.Conn.put_session(conn, @session_key, rest)
          {conn, {:error, :expired}}
        else
          conn = Plug.Conn.put_session(conn, @session_key, rest)
          {conn, {:ok, txn}}
        end

      {[], _} ->
        {conn, {:error, :not_found}}
    end
  end

  def clear(conn) do
    Plug.Conn.delete_session(conn, @session_key)
  end

  defp prune_expired(txns, now \\ DateTime.utc_now()) do
    Enum.reject(txns, &expired?(&1, now))
  end

  defp expired?(%{"expires_at" => iso}, now) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, expires_at, _} -> DateTime.compare(now, expires_at) == :gt
      _ -> true
    end
  end

  defp expired?(_, _), do: true
end
