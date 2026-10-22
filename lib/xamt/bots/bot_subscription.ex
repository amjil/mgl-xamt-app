defmodule Xamt.Bots.BotSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_events ["message.created", "member.joined", "reaction.added"]

  schema "bot_subscriptions" do
    field :event_type, :string
    field :filter, :map, default: %{}
    field :is_enabled, :boolean, default: true

    belongs_to :bot_installation, Xamt.Bots.BotInstallation
    belongs_to :channel, Xamt.Channels.Channel

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:bot_installation_id, :channel_id, :event_type, :filter, :is_enabled])
    |> validate_required([:bot_installation_id, :event_type])
    |> validate_inclusion(:event_type, @valid_events)
  end
end
