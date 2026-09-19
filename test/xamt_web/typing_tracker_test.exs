defmodule XamtWeb.TypingTrackerTest do
  use ExUnit.Case, async: false

  alias XamtWeb.TypingTracker

  test "handle_diff packs joins and leaves into one local broadcast" do
    topic = "typing:channel:#{Ecto.UUID.generate()}"
    Phoenix.PubSub.subscribe(Xamt.PubSub, topic)

    {:ok, state} = TypingTracker.init(pubsub_server: Xamt.PubSub)
    joins = [{"u1", %{username: "ada"}}, {"u2", %{username: "bob"}}]
    leaves = [{"u3", %{username: "cyd"}}]

    assert {:ok, ^state} = TypingTracker.handle_diff(%{topic => {joins, leaves}}, state)
    assert_receive {:typing_diff, ^topic, ^joins, ^leaves}, 500
    refute_receive {:typing_diff, _, _, _}
  end

  test "track_user is idempotent for the same pid and key" do
    channel = %{id: Ecto.UUID.generate()}
    user = %{id: Ecto.UUID.generate(), username: "ada", display_name: "Ada"}

    assert :ok = TypingTracker.track_user(self(), channel, user)
    assert :ok = TypingTracker.track_user(self(), channel, user)
    assert [{id, meta}] = TypingTracker.list(channel)
    assert id == user.id
    assert meta.username == "ada"
    assert meta.display_name == "Ada"

    assert :ok = TypingTracker.untrack_user(self(), channel, user)
    assert [] = TypingTracker.list(channel)
  end

  test "untrack on process exit drops the typist" do
    channel = %{id: Ecto.UUID.generate()}
    user = %{id: Ecto.UUID.generate(), username: "ghost", display_name: "Ghost"}
    topic = TypingTracker.topic(channel)
    parent = self()

    Phoenix.PubSub.subscribe(Xamt.PubSub, topic)

    pid =
      start_supervised!(%{
        id: :ghost_typist,
        start:
          {Task, :start_link,
           [
             fn ->
               :ok = TypingTracker.track_user(self(), channel, user)
               send(parent, :tracked)
               Process.sleep(:infinity)
             end
           ]},
        restart: :temporary
      })

    assert_receive :tracked
    assert [{id, _meta}] = TypingTracker.list(channel)
    assert id == user.id
    assert_receive {:typing_diff, ^topic, _joins, _leaves}, 500

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert_receive {:typing_diff, ^topic, _joins, leaves}, 500
    assert Enum.any?(leaves, fn {id, _meta} -> id == user.id end)
    assert [] = TypingTracker.list(channel)
  end
end
