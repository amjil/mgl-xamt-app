defmodule Xamt.MglId.Auth do
  @moduledoc """
  Orchestrates Mgl ID login and account-linking after a verified ID token.
  """

  require Logger

  alias Xamt.Accounts
  alias Xamt.MglId
  alias Xamt.MglId.{Client, IdToken}
  alias Xamt.SiteSettings

  @doc """
  Exchanges `code`, verifies the ID token, and resolves or provisions a user.

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
        if SiteSettings.registration_enabled?() do
          case Accounts.provision_user_from_mgl(claims) do
            {:ok, user} ->
              emit("auth.mgl.identity.created", user, claims)
              {:ok, user}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :registration_disabled}
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
