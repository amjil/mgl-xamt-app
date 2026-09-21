defmodule Xamt.Repo.Migrations.AddGlobalRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :global_role, :string, default: "user", null: false
    end

    create index(:users, [:global_role])
  end
end
