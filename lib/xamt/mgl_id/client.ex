defmodule Xamt.MglId.Client do
  @moduledoc """
  OIDC Authorization Code + PKCE client for Mgl ID.
  """

  alias Xamt.MglId
  alias Xamt.MglId.{Discovery, Pkce}

  @doc """
  Builds the Mgl ID authorization URL and returns `{url, transaction_attrs}`.
  """
  def authorize_url(opts \\ []) do
    purpose = Keyword.get(opts, :purpose, "login")
    redirect_uri = Keyword.get(opts, :redirect_uri, MglId.redirect_uri())
    user_id = Keyword.get(opts, :user_id)

    state = random_token()
    nonce = random_token()
    verifier = Pkce.verifier()
    challenge = Pkce.challenge(verifier)

    with {:ok, endpoint} <- Discovery.authorization_endpoint() do
      query =
        URI.encode_query(%{
          "response_type" => "code",
          "client_id" => MglId.client_id(),
          "redirect_uri" => redirect_uri,
          "scope" => Enum.join(MglId.scopes(), " "),
          "state" => state,
          "nonce" => nonce,
          "code_challenge" => challenge,
          "code_challenge_method" => Pkce.challenge_method()
        })

      txn = %{
        "state" => state,
        "nonce" => nonce,
        "code_verifier" => verifier,
        "redirect_uri" => redirect_uri,
        "purpose" => to_string(purpose),
        "user_id" => user_id && to_string(user_id),
        "expires_at" =>
          DateTime.utc_now()
          |> DateTime.add(MglId.transaction_ttl_seconds(), :second)
          |> DateTime.to_iso8601()
      }

      {:ok, endpoint <> "?" <> query, txn}
    end
  end

  @doc """
  Exchanges an authorization code for tokens. Returns the decoded JSON body.
  """
  def exchange_code(code, txn) when is_binary(code) and is_map(txn) do
    with {:ok, endpoint} <- Discovery.token_endpoint() do
      body = %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => txn["redirect_uri"],
        "client_id" => MglId.client_id(),
        "client_secret" => MglId.client_secret(),
        "code_verifier" => txn["code_verifier"]
      }

      opts =
        Keyword.merge(
          [form: body, headers: [{"accept", "application/json"}]],
          MglId.req_options()
        )

      case Req.post(endpoint, opts) do
        {:ok, %{status: 200, body: response}} when is_map(response) ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          {:error, {:token_endpoint, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Confirms an Mgl ID → product account-link initiation with client credentials.

  Body fields match `POST /api/v1/account-links/confirm` on mgl-id.
  """
  def confirm_account_link(initiation_token, external_user_id)
      when is_binary(initiation_token) do
    url = MglId.account_link_confirm_url()

    body = %{
      "initiation_token" => initiation_token,
      "external_user_id" => to_string(external_user_id),
      "external_account_status" => "active",
      "client_id" => MglId.client_id(),
      "client_secret" => MglId.client_secret()
    }

    opts =
      Keyword.merge(
        [
          json: body,
          headers: [{"accept", "application/json"}]
        ],
        MglId.req_options()
      )

    case Req.post(url, opts) do
      {:ok, %{status: 200, body: response}} when is_map(response) ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, {:account_link_confirm, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp random_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
end
