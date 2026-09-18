defmodule Xamt.Repo.Migrations.AddServerVisibilityAndInvites do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :visibility, :string, null: false, default: "private"
    end

    create index(:servers, [:visibility])

    create table(:server_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code, :string, null: false
      add :expires_at, :utc_datetime
      add :max_uses, :integer
      add :uses, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:server_invites, [:code])
    create index(:server_invites, [:server_id])
  end
end
