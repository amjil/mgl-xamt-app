defmodule Xamt.Repo.Migrations.CreateBookmarks do
  use Ecto.Migration

  def change do
    create table(:bookmarks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bookmarks, [:user_id, :message_id])
    create index(:bookmarks, [:user_id])
  end
end
