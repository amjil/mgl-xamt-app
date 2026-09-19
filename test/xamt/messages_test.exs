defmodule Xamt.MessagesTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Servers}
  alias Xamt.Messages.{RateLimiter, Reaction}

  setup do
    owner = Xamt.AccountsFixtures.user_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Test"})
    channel = hd(Channels.list_channels(server.id))
    %{scope: scope, channel: channel, owner: owner, server: server}
  end

  test "stores a reply_to_id and preloads the parent", %{scope: scope, channel: channel} do
    {:ok, parent} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>parent</p>",
        "content" => %{"type" => "rich_text", "html" => "<p>parent</p>"}
      })

    {:ok, reply} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>child</p>",
        "content" => %{"type" => "rich_text", "html" => "<p>child</p>"},
        "reply_to_id" => parent.id
      })

    loaded = Messages.get_message!(reply.id)
    assert loaded.reply_to_id == parent.id
    assert loaded.reply_to.id == parent.id
    assert Ecto.assoc_loaded?(loaded.user)
    assert Ecto.assoc_loaded?(loaded.reply_to.user)
    assert loaded.reply_to.user.id == parent.user_id

    # Broadcast payload must already include the nested author — LiveView
    # renders "replied to @someone" from `message.reply_to.user`.
    assert Ecto.assoc_loaded?(reply.user)
    assert Ecto.assoc_loaded?(reply.reply_to)
    assert Ecto.assoc_loaded?(reply.reply_to.user)
    assert reply.reply_to.user.id == parent.user_id
  end

  test "list_messages join-preloads authors and quoted authors without N+1", %{
    scope: scope,
    channel: channel,
    server: server,
    owner: owner
  } do
    parent_author =
      Xamt.AccountsFixtures.user_fixture(%{
        username: "quoted#{System.unique_integer() |> abs()}"
      })

    {:ok, _} = Servers.join_server(Scope.for_user(parent_author), server.id)

    {:ok, parent} =
      Messages.create_message(Scope.for_user(parent_author), channel.id, %{
        "content_html" => "<p>parent</p>",
        "content" => %{"type" => "rich_text"}
      })

    for i <- 1..5 do
      {:ok, _} =
        Messages.create_message(scope, channel.id, %{
          "content_html" => "<p>reply #{i}</p>",
          "content" => %{"type" => "rich_text"},
          "reply_to_id" => parent.id
        })
    end

    {messages, query_count} = with_query_count(fn -> Messages.list_messages(channel.id) end)

    assert length(messages) == 6

    root = Enum.find(messages, &(&1.id == parent.id))
    assert Ecto.assoc_loaded?(root.user)
    assert root.user.id == parent_author.id
    assert is_nil(root.reply_to)
    assert Ecto.assoc_loaded?(root.mentions)

    replies = Enum.filter(messages, &(&1.reply_to_id == parent.id))
    assert length(replies) == 5

    Enum.each(replies, fn reply ->
      assert Ecto.assoc_loaded?(reply.user)
      assert reply.user.id == owner.id
      assert Ecto.assoc_loaded?(reply.reply_to)
      assert Ecto.assoc_loaded?(reply.reply_to.user)
      assert reply.reply_to.user.id == parent_author.id
      assert Ecto.assoc_loaded?(reply.mentions)
    end)

    # One joined SELECT for message+user+reply_to+reply_to.user, one for mentions.
    # Query count must not grow with the number of replies.
    assert query_count == 2
  end

  test "toggles a reaction and summarises it", %{scope: scope, channel: channel, owner: owner} do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>hi</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:ok, summary} = Messages.toggle_reaction(scope, message.id, hd(Reaction.emojis()))
    assert summary[hd(Reaction.emojis())] == [owner.id]

    assert {:ok, %{}} = Messages.toggle_reaction(scope, message.id, hd(Reaction.emojis()))
  end

  test "indexes and finds traditional Mongolian after NNBSP / FVS normalisation", %{
    scope: scope,
    channel: channel
  } do
    # NNBSP (U+202F) and FVS1 (U+180B) must not keep two spellings apart
    html = "<p>ᠮᠣᠩᠭᠣᠯ\u202Fᠪᠢᠴᠢᠭ\u180B</p>"

    {:ok, _message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => html,
        "content" => %{"type" => "rich_text", "html" => html}
      })

    hits = Messages.search_messages([channel.id], "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ")
    assert length(hits) == 1

    assert Messages.search_messages([channel.id], "no-such-word") == []
  end

  test "updates search_text when a message is edited", %{scope: scope, channel: channel} do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>alpha</p>",
        "content" => %{"type" => "rich_text"}
      })

    {:ok, _} =
      Messages.update_message(scope, message.id, %{
        "content_html" => "<p>beta</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.search_messages([channel.id], "beta") != []
    assert Messages.search_messages([channel.id], "alpha") == []
  end

  test "search finds messages across the given channels", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "other"})

    {:ok, message} =
      Messages.create_message(scope, other.id, %{
        "content_html" => "<p>cross-channel-needle</p>",
        "content" => %{"type" => "rich_text"}
      })

    hits = Messages.search_messages([channel.id, other.id], "cross-channel-needle")
    assert length(hits) == 1
    assert hd(hits).id == message.id
    assert hd(hits).channel.name == "other"
    assert Messages.search_messages([channel.id], "cross-channel-needle") == []
  end

  test "plain_text strips tags", %{scope: scope, channel: channel} do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>hello <strong>there</strong></p>",
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.plain_text(message) == "hello there"
    assert Messages.excerpt(message, 5) == "hello…"
  end

  test "rate-limits rapid message creates", %{scope: scope, channel: channel, owner: owner} do
    RateLimiter.reset()
    previous = Application.get_env(:xamt, RateLimiter, [])

    try do
      Application.put_env(:xamt, RateLimiter, limit: 1, window_seconds: 60)

      attrs = %{"content_html" => "<p>ok</p>", "content" => %{"type" => "rich_text"}}
      assert {:ok, _} = Messages.create_message(scope, channel.id, attrs)
      assert {:error, :rate_limited} = Messages.create_message(scope, channel.id, attrs)

      # Direct check still respects explicit opts independently of app config
      RateLimiter.reset()
      assert :ok = RateLimiter.check_rate(owner.id, limit: 2, window_seconds: 60)
      assert :ok = RateLimiter.check_rate(owner.id, limit: 2, window_seconds: 60)

      assert {:error, :rate_limited} =
               RateLimiter.check_rate(owner.id, limit: 2, window_seconds: 60)
    after
      RateLimiter.reset()
      Application.put_env(:xamt, RateLimiter, previous)
    end
  end

  test "stores mentions of server members and rewrites the chip HTML", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    target =
      Xamt.AccountsFixtures.user_fixture(%{
        username: "bob#{System.unique_integer() |> abs()}",
        display_name: "Bob"
      })

    {:ok, _} = Servers.join_server(Scope.for_user(target), server.id)

    html =
      ~s[<p>hey <span class="evil" onclick="alert(1)" data-mention-id="#{target.id}">@wrong</span></p>]

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => html,
        "content" => %{"type" => "rich_text"}
      })

    assert message.mentioned_user_ids == [target.id]
    assert message.content_html =~ ~s(class="xamt-mention mongol-text")
    assert message.content_html =~ ~s(data-mention-id="#{target.id}")
    assert message.content_html =~ ~s(data-mention-username="#{target.username}")
    assert message.content_html =~ "@#{target.username}"
    refute message.content_html =~ "onclick"
    refute message.content_html =~ "@wrong"
    assert message.content_html =~ ~s(href="/profile/#{target.username}")
  end

  test "drops mentions of users who are not members", %{
    scope: scope,
    channel: channel
  } do
    outsider =
      Xamt.AccountsFixtures.user_fixture(%{username: "out#{System.unique_integer() |> abs()}"})

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" =>
          ~s(<p>hey <span data-mention-id="#{outsider.id}">@#{outsider.username}</span></p>),
        "content" => %{"type" => "rich_text"}
      })

    assert message.mentioned_user_ids == []
    refute message.content_html =~ "data-mention-id"
    assert message.content_html =~ "@#{outsider.username}"
  end

  test "replaces mention rows when a message is edited", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    first =
      Xamt.AccountsFixtures.user_fixture(%{username: "one#{System.unique_integer() |> abs()}"})

    second =
      Xamt.AccountsFixtures.user_fixture(%{username: "two#{System.unique_integer() |> abs()}"})

    {:ok, _} = Servers.join_server(Scope.for_user(first), server.id)
    {:ok, _} = Servers.join_server(Scope.for_user(second), server.id)

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" =>
          ~s(<p><span data-mention-id="#{first.id}">@#{first.username}</span></p>),
        "content" => %{"type" => "rich_text"}
      })

    assert message.mentioned_user_ids == [first.id]

    {:ok, updated} =
      Messages.update_message(scope, message.id, %{
        "content_html" =>
          ~s(<p><span data-mention-id="#{second.id}">@#{second.username}</span></p>),
        "content" => %{"type" => "rich_text"}
      })

    assert updated.mentioned_user_ids == [second.id]
    assert updated.content_html =~ "@#{second.username}"
    refute updated.content_html =~ first.username
  end

  test "update and delete broadcast the latest message and keep tombstones", %{
    scope: scope,
    channel: channel
  } do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>orig-body</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert_receive {:new_message, %{id: id}} when id == message.id

    {:ok, updated} =
      Messages.update_message(scope, message.id, %{
        "content_html" => "<p>edited-body</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert updated.content_html =~ "edited-body"
    assert DateTime.compare(updated.updated_at, updated.inserted_at) == :gt
    assert_receive {:updated_message, %{id: ^id, content_html: html}}
    assert html =~ "edited-body"

    outsider = Xamt.AccountsFixtures.user_fixture()
    outsider_scope = Scope.for_user(outsider)

    assert {:error, :unauthorized} =
             Messages.update_message(outsider_scope, message.id, %{
               "content_html" => "<p>nope</p>"
             })

    assert {:error, :unauthorized} = Messages.delete_message(outsider_scope, message.id)

    {:ok, deleted} = Messages.delete_message(scope, message.id)
    assert %DateTime{} = deleted.deleted_at
    assert_receive {:deleted_message, %{id: ^id, deleted_at: %DateTime{}}}

    listed = Messages.list_messages(channel.id)
    tombstone = Enum.find(listed, &(&1.id == message.id))
    assert tombstone
    assert tombstone.deleted_at

    assert {:error, :deleted} =
             Messages.update_message(scope, message.id, %{"content_html" => "<p>x</p>"})

    assert {:error, :deleted} = Messages.delete_message(scope, message.id)

    assert {:error, :deleted} =
             Messages.toggle_reaction(scope, message.id, hd(Reaction.emojis()))
  end

  defp with_query_count(fun) do
    parent = self()
    handler_id = "query-count-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:xamt, :repo, :query],
        fn _event, _meas, _meta, _config -> send(parent, :repo_query) end,
        nil
      )

    try do
      result = fun.()
      {result, drain_query_count(0)}
    after
      :telemetry.detach(handler_id)

      # Drop any leftover counts so they cannot leak into later tests.
      drain_query_count(0)
    end
  end

  defp drain_query_count(n) do
    receive do
      :repo_query -> drain_query_count(n + 1)
    after
      0 -> n
    end
  end
end
