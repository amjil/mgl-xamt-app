defmodule Xamt.Servers.PermissionsTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Xamt.Servers.Permissions

  test "flags are distinct powers of two" do
    values = Permissions.flags() |> Map.values() |> Enum.sort()
    assert values == Enum.map(0..(length(values) - 1), &(1 <<< &1))
  end

  test "grant, has_permission? and revoke round-trip a single flag" do
    perms = Permissions.grant(0, :kick_members)
    assert Permissions.has_permission?(perms, :kick_members)
    refute Permissions.has_permission?(perms, :ban_members)

    perms = Permissions.revoke(perms, :kick_members)
    refute Permissions.has_permission?(perms, :kick_members)
    assert perms == 0
  end

  test "granting one flag does not disturb others" do
    perms =
      0
      |> Permissions.grant(:view_channel)
      |> Permissions.grant(:send_messages)
      |> Permissions.grant(:kick_members)
      |> Permissions.revoke(:send_messages)

    assert Enum.sort(Permissions.enabled_flags(perms)) == [:kick_members, :view_channel]
    refute Permissions.has_permission?(perms, :send_messages)
  end

  test "role presets" do
    member = Permissions.for_role("member")
    assert Permissions.has_permission?(member, :view_channel)
    assert Permissions.has_permission?(member, :send_messages)
    refute Permissions.has_permission?(member, :kick_members)

    admin = Permissions.for_role("admin")
    assert Permissions.has_permission?(admin, :manage_server)
    assert Permissions.has_permission?(admin, :kick_members)

    owner = Permissions.for_role("owner")
    assert Enum.sort(Permissions.enabled_flags(owner)) == Enum.sort(Permissions.flag_names())
  end

  test "has_any? and nil-safe checks" do
    perms = Permissions.default_member_perms()
    assert Permissions.has_any?(perms, [:kick_members, :send_messages])
    refute Permissions.has_any?(perms, [:kick_members, :ban_members])
    refute Permissions.has_permission?(nil, :view_channel)
    refute Permissions.has_any?(nil, [:view_channel])
  end
end
