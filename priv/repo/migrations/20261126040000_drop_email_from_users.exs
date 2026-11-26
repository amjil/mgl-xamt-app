defmodule Xamt.Repo.Migrations.DropEmailFromUsers do
  use Ecto.Migration

  def up do
    # Change-email tokens are meaningless once the column is gone.
    execute "DELETE FROM users_tokens WHERE context LIKE 'change:%'"

    # Dropping the column also drops its unique index.
    alter table(:users) do
      remove :email
    end
  end

  def down do
    # Data cannot be restored; the column comes back empty and nullable.
    alter table(:users) do
      add :email, :citext
    end

    create unique_index(:users, [:email])
  end
end
