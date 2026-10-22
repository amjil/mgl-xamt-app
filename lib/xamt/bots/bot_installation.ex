defmodule Xamt.Bots.BotInstallation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_installations" do
    field :granted_scopes, {:array, :string}, default: []
    field :allowed_channel_ids, {:array, :binary_id}, default: []
    field :status, :string, default: "enabled"

    belongs_to :bot, Xamt.Bots.Bot
    belongs_to :server, Xamt.Servers.Server
    belongs_to :channel, Xamt.Channels.Channel
    belongs_to :installed_by, Xamt.Accounts.User

    has_many :subscriptions, Xamt.Bots.BotSubscription
    has_many :tokens, Xamt.Bots.BotToken

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [
      :bot_id,
      :server_id,
      :channel_id,
      :installed_by_id,
      :granted_scopes,
      :allowed_channel_ids,
      :status
    ])
    |> validate_required([:bot_id, :server_id])
    |> validate_inclusion(:status, ["enabled", "disabled"])
  end
end
