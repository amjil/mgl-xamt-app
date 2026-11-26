defmodule Xamt.Accounts.MglIdentityTest do
  use Xamt.DataCase, async: true

  alias Xamt.Accounts
  alias Xamt.MglId
  alias Xamt.MglIdHelpers
  import Xamt.AccountsFixtures

  test "provisions a new user and identity from claims" do
    claims = MglIdHelpers.default_claims()

    assert {:ok, user} = Accounts.provision_user_from_mgl(claims)
    assert user.display_name == claims["name"]
    assert user.confirmed_at

    identity = Accounts.get_mgl_identity(user)
    assert identity.provider == MglId.provider()
    assert identity.subject == claims["sub"]
    assert identity.issuer == String.trim_trailing(MglId.issuer(), "/")
  end

  test "looks up user by issuer and subject" do
    claims = MglIdHelpers.default_claims()
    {:ok, user} = Accounts.provision_user_from_mgl(claims)

    found =
      Accounts.get_user_by_mgl_identity(
        MglId.issuer(),
        claims["sub"]
      )

    assert found.user.id == user.id
  end

  test "does not merge by username when provisioning" do
    existing = user_fixture(%{username: "taken_name"})

    claims =
      MglIdHelpers.default_claims(%{
        "preferred_username" => "taken_name"
      })

    assert {:ok, user} = Accounts.provision_user_from_mgl(claims)
    assert user.id != existing.id
    assert user.username != existing.username
    assert is_nil(Accounts.get_mgl_identity(existing))
  end

  test "links identity to an existing user" do
    user = user_fixture()
    claims = MglIdHelpers.default_claims()

    assert {:ok, identity} = Accounts.link_mgl_identity(user, claims)
    assert identity.user_id == user.id

    # Idempotent
    assert {:ok, again} = Accounts.link_mgl_identity(user, claims)
    assert again.id == identity.id
  end

  test "rejects linking an identity already used by another user" do
    user_a = user_fixture()
    user_b = user_fixture()
    claims = MglIdHelpers.default_claims()

    assert {:ok, _} = Accounts.link_mgl_identity(user_a, claims)

    assert {:error, :already_linked_other_user} =
             Accounts.link_mgl_identity(user_b, claims)
  end

  test "rejects second mgl identity on same user" do
    user = user_fixture()
    claims_a = MglIdHelpers.default_claims()
    claims_b = MglIdHelpers.default_claims()

    assert {:ok, _} = Accounts.link_mgl_identity(user, claims_a)
    assert {:error, :user_already_linked} = Accounts.link_mgl_identity(user, claims_b)
  end

  test "provisions without an email claim" do
    claims =
      MglIdHelpers.default_claims(%{
        "sub" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "preferred_username" => "NoMailUser"
      })
      |> Map.delete("email")

    assert {:ok, user} = Accounts.provision_user_from_mgl(claims)
    assert user.username == "NoMailUser"
    assert Accounts.get_mgl_identity(user)
  end
end
