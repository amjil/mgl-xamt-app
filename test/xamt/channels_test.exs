defmodule Xamt.ChannelsTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Servers}
  alias Xamt.Channels.{ChannelRead, LastMessageCache}

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Reads"})
    channel = hd(Channels.list_channels(server.id))
    %{scope: scope, channel: channel, owner: owner, server: server}
  end

  test "mark_as_read inserts a watermark", %{owner: owner, channel: channel, scope: scope} do
    message = post(scope, channel, "hello")

    assert {:ok, read} =
             Channels.mark_as_read(owner.id, channel.id, message.id, message.inserted_at)

    assert read.user_id == owner.id
    assert read.channel_id == channel.id
    assert read.last_read_message_id == message.id

    assert DateTime.compare(read.last_read_at, DateTime.truncate(message.inserted_at, :second)) ==
             :eq
  end

  test "mark_as_read advances the watermark for a newer message", %{
    owner: owner,
    channel: channel,
    scope: scope
  } do
    older = stamp(post(scope, channel, "older"), ~U[2026-09-19 10:00:00Z])
    newer = stamp(post(scope, channel, "newer"), ~U[2026-09-19 10:00:01Z])

    assert {:ok, _} = Channels.mark_as_read(owner.id, channel.id, older.id, older.inserted_at)
    assert {:ok, _} = Channels.mark_as_read(owner.id, channel.id, newer.id, newer.inserted_at)

    read = Repo.get_by!(ChannelRead, user_id: owner.id, channel_id: channel.id)
    assert read.last_read_message_id == newer.id
    assert DateTime.compare(read.last_read_at, ~U[2026-09-19 10:00:01Z]) == :eq
  end

  test "mark_as_read ignores an older or duplicate watermark without raising", %{
    owner: owner,
    channel: channel,
    scope: scope
  } do
    older = stamp(post(scope, channel, "older"), ~U[2026-09-19 10:00:00Z])
    newer = stamp(post(scope, channel, "newer"), ~U[2026-09-19 10:00:01Z])

    assert {:ok, _} = Channels.mark_as_read(owner.id, channel.id, newer.id, newer.inserted_at)

    # Same message again (IntersectionObserver / reconnect) and an older one.
    assert {:ok, _} = Channels.mark_as_read(owner.id, channel.id, newer.id, newer.inserted_at)
    assert {:ok, _} = Channels.mark_as_read(owner.id, channel.id, older.id, older.inserted_at)

    read = Repo.get_by!(ChannelRead, user_id: owner.id, channel_id: channel.id)
    assert read.last_read_message_id == newer.id
    assert DateTime.compare(read.last_read_at, ~U[2026-09-19 10:00:01Z]) == :eq
  end

  defp post(scope, channel, html) do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>#{html}</p>",
        "content" => %{"type" => "rich_text", "html" => "<p>#{html}</p>"}
      })

    message
  end

  test "LastMessageCache.put keeps the newest timestamp", %{channel: channel} do
    older = ~U[2026-09-19 10:00:00Z]
    newer = ~U[2026-09-19 10:00:01Z]
    old_id = Ecto.UUID.generate()
    new_id = Ecto.UUID.generate()

    LastMessageCache.put(channel.id, new_id, newer)
    LastMessageCache.put(channel.id, old_id, older)

    assert {^new_id, ^newer} = LastMessageCache.get(channel.id)
  end

  defp stamp(message, inserted_at) do
    message
    |> Ecto.Changeset.change(inserted_at: inserted_at, updated_at: inserted_at)
    |> Repo.update!()
  end
end
