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
end
