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

  @doc """
  Product-side receiver for Mgl ID → Xamt account-link initiations.
  """
  def account_link_path, do: "/account/link"

  def account_link_confirm_url do
    issuer()
    |> String.trim_trailing("/")
    |> Kernel.<>("/api/v1/account-links/confirm")
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
  Default Req options merged with config overrides
  (e.g. `plug: {Req.Test, ...}` in tests).

  Timeouts and `retry: false` prevent a flaky IdP from blocking a login
  callback for the Req default of ~45s (3 retries × 15s).
  """
  def req_options do
    defaults = [
      receive_timeout: 5_000,
      connect_options: [timeout: 3_000],
      retry: false,
      redirect: false
    ]

    Keyword.merge(defaults, Keyword.get(config(), :req_options, []))
  end

  defp normalize_scopes(scopes) when is_binary(scopes) do
    scopes
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
end
