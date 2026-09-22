defmodule Xamt.MessagesTest do
  use Xamt.DataCase, async: false

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Moderation, Servers}
  alias Xamt.Messages.{RateLimiter, Reaction}

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Test"})
    channel = hd(Channels.list_channels(server.id))
    %{scope: scope, channel: channel, owner: owner, server: server}
  end

  test "stores audio messages and keeps the player payload on broadcast", %{
    scope: scope,
    channel: channel
  } do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "🎤 <em>Voice message</em>",
        "content" => %{"type" => "audio", "url" => "/uploads/voice.webm"}
      })

    assert message.content_type == "audio"
    assert message.content["url"] == "/uploads/voice.webm"
    assert message.search_text =~ "Voice message"

    assert_receive {:new_message, broadcasted}
    assert broadcasted.content == %{"type" => "audio", "url" => "/uploads/voice.webm"}
  end

  test "stores gallery messages and keeps images on broadcast", %{
    scope: scope,
    channel: channel
  } do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    images = [
      %{"thumb" => "/uploads/thumb_a.jpg", "original" => "/uploads/a.jpg"},
      %{"thumb" => "/uploads/thumb_b.jpg", "original" => "/uploads/b.jpg"}
    ]

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "",
        "content" => %{"type" => "gallery", "images" => images},
        "content_type" => "gallery"
      })

    assert message.content_type == "gallery"
    assert message.content["images"] == images
    assert message.search_text == "🖼"
    assert Messages.excerpt(message) == "🖼"

    assert_receive {:new_message, broadcasted}
    assert broadcasted.content == %{"type" => "gallery", "images" => images}
  end

  test "gallery caption is used for search and excerpt", %{scope: scope, channel: channel} do
    images = [%{"thumb" => "/uploads/thumb_a.jpg", "original" => "/uploads/a.jpg"}]

    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>road trip</p>",
        "content" => %{"type" => "gallery", "images" => images},
        "content_type" => "gallery"
      })

    assert message.search_text =~ "road trip"
    assert Messages.excerpt(message) =~ "road trip"
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

  test "rejects reactions from users outside the server", %{
    scope: scope,
    channel: channel
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>react me</p>",
        "content" => %{"type" => "rich_text"}
      })

    outsider = Xamt.AccountsFixtures.user_fixture()

    assert {:error, :unauthorized} =
             Messages.toggle_reaction(Scope.for_user(outsider), message.id, hd(Reaction.emojis()))
  end

  test "creates a poll message with options", %{scope: scope, channel: channel} do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Where this weekend?",
        "options" => ["North", "South", "Stay home"],
        "allow_multiple" => false
      })

    assert message.content_type == "poll"
    assert message.content["question"] == "Where this weekend?"
    assert message.search_text =~ "Where this weekend?"
    assert Messages.excerpt(message) =~ "Where this weekend?"

    summary = Messages.poll_summary([message.id])
    poll = summary[message.id]
    assert poll.question == "Where this weekend?"
    assert length(poll.options) == 3
    assert Enum.all?(poll.options, &(&1.votes_count == 0))

    assert_receive {:new_message, broadcasted}
    assert broadcasted.content_type == "poll"
    assert broadcasted.content == %{"type" => "poll", "question" => "Where this weekend?"}
  end

  test "rejects invalid poll option counts", %{scope: scope, channel: channel} do
    assert {:error, :invalid_poll} =
             Messages.create_poll_message(scope, channel.id, %{
               "question" => "Only one?",
               "options" => ["A"]
             })

    assert {:error, :invalid_poll} =
             Messages.create_poll_message(scope, channel.id, %{
               "question" => "",
               "options" => ["A", "B"]
             })
  end

  test "single-select vote switches options and updates counts", %{
    scope: scope,
    channel: channel,
    owner: owner
  } do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Pick one",
        "options" => ["A", "B"],
        "allow_multiple" => false
      })

    poll = Messages.poll_summary([message.id])[message.id]
    [opt_a, opt_b] = poll.options

    assert {:ok, payload} = Messages.toggle_vote(scope, poll.id, opt_a.id)
    assert opt_a.id in payload.poll.selected_option_ids
    assert Enum.find(payload.poll.options, &(&1.id == opt_a.id)).votes_count == 1

    assert_receive {:poll_updated, %{poll: updated}}
    assert Enum.find(updated.options, &(&1.id == opt_a.id)).votes_count == 1

    assert {:ok, payload2} = Messages.toggle_vote(scope, poll.id, opt_b.id)
    assert payload2.poll.selected_option_ids == [opt_b.id]
    assert Enum.find(payload2.poll.options, &(&1.id == opt_a.id)).votes_count == 0
    assert Enum.find(payload2.poll.options, &(&1.id == opt_b.id)).votes_count == 1

    my = Messages.poll_votes_for_user(owner.id, [poll.id])
    assert MapSet.member?(my[poll.id], opt_b.id)
    refute MapSet.member?(my[poll.id], opt_a.id)
  end

  test "multi-select toggles options independently", %{scope: scope, channel: channel} do
    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Pick many",
        "options" => ["A", "B", "C"],
        "allow_multiple" => true
      })

    poll = Messages.poll_summary([message.id])[message.id]
    [opt_a, opt_b, _opt_c] = poll.options

    assert {:ok, _} = Messages.toggle_vote(scope, poll.id, opt_a.id)
    assert {:ok, payload} = Messages.toggle_vote(scope, poll.id, opt_b.id)
    assert MapSet.new(payload.poll.selected_option_ids) == MapSet.new([opt_a.id, opt_b.id])

    assert {:ok, payload2} = Messages.toggle_vote(scope, poll.id, opt_a.id)
    assert payload2.poll.selected_option_ids == [opt_b.id]
    assert Enum.find(payload2.poll.options, &(&1.id == opt_a.id)).votes_count == 0
    assert Enum.find(payload2.poll.options, &(&1.id == opt_b.id)).votes_count == 1
  end

  test "rejects votes on deleted messages and from outsiders", %{
    scope: scope,
    channel: channel
  } do
    {:ok, message} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Gone?",
        "options" => ["Yes", "No"]
      })

    poll = Messages.poll_summary([message.id])[message.id]
    option_id = hd(poll.options).id

    outsider = Xamt.AccountsFixtures.user_fixture()

    assert {:error, :unauthorized} =
             Messages.toggle_vote(Scope.for_user(outsider), poll.id, option_id)

    {:ok, _} = Messages.delete_message(scope, message.id)

    assert {:error, :deleted} = Messages.toggle_vote(scope, poll.id, option_id)
  end

  test "open poll details list voters; closed polls are author-only", %{
    scope: scope,
    channel: channel,
    server: server,
    owner: owner
  } do
    member =
      Xamt.AccountsFixtures.user_fixture(%{
        username: "voter#{System.unique_integer() |> abs()}"
      })

    {:ok, _} = Servers.join_server(Scope.for_user(member), server.id)
    member_scope = Scope.for_user(member)

    {:ok, open_msg} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Open poll",
        "options" => ["Yes", "No"],
        "results_open" => true
      })

    open_poll = Messages.poll_summary([open_msg.id])[open_msg.id]
    yes = hd(open_poll.options)

    assert {:ok, _} = Messages.toggle_vote(member_scope, open_poll.id, yes.id)
    assert {:ok, details} = Messages.get_poll_details(member_scope, open_poll.id)
    assert hd(Enum.find(details.options, &(&1.id == yes.id)).voters).id == member.id

    {:ok, closed_msg} =
      Messages.create_poll_message(scope, channel.id, %{
        "question" => "Closed poll",
        "options" => ["A", "B"],
        "results_open" => false
      })

    closed_poll = Messages.poll_summary([closed_msg.id])[closed_msg.id]
    assert closed_poll.results_open == false

    assert {:error, :forbidden} = Messages.get_poll_details(member_scope, closed_poll.id)
    assert {:ok, _} = Messages.get_poll_details(Scope.for_user(owner), closed_poll.id)
  end

  test "sanitizes dangerous HTML before persist", %{scope: scope, channel: channel} do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" =>
          ~s|<p>safe<img src=x onerror="alert(1)"><script>document.cookie</script></p>|,
        "content" => %{"type" => "rich_text"}
      })

    refute message.content_html =~ "onerror"
    refute message.content_html =~ "<script"
    refute message.content_html =~ "document.cookie"
    assert message.content_html =~ "safe"
    assert message.content["html"] == message.content_html
  end

  test "rejects reply_to_id from another channel", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    {:ok, other} = Channels.create_channel(scope, server, %{"name" => "other-reply"})

    {:ok, foreign} =
      Messages.create_message(scope, other.id, %{
        "content_html" => "<p>foreign parent</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:error, :invalid_reply} =
             Messages.create_message(scope, channel.id, %{
               "content_html" => "<p>sneaky reply</p>",
               "content" => %{"type" => "rich_text"},
               "reply_to_id" => foreign.id
             })
  end

  test "get_message_for_user requires channel membership", %{
    scope: scope,
    channel: channel
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>mine</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:ok, loaded} = Messages.get_message_for_user(scope, message.id)
    assert loaded.id == message.id

    outsider = Xamt.AccountsFixtures.user_fixture()

    assert {:error, :unauthorized} =
             Messages.get_message_for_user(Scope.for_user(outsider), message.id)
  end

  test "search_server_messages only covers the user's server", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    {:ok, _} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>server-needle-alpha</p>",
        "content" => %{"type" => "rich_text"}
      })

    other_owner = Xamt.AccountsFixtures.creator_fixture()
    other_scope = Scope.for_user(other_owner)
    {:ok, other_server} = Servers.create_server(other_scope, %{"name" => "Other"})
    other_channel = hd(Channels.list_channels(other_server.id))

    {:ok, _} =
      Messages.create_message(other_scope, other_channel.id, %{
        "content_html" => "<p>server-needle-alpha</p>",
        "content" => %{"type" => "rich_text"}
      })

    hits = Messages.search_server_messages(scope, server.id, "server-needle-alpha")
    assert length(hits) == 1
    assert hd(hits).channel_id == channel.id

    assert Messages.search_server_messages(scope, other_server.id, "server-needle-alpha") == []
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

    # Authors retracting their own message stay out of the server audit log.
    assert Moderation.list_audit_logs_for_resource(channel.server_id, message.id) == []

    assert {:error, :deleted} =
             Messages.update_message(scope, message.id, %{"content_html" => "<p>x</p>"})

    assert {:error, :deleted} = Messages.delete_message(scope, message.id)

    assert {:error, :deleted} =
             Messages.toggle_reaction(scope, message.id, hd(Reaction.emojis()))
  end

  test "members without send_messages cannot post", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    muted = Xamt.AccountsFixtures.user_fixture()
    muted_scope = Scope.for_user(muted)
    {:ok, _} = Servers.join_server(muted_scope, server.id)

    {:ok, _} = Servers.revoke_permission(scope, server.id, muted.id, :send_messages)

    assert {:error, :unauthorized} =
             Messages.create_message(muted_scope, channel.id, %{
               "content_html" => "<p>nope</p>",
               "content" => %{"type" => "rich_text"}
             })
  end

  test "manage_messages lets a moderator delete someone else's message", %{
    scope: scope,
    channel: channel,
    server: server,
    owner: owner
  } do
    author = Xamt.AccountsFixtures.user_fixture()
    author_scope = Scope.for_user(author)
    {:ok, _} = Servers.join_server(author_scope, server.id)

    {:ok, message} =
      Messages.create_message(author_scope, channel.id, %{
        "content_html" => "<p>take this down</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:ok, deleted} = Messages.delete_message(scope, message.id, "spam")
    assert %DateTime{} = deleted.deleted_at

    [log] = Moderation.list_audit_logs(server.id)
    assert log.action == "message_deleted"
    assert log.actor_id == owner.id
    assert log.target_user_id == author.id
    assert log.target_resource_id == message.id
    assert log.reason == "spam"
    assert log.metadata["channel_id"] == channel.id
    assert log.metadata["content_snippet"] == "take this down"
    assert log.metadata["actor_username"] == owner.username
    assert log.metadata["target_username"] == author.username
  end

  test "toggle_pin_message requires manage_messages and broadcasts", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    Phoenix.PubSub.subscribe(Xamt.PubSub, Messages.channel_topic(channel.id))

    author = Xamt.AccountsFixtures.user_fixture()
    author_scope = Scope.for_user(author)
    {:ok, _} = Servers.join_server(author_scope, server.id)

    {:ok, message} =
      Messages.create_message(author_scope, channel.id, %{
        "content_html" => "<p>pin me</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:error, :unauthorized} = Messages.toggle_pin_message(author_scope, message.id)

    assert {:ok, pinned} = Messages.toggle_pin_message(scope, message.id)
    assert pinned.is_pinned
    assert_receive {:message_pinned_toggled, %{id: id, is_pinned: true}} when id == message.id

    assert [listed] = Messages.list_pinned_messages(channel.id)
    assert listed.id == message.id

    assert {:ok, unpinned} = Messages.toggle_pin_message(scope, message.id)
    refute unpinned.is_pinned
    assert_receive {:message_pinned_toggled, %{id: ^id, is_pinned: false}}
    assert Messages.list_pinned_messages(channel.id) == []
  end

  test "deleted messages cannot be pinned and leave the board", %{
    scope: scope,
    channel: channel
  } do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>gone</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:ok, pinned} = Messages.toggle_pin_message(scope, message.id)
    assert pinned.is_pinned
    assert length(Messages.list_pinned_messages(channel.id)) == 1

    assert {:ok, _} = Messages.delete_message(scope, message.id)
    assert Messages.list_pinned_messages(channel.id) == []
    assert {:error, :deleted} = Messages.toggle_pin_message(scope, message.id)
  end

  test "moderator delete without a reason still writes an audit log", %{
    scope: scope,
    channel: channel,
    server: server
  } do
    author = Xamt.AccountsFixtures.user_fixture()
    {:ok, _} = Servers.join_server(Scope.for_user(author), server.id)

    {:ok, message} =
      Messages.create_message(Scope.for_user(author), channel.id, %{
        "content_html" => "<p>blank reason</p>",
        "content" => %{"type" => "rich_text"}
      })

    assert {:ok, _} = Messages.delete_message(scope, message.id, "   ")
    [log] = Moderation.list_audit_logs_for_resource(server.id, message.id)
    assert log.action == "message_deleted"
    assert is_nil(log.reason)
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
