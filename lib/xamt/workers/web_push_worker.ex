defmodule Xamt.Workers.WebPushWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :web_push,
    max_attempts: 3,
    unique: [
      period: 30,
      keys: [:user_id, :message_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Xamt.Messages.Message
  alias Xamt.Notifications.WebPush
  alias Xamt.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "message_id" => message_id}}) do
    case Repo.get(Message, message_id) do
      nil ->
        {:cancel, :message_not_found}

      message ->
        WebPush.deliver_mention_now(user_id, message)
        :ok
    end
  end
end
