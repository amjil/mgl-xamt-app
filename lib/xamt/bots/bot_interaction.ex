defmodule Xamt.Bots.BotInteraction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending responded expired cancelled)

  schema "bot_interactions" do
    field :action_key, :string
    field :label, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime_usec
    field :responded_at, :utc_datetime_usec
    field :response_payload, :map, default: %{}

    belongs_to :bot, Xamt.Bots.Bot
    belongs_to :bot_installation, Xamt.Bots.BotInstallation
    belongs_to :server, Xamt.Servers.Server
    belongs_to :channel, Xamt.Channels.Channel
    belongs_to :message, Xamt.Messages.Message
    belongs_to :created_by_user, Xamt.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, [
      :bot_id,
      :bot_installation_id,
      :server_id,
      :channel_id,
      :message_id,
      :created_by_user_id,
      :action_key,
      :label,
      :payload,
      :status,
      :expires_at,
      :responded_at,
      :response_payload
    ])
    |> validate_required([
      :bot_id,
      :bot_installation_id,
      :server_id,
      :channel_id,
      :action_key,
      :expires_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:action_key, max: 80)
    |> validate_length(:label, max: 120)
  end
end
