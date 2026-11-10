defmodule Xamt.Workers.LinkPreviewWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :link_preview,
    max_attempts: 3,
    unique: [
      period: 60,
      keys: [:message_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Xamt.Messages.LinkPreview
  alias Xamt.Messages.Message
  alias Xamt.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id, "url" => url}}) do
    case Repo.get(Message, message_id) do
      nil ->
        {:cancel, :message_not_found}

      message ->
        LinkPreview.unfurl_now(message, url)
        :ok
    end
  end
end
