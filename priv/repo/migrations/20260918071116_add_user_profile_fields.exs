defmodule Xamt.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :citext, null: false
      add :display_name, :string
      add :avatar, :string
      add :bio, :text
      add :status, :string, null: false, default: "offline"
    end

    create unique_index(:users, [:username])
  end
end
