defmodule Xamt.Repo.Migrations.CreateSiteSettings do
  use Ecto.Migration

  def change do
    create table(:site_settings, primary_key: false) do
      add :id, :string, primary_key: true
      add :registration_enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    execute(
      """
      INSERT INTO site_settings (id, registration_enabled, inserted_at, updated_at)
      VALUES ('default', TRUE, timezone('utc', now()), timezone('utc', now()))
      """,
      "DELETE FROM site_settings WHERE id = 'default'"
    )
  end
end
