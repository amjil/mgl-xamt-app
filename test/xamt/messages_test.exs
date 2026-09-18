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
end
