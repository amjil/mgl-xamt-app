defmodule Xamt.Repo.Migrations.CreateBotPlatformTables do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_bot, :boolean, default: false, null: false
    end

    create table(:bots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, size: 80, null: false
      add :avatar_url, :string
      add :description, :string, size: 500

      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :bot_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :webhook_url, :string, null: false
      add :signing_secret, :string, null: false

      add :requested_scopes, {:array, :string}, default: [], null: false
      add :status, :string, size: 20, default: "active", null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bots, [:creator_id])
    create unique_index(:bots, [:bot_user_id])

    create table(:bot_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all)
      add :installed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :granted_scopes, {:array, :string}, default: [], null: false
      add :allowed_channel_ids, {:array, :binary_id}, default: [], null: false
      add :status, :string, size: 20, default: "enabled", null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bot_installations, [:bot_id, :server_id, :channel_id],
             where: "channel_id IS NOT NULL"
           )

    create unique_index(:bot_installations, [:bot_id, :server_id],
             name: :bot_installations_bot_id_server_id_null_channel_index,
             where: "channel_id IS NULL"
           )

    create index(:bot_installations, [:server_id, :status])
    create index(:bot_installations, [:channel_id, :status])

    create table(:bot_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false

      add :bot_installation_id,
          references(:bot_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token_hash, :binary, null: false
      add :token_prefix, :string, size: 20, null: false
      add :scopes, {:array, :string}, default: [], null: false

      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:bot_tokens, [:token_hash])
    create index(:bot_tokens, [:bot_installation_id])

    create table(:bot_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bot_installation_id,
          references(:bot_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :event_type, :string, size: 60, null: false
      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all)
      add :filter, :map, default: %{}, null: false
      add :is_enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bot_subscriptions, [:bot_installation_id, :event_type, :channel_id],
             where: "channel_id IS NOT NULL"
           )

    create unique_index(:bot_subscriptions, [:bot_installation_id, :event_type],
             name: :bot_subscriptions_installation_event_null_channel_index,
             where: "channel_id IS NULL"
           )

    create index(:bot_subscriptions, [:event_type, :is_enabled])

    create table(:bot_commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 40, null: false
      add :description, :string, size: 200, null: false
      add :parameters_schema, {:array, :map}, default: [], null: false
      add :is_enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bot_commands, [:bot_id, :name])

    create table(:bot_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bot_id, references(:bots, type: :binary_id, on_delete: :delete_all), null: false

      add :bot_installation_id,
          references(:bot_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :channel_id, references(:channels, type: :binary_id, on_delete: :nilify_all)

      add :event_type, :string, size: 60, null: false
      add :payload, :map, null: false

      add :status, :string, size: 20, default: "pending", null: false
      add :retry_count, :integer, default: 0, null: false
      add :max_retries, :integer, default: 5, null: false
      add :next_attempt_at, :utc_datetime_usec, null: false
      add :delivered_at, :utc_datetime_usec
      add :execution_result, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bot_events, [:status, :next_attempt_at])
    create index(:bot_events, [:bot_installation_id, :inserted_at])
  end
end
