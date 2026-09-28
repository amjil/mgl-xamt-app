defmodule Xamt.Repo.Migrations.AddMagicLinkEnabledToSiteSettings do
  use Ecto.Migration

  def change do
    alter table(:site_settings) do
      add :magic_link_enabled, :boolean, default: true, null: false
    end
  end
end
