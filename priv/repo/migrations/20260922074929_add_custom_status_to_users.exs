defmodule Xamt.Repo.Migrations.AddCustomStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :status_emoji, :string, size: 10
      add :status_text, :string, size: 50
    end
  end
end
