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
      status_emoji: user.status_emoji,
      status_text: user.status_text,
      online_at: System.system_time(:second)
    })
  end

  def untrack_user(pid, topic, user) when is_pid(pid) and is_binary(topic) do
    untrack(pid, topic, to_string(user.id))
  end

  @doc """
  Updates the tracked user's custom status meta on a channel topic.
  """
  def update_user_status(pid, topic, user, attrs)
      when is_pid(pid) and is_binary(topic) and is_map(attrs) do
    update(pid, topic, to_string(user.id), fn existing_meta ->
      Map.merge(existing_meta, %{
        status_emoji: Map.get(attrs, :status_emoji) || Map.get(attrs, "status_emoji"),
        status_text: Map.get(attrs, :status_text) || Map.get(attrs, "status_text")
      })
    end)
  end
end
