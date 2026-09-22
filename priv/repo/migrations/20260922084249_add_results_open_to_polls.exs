defmodule Xamt.Repo.Migrations.AddResultsOpenToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      add :results_open, :boolean, null: false, default: true
    end
  end
end
