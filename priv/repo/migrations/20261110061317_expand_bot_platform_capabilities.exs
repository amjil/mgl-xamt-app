defmodule Xamt.Repo.Migrations.ExpandBotPlatformCapabilities do
  use Ecto.Migration

  def change do
    alter table(:bot_installations) do
      add :uninstalled_at, :utc_datetime_usec
    end

    create table(:bot_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false

      add :bot_installation_id,
          references(:bot_installations, type: :binary_id, on_delete: :nilify_all)

      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :server_id, references(:servers, type: :binary_id, on_delete: :nilify_all)
      add :channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)

      add :action, :string, size: 80, null: false
      add :resource_type, :string, size: 40
      add :resource_id, :string, size: 64
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:bot_audit_logs, [:bot_id, :inserted_at])
    create index(:bot_audit_logs, [:bot_installation_id, :inserted_at])
    create index(:bot_audit_logs, [:server_id, :inserted_at])

    create table(:bot_idempotency_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bot_installation_id,
          references(:bot_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :nonce, :string, size: 128, null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:bot_idempotency_keys, [:bot_installation_id, :nonce])

    create table(:bot_interactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false

      add :bot_installation_id,
          references(:bot_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all)
      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :action_key, :string, size: 80, null: false
      add :label, :string, size: 120
      add :payload, :map, default: %{}, null: false
      add :status, :string, size: 20, default: "pending", null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :responded_at, :utc_datetime_usec
      add :response_payload, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bot_interactions, [:bot_installation_id, :status])
    create index(:bot_interactions, [:message_id])
    create index(:bot_interactions, [:expires_at, :status])
  end
end
