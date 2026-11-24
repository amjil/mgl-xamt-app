defmodule Xamt.MglId do
  @moduledoc """
  Configuration and feature flag for Mgl ID (mgl-id) OIDC login.
  """

  @provider "mgl_id"
  @default_scopes "openid profile email"

  def provider, do: @provider

  def enabled? do
    config()[:enabled] == true
  end

  def config do
    Application.get_env(:xamt, __MODULE__, [])
  end

  def issuer do
    Keyword.fetch!(config(), :issuer)
  end

  def client_id do
    Keyword.fetch!(config(), :client_id)
  end

  def client_secret do
    Keyword.fetch!(config(), :client_secret)
  end

  def redirect_uri do
    Keyword.fetch!(config(), :redirect_uri)
  end

  def link_redirect_uri do
    Keyword.get(config(), :link_redirect_uri) ||
      redirect_uri()
      |> String.replace_suffix(
        "/auth/mgl/callback",
        "/settings/account/identities/mgl/callback"
      )
  end

  def scopes do
    config()
    |> Keyword.get(:scopes, @default_scopes)
    |> normalize_scopes()
  end

  def transaction_ttl_seconds do
    Keyword.get(config(), :transaction_ttl_seconds, 600)
  end

  @doc """
  Extra Req options (e.g. `plug: {Req.Test, ...}` in tests).
  """
  def req_options do
    Keyword.get(config(), :req_options, [])
  end

  defp normalize_scopes(scopes) when is_binary(scopes) do
    scopes
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
end
