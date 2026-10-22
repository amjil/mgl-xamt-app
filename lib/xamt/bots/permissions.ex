defmodule Xamt.Bots.Permissions do
  @moduledoc false

  def required_scope_for_event("member.joined"), do: "server.members.events"
  def required_scope_for_event("message.created"), do: "channel.messages.read"
  def required_scope_for_event("reaction.added"), do: "channel.messages.read"
  def required_scope_for_event(_), do: nil
end
