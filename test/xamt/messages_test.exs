defmodule Xamt.MessagesTest do
  use Xamt.DataCase, async: true

  alias Xamt.Accounts.Scope
  alias Xamt.{Channels, Messages, Servers}
  alias Xamt.Messages.Reaction

  setup do
    owner = Xamt.AccountsFixtures.user_fixture()
    scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(scope, %{"name" => "Test"})
    channel = hd(Channels.list_channels(server.id))
    %{scope: scope, channel: channel, owner: owner}
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

  test "plain_text strips tags", %{scope: scope, channel: channel} do
    {:ok, message} =
      Messages.create_message(scope, channel.id, %{
        "content_html" => "<p>hello <strong>there</strong></p>",
        "content" => %{"type" => "rich_text"}
      })

    assert Messages.plain_text(message) == "hello there"
    assert Messages.excerpt(message, 5) == "hello…"
  end
end
