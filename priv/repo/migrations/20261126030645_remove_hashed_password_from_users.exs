defmodule Xamt.Repo.Migrations.RemoveHashedPasswordFromUsers do
  use Ecto.Migration

  # Sign-in is Mgl ID only; no code path reads or writes local passwords now.
  def up do
    alter table(:users) do
      remove :hashed_password
    end
  end

  # Existing hashes are not recoverable; the column comes back empty.
  def down do
    alter table(:users) do
      add :hashed_password, :string
    end
  end
end
