defmodule Xamt.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      # Required on insert; nilified if the actor account is later removed so
      # the log itself is never deleted.
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :target_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Message, channel, member, etc. Stored as a string so one table can
      # cover every moderation action without a polymorphic FK.
      add :target_resource_id, :string
      add :action, :string, null: false
      add :reason, :string

      add :metadata, :jsonb, null: false, default: fragment("'{}'::jsonb")

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:server_id, :inserted_at])
    create index(:audit_logs, [:actor_id])
    create index(:audit_logs, [:target_user_id])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:target_resource_id])
  end
end
