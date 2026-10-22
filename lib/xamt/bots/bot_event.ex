defmodule Xamt.Bots.BotEvent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_events" do
    field :event_type, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :retry_count, :integer, default: 0
    field :max_retries, :integer, default: 5
    field :next_attempt_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :execution_result, :map, default: %{}

    belongs_to :bot, Xamt.Bots.Bot
    belongs_to :bot_installation, Xamt.Bots.BotInstallation
    belongs_to :server, Xamt.Servers.Server
    belongs_to :channel, Xamt.Channels.Channel

    timestamps(type: :utc_datetime_usec)
  end
end
