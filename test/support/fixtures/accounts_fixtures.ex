defmodule Xamt.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Xamt.Accounts` context.
  """

  import Ecto.Query

  alias Xamt.Accounts
  alias Xamt.Accounts.{Scope, User}
  alias Xamt.Repo

  def unique_user_username, do: "user#{System.unique_integer() |> abs()}"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      username: unique_user_username()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {global_role, attrs} = pop_global_role(attrs)

    # Admin changeset creates a confirmed account directly (public sign-up is gone).
    user =
      %User{}
      |> User.admin_registration_changeset(
        attrs
        |> valid_user_attributes()
        |> Map.put_new(:global_role, "user")
      )
      |> Repo.insert!()

    maybe_set_global_role(user, global_role)
  end

  def creator_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:global_role, "creator")
    |> user_fixture()
  end

  def admin_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:global_role, "admin")
    |> user_fixture()
  end

  defp pop_global_role(attrs) do
    cond do
      is_map_key(attrs, :global_role) -> Map.pop(attrs, :global_role)
      is_map_key(attrs, "global_role") -> Map.pop(attrs, "global_role")
      true -> {nil, attrs}
    end
  end

  defp maybe_set_global_role(user, role) when is_binary(role) do
    {:ok, user} = Accounts.update_user_global_role(user, role)
    user
  end

  defp maybe_set_global_role(user, _), do: user

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Xamt.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Xamt.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
