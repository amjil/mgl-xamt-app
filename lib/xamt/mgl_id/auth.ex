defmodule Xamt.MglId.Auth do
  @moduledoc """
  Orchestrates Mgl ID login and account-linking after a verified ID token.
  """

  require Logger

  alias Xamt.Accounts
  alias Xamt.MglId
  alias Xamt.MglId.{Client, IdToken}

  @doc """
  Exchanges `code`, verifies the ID token, and resolves or provisions a user.

  First-time Mgl ID login provisions a local account. Mgl ID is the only
  sign-in path, so there is no separate public registration step.

  Returns `{:ok, user}` or `{:error, reason}`.
  """
  def complete_login(code, txn) when is_binary(code) and is_map(txn) do
    with {:ok, claims} <- authenticate(code, txn),
         {:ok, user} <- resolve_or_provision(claims) do
      emit("auth.mgl.login.succeeded", user, claims)
      {:ok, user}
    else
      {:error, reason} = error ->
        emit_failure("auth.mgl.login.failed", reason)
        error
    end
  end

  @doc """
  Exchanges `code`, verifies the ID token, and links identity to `user`.
  """
  def complete_link(code, txn, user) when is_binary(code) and is_map(txn) do
    expected_user_id = txn["user_id"]

    cond do
      is_nil(user) ->
        {:error, :not_authenticated}

      is_binary(expected_user_id) and expected_user_id != to_string(user.id) ->
        {:error, :session_mismatch}

      true ->
        with {:ok, claims} <- authenticate(code, txn),
             {:ok, _identity} <- Accounts.link_mgl_identity(user, claims) do
          emit("auth.mgl.identity.linked", user, claims)
          {:ok, user}
        else
          {:error, :already_linked_other_user} = error ->
            emit_failure("auth.mgl.identity.link_failed", :already_linked_other_user)
            error

          {:error, reason} = error ->
            emit_failure("auth.mgl.identity.link_failed", reason)
            error
        end
    end
  end

  @doc """
  Completes an Mgl ID–initiated product account link.

  Proves ownership of the signed-in Xamt user, confirms with mgl-id, then
  stores a local `UserIdentity` keyed by the Amjil user id (`sub`).
  """
  def complete_account_link(user, token, provider)
      when is_binary(token) and is_binary(provider) do
    cond do
      is_nil(user) ->
        {:error, :not_authenticated}

      provider != "xamt" ->
        {:error, :invalid_provider}

      Accounts.get_mgl_identity(user) ->
        {:error, :user_already_linked}

      true ->
        with {:ok, response} <- Client.confirm_account_link(token, user.id),
             {:ok, claims} <- claims_from_confirm(response),
             {:ok, _identity} <- Accounts.link_mgl_identity(user, claims) do
          emit("auth.mgl.identity.linked", user, claims)
          {:ok, user}
        else
          {:error, :already_linked_other_user} = error ->
            emit_failure("auth.mgl.identity.link_failed", :already_linked_other_user)
            error

          {:error, reason} = error ->
            emit_failure("auth.mgl.identity.link_failed", reason)
            error
        end
    end
  end

  defp claims_from_confirm(%{"data" => data}) when is_map(data) do
    subject = data["amjil_user_id"] || data["user_id"]

    preferred =
      data["preferred_username"] ||
        get_in(data, ["user", "preferred_username"]) ||
        get_in(data, ["link", "preferred_username"])

    if is_binary(subject) and subject != "" do
      claims = %{
        "sub" => subject,
        "iss" => MglId.issuer() |> String.trim_trailing("/")
      }

      claims =
        if is_binary(preferred) and preferred != "" do
          Map.put(claims, "preferred_username", preferred)
        else
          claims
        end

      {:ok, claims}
    else
      {:error, :missing_amjil_user_id}
    end
  end

  defp claims_from_confirm(_), do: {:error, :invalid_confirm_response}

  defp authenticate(code, txn) do
    with {:ok, token_response} <- Client.exchange_code(code, txn),
         id_token when is_binary(id_token) <- Map.get(token_response, "id_token"),
         {:ok, claims} <- IdToken.verify(id_token, nonce: txn["nonce"]) do
      {:ok, claims}
    else
      nil ->
        {:error, :missing_id_token}

      {:error, _} = error ->
        error
    end
  end

  defp resolve_or_provision(claims) do
    issuer = MglId.issuer() |> String.trim_trailing("/")
    subject = claims["sub"]

    case Accounts.get_user_by_mgl_identity(issuer, subject) do
      %{user: user} = _identity ->
        {:ok, user}

      nil ->
        case Accounts.provision_user_from_mgl(claims) do
          {:ok, user} ->
            emit("auth.mgl.identity.created", user, claims)
            {:ok, user}

          # Concurrent first-login / double-submit: identity was inserted by a
          # racing request — re-query so login stays idempotent.
          {:error, :identity_conflict} ->
            case Accounts.get_user_by_mgl_identity(issuer, subject) do
              %{user: user} -> {:ok, user}
              nil -> {:error, :identity_conflict}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp emit(event, user, claims) do
    Logger.info(fn ->
      "#{event} user_id=#{user.id} subject_hash=#{subject_hash(claims["sub"])}"
    end)

    :telemetry.execute(
      [:xamt, :mgl_id, :auth],
      %{count: 1},
      %{
        event: event,
        user_id: user.id,
        subject_hash: subject_hash(claims["sub"])
      }
    )
  end

  defp emit_failure(event, reason) do
    Logger.warning(fn -> "#{event} reason=#{inspect(reason)}" end)

    :telemetry.execute(
      [:xamt, :mgl_id, :auth],
      %{count: 1},
      %{event: event, reason: inspect(reason)}
    )
  end

  defp subject_hash(nil), do: nil

  defp subject_hash(sub) when is_binary(sub) do
    :crypto.hash(:sha256, sub) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end
end
