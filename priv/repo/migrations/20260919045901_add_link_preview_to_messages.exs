defmodule Xamt.Repo.Migrations.AddLinkPreviewToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :link_preview, :map
    end
  end
end
