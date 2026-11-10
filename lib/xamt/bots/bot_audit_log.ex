defmodule Xamt.Bots.BotAuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(
    bot.created
    bot.updated
    bot.suspended
    installation.created
    installation.updated
    installation.uninstalled
    token.issued
    token.rotated
    token.revoked
    message.sent
    message.updated
    message.deleted
    interaction.created
    interaction.responded
    delivery.retried
    subscription.disabled
  )

  schema "bot_audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}

    belongs_to :bot, Xamt.Bots.Bot
    belongs_to :bot_installation, Xamt.Bots.BotInstallation
    belongs_to :actor_user, Xamt.Accounts.User
    belongs_to :server, Xamt.Servers.Server
    belongs_to :channel, Xamt.Channels.Channel

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def actions, do: @actions

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :bot_id,
      :bot_installation_id,
      :actor_user_id,
      :server_id,
      :channel_id,
      :action,
      :resource_type,
      :resource_id,
      :metadata
    ])
    |> validate_required([:bot_id, :action])
    |> validate_inclusion(:action, @actions)
  end
end
