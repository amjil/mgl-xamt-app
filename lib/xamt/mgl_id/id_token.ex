defmodule Xamt.MglId.IdToken do
  @moduledoc """
  ID Token validation (RS256 + JWKS) for Mgl ID.
  """

  alias Xamt.MglId
  alias Xamt.MglId.{Cache, Discovery}

  @jwks_cache_key :jwks
  @jwks_ttl_ms :timer.hours(1)
  @allowed_algs ["RS256"]
  @clock_skew_seconds 60

  @doc """
  Verifies the JWT signature and required claims.

  Options:
    * `:nonce` - required expected nonce
    * `:force_jwks` - bypass JWKS cache
  """
  def verify(id_token, opts \\ []) when is_binary(id_token) do
    expected_nonce = Keyword.fetch!(opts, :nonce)
    force_jwks? = Keyword.get(opts, :force_jwks, false)

    with {:ok, header} <- peek_header(id_token),
         :ok <- validate_alg(header),
         {:ok, jwk} <- resolve_jwk(header, force_jwks?),
         {:ok, claims} <- verify_signature(id_token, jwk),
         :ok <- validate_claims(claims, expected_nonce) do
      {:ok, claims}
    else
      {:error, :unknown_kid} ->
        # One refresh retry for key rotation.
        with {:ok, header} <- peek_header(id_token),
             {:ok, jwk} <- resolve_jwk(header, true),
             {:ok, claims} <- verify_signature(id_token, jwk),
             :ok <- validate_claims(claims, expected_nonce) do
          {:ok, claims}
        else
          {:error, reason} = error ->
            emit_validation_failed(reason)
            error
        end

      {:error, reason} = error ->
        emit_validation_failed(reason)
        error
    end
  end

  defp peek_header(id_token) do
    try do
      case String.split(id_token, ".") do
        [header_b64, _payload, _sig] ->
          header =
            header_b64
            |> Base.url_decode64!(padding: false)
            |> Jason.decode!()

          {:ok, header}

        _ ->
          {:error, :invalid_jwt}
      end
    rescue
      _ -> {:error, :invalid_jwt}
    catch
      _, _ -> {:error, :invalid_jwt}
    end
  end

  defp validate_alg(%{"alg" => alg}) when alg in @allowed_algs, do: :ok
  defp validate_alg(%{"alg" => "none"}), do: {:error, :alg_none}
  defp validate_alg(%{"alg" => _}), do: {:error, :unsupported_alg}
  defp validate_alg(_), do: {:error, :missing_alg}

  defp resolve_jwk(header, force?) do
    kid = Map.get(header, "kid")

    with {:ok, jwks} <- fetch_jwks(force?),
         {:ok, jwk_map} <- find_key(jwks, kid) do
      {:ok, JOSE.JWK.from_map(jwk_map)}
    end
  end

  defp fetch_jwks(false) do
    case Cache.get(@jwks_cache_key) do
      {:ok, jwks} -> {:ok, jwks}
      :miss -> fetch_jwks(true)
    end
  end

  defp fetch_jwks(true) do
    with {:ok, uri} <- Discovery.jwks_uri(),
         {:ok, %{status: 200, body: body}} <-
           Req.get(uri, Keyword.merge([decode_body: true], MglId.req_options())),
         keys when is_list(keys) <- Map.get(body, "keys") do
      :ok = Cache.put(@jwks_cache_key, body, @jwks_ttl_ms)
      {:ok, body}
    else
      {:ok, %{status: status}} ->
        {:error, {:jwks_http_status, status}}

      nil ->
        {:error, :jwks_missing_keys}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:jwks_unexpected, other}}
    end
  end

  defp find_key(%{"keys" => keys}, kid) when is_list(keys) do
    key =
      cond do
        is_binary(kid) and kid != "" ->
          Enum.find(keys, fn k -> Map.get(k, "kid") == kid end)

        length(keys) == 1 ->
          List.first(keys)

        true ->
          nil
      end

    case key do
      nil -> {:error, :unknown_kid}
      map when is_map(map) -> {:ok, map}
    end
  end

  defp find_key(_, _), do: {:error, :jwks_missing_keys}

  defp verify_signature(id_token, jwk) do
    case JOSE.JWT.verify_strict(jwk, @allowed_algs, id_token) do
      {true, %JOSE.JWT{fields: claims}, _jws} ->
        {:ok, claims}

      {false, _, _} ->
        {:error, :invalid_signature}

      other ->
        {:error, {:verify_failed, other}}
    end
  end

  defp validate_claims(claims, expected_nonce) do
    now = System.system_time(:second)
    issuer = MglId.issuer() |> String.trim_trailing("/")
    client_id = MglId.client_id()

    with :ok <- claim_equals(claims, "iss", issuer),
         :ok <- validate_aud(claims, client_id),
         :ok <- require_sub(claims),
         :ok <- validate_exp(claims, now),
         :ok <- validate_iat(claims, now),
         :ok <- validate_nbf(claims, now),
         :ok <- claim_equals(claims, "nonce", expected_nonce) do
      :ok
    end
  end

  defp claim_equals(claims, key, expected) do
    actual = Map.get(claims, key)

    cond do
      key == "iss" and (actual == expected or actual == expected <> "/") ->
        :ok

      actual == expected ->
        :ok

      true ->
        {:error, {:claim_mismatch, key}}
    end
  end

  defp validate_aud(claims, client_id) do
    case Map.get(claims, "aud") do
      ^client_id ->
        :ok

      list when is_list(list) ->
        if client_id in list do
          validate_azp(claims, client_id, list)
        else
          {:error, {:claim_mismatch, "aud"}}
        end

      _ ->
        {:error, {:claim_mismatch, "aud"}}
    end
  end

  defp validate_azp(_claims, _client_id, [_single]), do: :ok

  defp validate_azp(claims, client_id, _multi) do
    case Map.get(claims, "azp") do
      ^client_id -> :ok
      nil -> {:error, {:missing_claim, "azp"}}
      _ -> {:error, {:claim_mismatch, "azp"}}
    end
  end

  defp require_sub(%{"sub" => sub}) when is_binary(sub) and sub != "", do: :ok
  defp require_sub(_), do: {:error, {:missing_claim, "sub"}}

  defp validate_exp(%{"exp" => exp}, now) when is_integer(exp) do
    if now <= exp + @clock_skew_seconds, do: :ok, else: {:error, :token_expired}
  end

  defp validate_exp(_, _), do: {:error, {:missing_claim, "exp"}}

  defp validate_iat(%{"iat" => iat}, now) when is_integer(iat) do
    if iat <= now + @clock_skew_seconds, do: :ok, else: {:error, :iat_in_future}
  end

  defp validate_iat(_, _), do: {:error, {:missing_claim, "iat"}}

  defp validate_nbf(%{"nbf" => nbf}, now) when is_integer(nbf) do
    if now + @clock_skew_seconds >= nbf, do: :ok, else: {:error, :token_not_yet_valid}
  end

  defp validate_nbf(_, _), do: :ok

  defp emit_validation_failed(reason) do
    :telemetry.execute(
      [:xamt, :mgl_id, :token, :validation_failed],
      %{count: 1},
      %{reason: inspect(reason)}
    )
  end
end
