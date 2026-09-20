defmodule Xamt.Moderation.AuditLog do
  @moduledoc """
  Immutable server-level moderation record.

  `metadata` is a JSONB map so new action types (kicks, renames, permission
  changes) can attach whatever snapshot they need without a migration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @actions ~w(message_deleted)
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :target_resource_id, :string
    field :action, :string
    field :reason, :string
    field :metadata, :map, default: %{}

    belongs_to :server, Xamt.Servers.Server
    belongs_to :actor, Xamt.Accounts.User
    belongs_to :target_user, Xamt.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def actions, do: @actions

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :server_id,
      :actor_id,
      :target_user_id,
      :target_resource_id,
      :action,
      :reason,
      :metadata
    ])
    |> validate_required([:server_id, :actor_id, :action])
    |> validate_inclusion(:action, @actions)
    |> validate_length(:reason, max: 500)
    |> validate_length(:target_resource_id, max: 64)
    |> foreign_key_constraint(:server_id)
    |> foreign_key_constraint(:actor_id)
    |> foreign_key_constraint(:target_user_id)
  end
end
