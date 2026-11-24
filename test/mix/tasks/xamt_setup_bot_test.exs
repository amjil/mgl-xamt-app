defmodule Mix.Tasks.Xamt.SetupBotTest do
  use Xamt.DataCase, async: false

  alias Mix.Tasks.Xamt.SetupBot
  alias Xamt.Accounts.Scope
  alias Xamt.{Bots, Channels, Servers}

  setup do
    owner = Xamt.AccountsFixtures.creator_fixture()
    owner_scope = Scope.for_user(owner)
    {:ok, server} = Servers.create_server(owner_scope, %{"name" => "Setup Bot Hall"})

    %{owner: owner, server: server}
  end

  test "creates channel and bot, sets webhook to bot uuid", %{server: server} do
    assert {:ok, result} =
             SetupBot.setup(
               server_id: server.id,
               channel_name: "ops",
               bot_name: "Ops Bot",
               bot_base_url: "http://127.0.0.1:4003",
               handler: "echo"
             )

    assert result.channel_action == :created
    assert result.bot_action == :created
    assert result.channel.name == "ops"
    assert result.bot.name == "Ops Bot"
    assert result.channel.id in result.installation.allowed_channel_ids
    assert result.webhook_url == "http://127.0.0.1:4003/webhooks/xamt/#{result.bot.id}"
    assert String.starts_with?(result.signing_secret, "whsec_")
    assert String.starts_with?(result.api_token, "xamt_bot_")
    assert {:ok, _} = Bots.authenticate_token(result.api_token)

    output = SetupBot.format_output(result)
    assert output =~ result.bot.id
    assert output =~ "--handler echo"
    assert output =~ "--channel-id #{result.channel.id}"
  end

  test "reuses channel and bot and rotates api token", %{server: server} do
    assert {:ok, first} =
             SetupBot.setup(
               server_slug: server.slug,
               channel_name: "reuse-ch",
               bot_name: "Reuse Bot",
               bot_base_url: "http://bot.local:4003"
             )

    old_token = first.api_token

    assert {:ok, second} =
             SetupBot.setup(
               server_slug: server.slug,
               channel_name: "reuse-ch",
               bot_name: "Reuse Bot",
               bot_base_url: "http://bot.local:4003"
             )

    assert second.channel_action == :reused
    assert second.bot_action == :reused
    assert second.channel.id == first.channel.id
    assert second.bot.id == first.bot.id
    assert second.api_token != old_token
    assert {:ok, _} = Bots.authenticate_token(second.api_token)
    assert {:error, :invalid_token} = Bots.authenticate_token(old_token)
    assert second.channel.id in second.installation.allowed_channel_ids
  end

  test "uses existing channel by id", %{server: server, owner: owner} do
    {:ok, channel} =
      Channels.create_channel(Scope.for_user(owner), server, %{"name" => "existing"})

    assert {:ok, result} =
             SetupBot.setup(
               server_id: server.id,
               channel_id: channel.id,
               bot_name: "Channel Id Bot"
             )

    assert result.channel_action == :reused
    assert result.channel.id == channel.id
  end

  test "requires a server selector" do
    assert {:error, {:server_required, _}} = SetupBot.setup([])
  end
end
