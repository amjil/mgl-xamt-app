defmodule Xamt.Repo.Migrations.CreateCommunityTables do
  use Ecto.Migration

  def change do
    create table(:servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :icon, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:servers, [:slug])
    create index(:servers, [:owner_id])

    create table(:server_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :nickname, :string
      add :joined_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:server_members, [:server_id, :user_id])
    create index(:server_members, [:server_id])
    create index(:server_members, [:user_id])

    create table(:channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :type, :string, null: false, default: "text"
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:server_id, :slug])
    create index(:channels, [:server_id])

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :channel_id, references(:channels, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :content, :map, null: false, default: %{}
      add :content_type, :string, null: false, default: "rich_text"
      add :content_html, :text
      add :reply_to_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:user_id])
    create index(:messages, [:reply_to_id])

    create table(:message_reactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:message_reactions, [:message_id, :user_id, :emoji])
    create index(:message_reactions, [:message_id])
  end
end
