defmodule Xamt.MglIdHelpers do
  @moduledoc false

  alias Xamt.MglId
  alias Xamt.MglId.Cache

  def rsa_keypair! do
    JOSE.JWK.generate_key({:rsa, 2048})
  end

  def jwks_for(jwk, kid \\ "test-key-1") do
    {_kty, public_map} = JOSE.JWK.to_public_map(jwk)
    %{"keys" => [Map.put(public_map, "kid", kid)]}
  end

  def sign_id_token(jwk, claims, kid \\ "test-key-1") do
    jwk = JOSE.JWK.merge(jwk, %{"kid" => kid})
    alg = %{"alg" => "RS256", "kid" => kid}

    jwk
    |> JOSE.JWT.sign(alg, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  def default_claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => MglId.issuer(),
        "aud" => MglId.client_id(),
        "sub" => Ecto.UUID.generate(),
        "exp" => now + 600,
        "iat" => now,
        "nonce" => "test-nonce",
        "preferred_username" => "mgluser",
        "name" => "Mgl User",
        "email" => "mgl#{System.unique_integer([:positive])}@example.com",
        "email_verified" => true
      },
      overrides
    )
  end

  def put_discovery!(doc \\ nil) do
    issuer = MglId.issuer() |> String.trim_trailing("/")

    doc =
      doc ||
        %{
          "issuer" => issuer,
          "authorization_endpoint" => issuer <> "/oauth/authorize",
          "token_endpoint" => issuer <> "/oauth/token",
          "jwks_uri" => issuer <> "/.well-known/jwks.json",
          "userinfo_endpoint" => issuer <> "/oauth/userinfo",
          "response_types_supported" => ["code"],
          "code_challenge_methods_supported" => ["S256"]
        }

    :ok = Cache.put(:discovery, doc, :timer.hours(1))
    doc
  end

  def put_jwks!(jwks) do
    :ok = Cache.put(:jwks, jwks, :timer.hours(1))
    jwks
  end

  def clear_cache! do
    Cache.clear()
  end
end
