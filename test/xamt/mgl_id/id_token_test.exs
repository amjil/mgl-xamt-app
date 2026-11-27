defmodule Xamt.MglId.IdTokenTest do
  use ExUnit.Case, async: false

  alias Xamt.MglId.IdToken
  alias Xamt.MglIdHelpers

  setup do
    MglIdHelpers.clear_cache!()
    MglIdHelpers.put_discovery!()
    jwk = MglIdHelpers.rsa_keypair!()
    jwks = MglIdHelpers.jwks_for(jwk)
    MglIdHelpers.put_jwks!(jwks)
    {:ok, jwk: jwk}
  end

  test "accepts a valid RS256 id token", %{jwk: jwk} do
    claims = MglIdHelpers.default_claims(%{"nonce" => "abc"})
    token = MglIdHelpers.sign_id_token(jwk, claims)

    assert {:ok, verified} = IdToken.verify(token, nonce: "abc")
    assert verified["sub"] == claims["sub"]
  end

  test "rejects wrong nonce", %{jwk: jwk} do
    claims = MglIdHelpers.default_claims(%{"nonce" => "abc"})
    token = MglIdHelpers.sign_id_token(jwk, claims)

    assert {:error, {:claim_mismatch, "nonce"}} =
             IdToken.verify(token, nonce: "other")
  end

  test "rejects missing expected nonce", %{jwk: jwk} do
    claims = MglIdHelpers.default_claims() |> Map.delete("nonce")
    token = MglIdHelpers.sign_id_token(jwk, claims)

    assert {:error, :missing_expected_nonce} = IdToken.verify(token, nonce: nil)
    assert {:error, :missing_expected_nonce} = IdToken.verify(token, nonce: "")
  end

  test "rejects expired token", %{jwk: jwk} do
    now = System.system_time(:second)

    claims =
      MglIdHelpers.default_claims(%{
        "nonce" => "abc",
        "exp" => now - 120,
        "iat" => now - 200
      })

    token = MglIdHelpers.sign_id_token(jwk, claims)
    assert {:error, :token_expired} = IdToken.verify(token, nonce: "abc")
  end

  test "rejects wrong audience", %{jwk: jwk} do
    claims = MglIdHelpers.default_claims(%{"nonce" => "abc", "aud" => "other-client"})
    token = MglIdHelpers.sign_id_token(jwk, claims)

    assert {:error, {:claim_mismatch, "aud"}} =
             IdToken.verify(token, nonce: "abc")
  end

  test "rejects wrong issuer", %{jwk: jwk} do
    claims = MglIdHelpers.default_claims(%{"nonce" => "abc", "iss" => "https://evil.example"})
    token = MglIdHelpers.sign_id_token(jwk, claims)

    assert {:error, {:claim_mismatch, "iss"}} =
             IdToken.verify(token, nonce: "abc")
  end

  test "rejects invalid signature", %{jwk: jwk} do
    other = MglIdHelpers.rsa_keypair!()
    claims = MglIdHelpers.default_claims(%{"nonce" => "abc"})
    token = MglIdHelpers.sign_id_token(other, claims)
    # JWKS still has `jwk`, not `other`
    _ = jwk

    assert {:error, :invalid_signature} = IdToken.verify(token, nonce: "abc")
  end
end
