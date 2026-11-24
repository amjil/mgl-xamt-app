defmodule Xamt.MglId.Pkce do
  @moduledoc """
  PKCE S256 helpers for Mgl ID Authorization Code flow.
  """

  @doc """
  Returns a high-entropy `code_verifier` (43–128 chars, unreserved).
  """
  def verifier do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns `BASE64URL(SHA256(verifier))` without padding.
  """
  def challenge(verifier) when is_binary(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  def challenge_method, do: "S256"
end
