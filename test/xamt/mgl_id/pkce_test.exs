defmodule Xamt.MglId.PkceTest do
  use ExUnit.Case, async: true

  alias Xamt.MglId.Pkce

  test "verifier is url-safe and long enough" do
    verifier = Pkce.verifier()
    assert byte_size(verifier) >= 43
    assert verifier =~ ~r/^[A-Za-z0-9_-]+$/
  end

  test "challenge is S256 base64url without padding" do
    verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    # Example from RFC 7636 appendix B
    assert Pkce.challenge(verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    assert Pkce.challenge_method() == "S256"
  end
end
