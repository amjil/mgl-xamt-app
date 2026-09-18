defmodule XamtWeb.Presence do
  @moduledoc """
  Presence tracking for online users in channels.
  """

  use Phoenix.Presence,
    otp_app: :xamt,
    pubsub_server: Xamt.PubSub

  def topic, do: "presence"

  def track_user(pid, topic, user) when is_pid(pid) and is_binary(topic) do
    track(pid, topic, to_string(user.id), %{
      username: user.username,
      display_name: user.display_name || user.username,
      avatar: user.avatar,
      online_at: System.system_time(:second)
    })
  end

  def untrack_user(pid, topic, user) when is_pid(pid) and is_binary(topic) do
    untrack(pid, topic, to_string(user.id))
  end
end
