defmodule Xamt.MglId.Discovery do
  @moduledoc """
  OpenID Connect Discovery for Mgl ID.
  """

  alias Xamt.MglId
  alias Xamt.MglId.Cache

  @cache_key :discovery
  @cache_ttl_ms :timer.hours(1)

  @required_keys ~w(
    issuer
    authorization_endpoint
    token_endpoint
    jwks_uri
  )

  def fetch(opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    if force? do
      refresh()
    else
      case Cache.get(@cache_key) do
        {:ok, doc} -> {:ok, doc}
        :miss -> refresh()
      end
    end
  end

  def authorization_endpoint(opts \\ []) do
    with {:ok, doc} <- fetch(opts), do: {:ok, doc["authorization_endpoint"]}
  end

  def token_endpoint(opts \\ []) do
    with {:ok, doc} <- fetch(opts), do: {:ok, doc["token_endpoint"]}
  end

  def jwks_uri(opts \\ []) do
    with {:ok, doc} <- fetch(opts), do: {:ok, doc["jwks_uri"]}
  end

  defp refresh do
    issuer = MglId.issuer() |> String.trim_trailing("/")
    url = issuer <> "/.well-known/openid-configuration"

    case Req.get(url, Keyword.merge([decode_body: true], MglId.req_options())) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        case validate(body, issuer) do
          :ok ->
            :ok = Cache.put(@cache_key, body, @cache_ttl_ms)
            :telemetry.execute([:xamt, :mgl_id, :discovery, :success], %{count: 1}, %{})
            {:ok, body}

          {:error, reason} = error ->
            emit_failure(reason)
            error
        end

      {:ok, %{status: status}} ->
        emit_failure({:http_status, status})
        {:error, {:http_status, status}}

      {:error, reason} ->
        emit_failure(reason)
        {:error, reason}
    end
  end

  defp validate(doc, expected_issuer) do
    missing = Enum.reject(@required_keys, &Map.has_key?(doc, &1))

    cond do
      missing != [] ->
        {:error, {:missing_keys, missing}}

      doc["issuer"] != expected_issuer and doc["issuer"] != expected_issuer <> "/" ->
        {:error, {:issuer_mismatch, doc["issuer"]}}

      true ->
        :ok
    end
  end

  defp emit_failure(reason) do
    :telemetry.execute(
      [:xamt, :mgl_id, :discovery, :failed],
      %{count: 1},
      %{reason: inspect(reason)}
    )
  end
end
