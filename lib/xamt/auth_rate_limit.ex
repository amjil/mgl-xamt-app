defmodule Xamt.AuthRateLimit do
  @moduledoc """
  Sliding-window limits for login, magic-link, register, and invite redeem.

  Reuses `Xamt.Messages.RateLimiter` ETS buckets. Keys are
  `{action, client}` so a busy chat user is not locked out of auth, and
  auth bursts do not eat the message quota.
  """

  alias Xamt.Messages.RateLimiter

  @defaults [
    login: [limit: 10, window_seconds: 60],
    magic_link: [limit: 5, window_seconds: 60],
    register: [limit: 5, window_seconds: 60],
    invite: [limit: 10, window_seconds: 60]
  ]

  def check(action, key) when is_atom(action) do
    {limit, window_seconds} = limits(action)
    RateLimiter.check_rate({action, key}, limit: limit, window_seconds: window_seconds)
  end

  def client_key(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] ->
        value |> String.split(",", parts: 2) |> hd() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> List.to_string()
    end
  end

  defp limits(action) do
    conf = Application.get_env(:xamt, __MODULE__, [])
    opts = Keyword.get(conf, action, Keyword.get(@defaults, action, []))

    {Keyword.get(opts, :limit, 10), Keyword.get(opts, :window_seconds, 60)}
  end
end
