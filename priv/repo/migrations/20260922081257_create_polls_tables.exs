defmodule Xamt.Repo.Migrations.CreatePollsTables do
  use Ecto.Migration

  def change do
    create table(:polls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :question, :string, null: false
      add :allow_multiple, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:polls, [:message_id])

    create table(:poll_options, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all), null: false
      add :text, :string, null: false
      add :votes_count, :integer, null: false, default: 0
      add :position, :integer, null: false, default: 0
    end

    create index(:poll_options, [:poll_id])

    create table(:poll_votes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all), null: false

      add :poll_option_id, references(:poll_options, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:poll_votes, [:poll_option_id, :user_id])
    create index(:poll_votes, [:poll_id])
    create index(:poll_votes, [:user_id])
  end
end
