defmodule Xamt.Bots.Permissions do
  @moduledoc false

  @event_scopes %{
    "member.joined" => "server.members.events",
    "member.left" => "server.members.events",
    "message.created" => "channel.messages.read",
    "message.updated" => "channel.messages.read",
    "message.deleted" => "channel.messages.read",
    "reaction.added" => "channel.messages.read",
    "bot.mentioned" => "channel.messages.read",
    "interaction.created" => "channel.messages.read",
    "interaction.responded" => "channel.messages.read",
    "channel.created" => "channel.messages.read"
  }

  def required_scope_for_event(event_type), do: Map.get(@event_scopes, event_type)

  def known_event_types, do: Map.keys(@event_scopes)
end
