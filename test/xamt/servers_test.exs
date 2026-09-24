defmodule Xamt.ServersTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Servers}
  alias Xamt.Servers.{Permissions, Server}

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    member = Xamt.AccountsFixtures.user_fixture()
    outsider = Xamt.AccountsFixtures.user_fixture()
    owner_scope = Scope.for_user(owner)

    {:ok, server} =
      Servers.create_server(owner_scope, %{"name" => "Closed", "visibility" => "private"})

    %{
      owner: owner,
      owner_scope: owner_scope,
      member: member,
      member_scope: Scope.for_user(member),
      outsider: outsider,
      outsider_scope: Scope.for_user(outsider),
      server: server
    }
  end

  test "create_server honours visibility", %{owner_scope: scope} do
    {:ok, server} = Servers.create_server(scope, %{"name" => "Open", "visibility" => "public"})
    assert Server.public?(server)
  end

  test "create_server uses a provided slug", %{owner_scope: scope} do
    mongolian_name = "\u1830\u1820\u1837\u1820\u1828"

    {:ok, server} =
      Servers.create_server(scope, %{"name" => mongolian_name, "slug" => "Saran Hall!"})

    assert server.name == mongolian_name
    assert server.slug == "saran-hall"
  end

  test "create_server falls back to untitled for a Mongolian name without a slug", %{
    owner_scope: scope
  } do
    {:ok, server} = Servers.create_server(scope, %{"name" => "\u1830\u1820\u1837\u1820\u1828"})
    assert server.slug == "untitled"
  end

  test "only admins can create an invite", %{
    owner_scope: owner_scope,
    outsider_scope: outsider_scope,
    server: server
  } do
    assert {:ok, invite} = Servers.create_invite(owner_scope, server.id)
    assert invite.code
    assert {:error, :unauthorized} = Servers.create_invite(outsider_scope, server.id)
  end

  test "redeem_invite joins the server", %{
    owner_scope: owner_scope,
    outsider_scope: outsider_scope,
    server: server
  } do
    {:ok, invite} = Servers.create_invite(owner_scope, server.id)
    assert {:ok, joined} = Servers.redeem_invite(outsider_scope, invite.code)
    assert joined.id == server.id
    assert Servers.member?(server.id, outsider_scope.user.id)
  end

  test "kick_member refuses to kick the owner", %{
    owner_scope: owner_scope,
    owner: owner,
    server: server
  } do
    assert {:error, :unauthorized} = Servers.kick_member(owner_scope, server.id, owner.id)
  end

  test "admins can kick a member", %{
    owner_scope: owner_scope,
    member_scope: member_scope,
    member: member,
    server: server
  } do
    {:ok, _} = Servers.join_server(member_scope, server.id)
    assert {:ok, _} = Servers.kick_member(owner_scope, server.id, member.id)
    refute Servers.member?(server.id, member.id)
  end

  test "non-admins cannot create a channel", %{member_scope: member_scope, server: server} do
    {:ok, _} = Servers.join_server(member_scope, server.id)

    assert {:error, :unauthorized} =
             Channels.create_channel(member_scope, server, %{"name" => "secret"})
  end

  test "admins can create, rename and delete a channel", %{owner_scope: scope, server: server} do
    assert {:ok, channel} = Channels.create_channel(scope, server, %{"name" => "extra"})
    assert {:ok, renamed} = Channels.update_channel(scope, channel.id, %{"name" => "renamed"})
    assert renamed.name == "renamed"
    assert {:ok, _} = Channels.delete_channel(scope, renamed.id)
  end

  test "Mongolian channel names get unique untitled slugs", %{owner_scope: scope, server: server} do
    assert {:ok, first} = Channels.create_channel(scope, server, %{"name" => "ᠮᠣᠩᠭᠣᠯ"})
    assert {:ok, second} = Channels.create_channel(scope, server, %{"name" => "ᠪᠢᠴᠢᠭ"})
    assert first.slug == "untitled"
    assert second.slug == "untitled-1"
    assert first.name == "ᠮᠣᠩᠭᠣᠯ"
    assert second.name == "ᠪᠢᠴᠢᠭ"
  end

  test "creating a channel named general does not collide with the default", %{
    owner_scope: scope,
    server: server
  } do
    assert {:ok, extra} = Channels.create_channel(scope, server, %{"name" => "general"})
    assert extra.slug == "general-1"
  end

  test "cannot delete the last channel", %{owner_scope: scope, server: server} do
    [only] = Channels.list_channels(server.id)
    assert {:error, :last_channel} = Channels.delete_channel(scope, only.id)
  end

  test "search_members matches username and display name", %{
    owner_scope: owner_scope,
    server: server
  } do
    username = "alice#{System.unique_integer() |> abs()}"

    target =
      Xamt.AccountsFixtures.user_fixture(%{username: username, display_name: "MentionTarget"})

    {:ok, _} = Servers.join_server(Scope.for_user(target), server.id)

    by_username = Servers.search_members(server.id, username)
    assert Enum.any?(by_username, &(&1.user_id == target.id))

    by_name = Servers.search_members(server.id, "MentionTarget")
    assert Enum.any?(by_name, &(&1.user_id == target.id))

    empty = Servers.search_members(server.id, "")
    assert length(empty) >= 1
    assert hd(empty).user_id == owner_scope.user.id

    assert Servers.search_members(server.id, "no-such-member") == []
  end

  test "list_servers_for_user includes the viewer's permission bitmask", %{
    owner_scope: owner_scope,
    member_scope: member_scope,
    server: server
  } do
    {:ok, _} = Servers.join_server(member_scope, server.id)

    [owned] = Servers.list_servers_for_user(owner_scope)
    assert owned.id == server.id
    assert owned.viewer_permissions == Permissions.owner_perms()

    [joined] = Servers.list_servers_for_user(member_scope)
    assert joined.id == server.id
    assert joined.viewer_permissions == Permissions.default_member_perms()
  end

  test "create_server and join_server stamp role permission presets", %{
    owner_scope: owner_scope,
    member_scope: member_scope,
    server: server
  } do
    owner_member = Servers.get_member(server.id, owner_scope.user.id)
    assert owner_member.permissions == Permissions.owner_perms()

    {:ok, joined} = Servers.join_server(member_scope, server.id)
    assert joined.role == "member"
    assert joined.permissions == Permissions.default_member_perms()
  end

  test "change_role rewrites the bitmask from the role preset", %{
    owner_scope: owner_scope,
    member_scope: member_scope,
    member: member,
    server: server
  } do
    {:ok, _} = Servers.join_server(member_scope, server.id)

    {:ok, promoted} = Servers.change_role(owner_scope, server.id, member.id, "admin")
    assert promoted.role == "admin"
    assert promoted.permissions == Permissions.admin_perms()

    {:ok, demoted} = Servers.change_role(owner_scope, server.id, member.id, "member")
    assert demoted.permissions == Permissions.default_member_perms()
  end

  test "a member granted kick_members can kick, and shows up as a moderator", %{
    owner_scope: owner_scope,
    member_scope: member_scope,
    member: member,
    server: server
  } do
    {:ok, _} = Servers.join_server(member_scope, server.id)

    assert {:error, :unauthorized} =
             Servers.kick_member(member_scope, server.id, owner_scope.user.id)

    {:ok, _} = Servers.grant_permission(owner_scope, server.id, member.id, :kick_members)
    assert Servers.can?(server.id, member.id, :kick_members)

    target = Xamt.AccountsFixtures.user_fixture()
    {:ok, _} = Servers.join_server(Scope.for_user(target), server.id)

    assert {:ok, _} = Servers.kick_member(member_scope, server.id, target.id)
    refute Servers.member?(server.id, target.id)

    moderators = Servers.list_moderators(server.id)
    assert Enum.any?(moderators, &(&1.user_id == member.id))
    assert Enum.any?(moderators, &(&1.user_id == owner_scope.user.id))
  end

  test "regular users cannot create a server" do
    scope = Scope.for_user(Xamt.AccountsFixtures.user_fixture())

    assert {:error, :unauthorized} =
             Servers.create_server(scope, %{"name" => "Forbidden Hall"})
  end

  test "admins can create a server" do
    scope = Scope.for_user(Xamt.AccountsFixtures.admin_fixture())
    assert {:ok, server} = Servers.create_server(scope, %{"name" => "Admin Hall"})
    assert server.name == "Admin Hall"
  end
end
