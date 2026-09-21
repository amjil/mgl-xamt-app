defmodule Xamt.CommunityCacheTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Servers}
  alias Xamt.Channels.ChannelListCache
  alias Xamt.Servers.ServerCache

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Cached Hall"})
    %{scope: scope, server: server}
  end

  test "get_server_by_slug! populates and reuses ServerCache", %{server: server} do
    ServerCache.reset()
    assert ServerCache.get_by_slug(server.slug) == nil

    loaded = Servers.get_server_by_slug!(server.slug)
    assert loaded.id == server.id
    assert ServerCache.get_by_slug(server.slug).id == server.id

    # Second call is served from ETS (same id/slug still present).
    assert Servers.get_server_by_slug!(server.slug).slug == server.slug
  end

  test "list_channels and unread helpers reuse the channel list cache", %{
    scope: scope,
    server: server
  } do
    ChannelListCache.reset()
    assert ChannelListCache.get(server.id) == nil

    [general] = Channels.list_channels(server.id)
    assert length(ChannelListCache.get(server.id)) == 1

    assert {:ok, extra} = Channels.create_channel(scope, server, %{"name" => "lounge"})
    # Writes invalidate; next list reloads and repopulates.
    assert ChannelListCache.get(server.id) == nil

    channels = Channels.list_channels_with_unread_status(server.id, scope.user.id)
    assert Enum.map(channels, & &1.id) == Enum.map(Channels.list_channels(server.id), & &1.id)
    assert Enum.any?(channels, &(&1.id == extra.id))
    assert Enum.any?(channels, &(&1.id == general.id))
    assert Enum.all?(channels, &(&1.has_unread == false))
  end

  test "update_server refreshes slug keys in the cache", %{scope: scope, server: server} do
    _ = Servers.get_server_by_slug!(server.slug)
    old_slug = server.slug

    assert {:ok, updated} =
             Servers.update_server(scope, server.id, %{
               "name" => "Renamed",
               "slug" => "renamed-hall"
             })

    assert ServerCache.get_by_slug(old_slug) == nil
    assert ServerCache.get_by_slug(updated.slug).id == updated.id
    assert Servers.get_server_by_slug!("renamed-hall").name == "Renamed"
  end
end
