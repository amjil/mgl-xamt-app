defmodule Xamt.Repo.Migrations.DropSiteSettingsAndMagicLinkTokens do
  use Ecto.Migration

  # Registration and magic-link login were removed; Mgl ID is the only
  # sign-in path. The site_settings table only held those two switches, and
  # outstanding "login" (magic-link) tokens can no longer be redeemed.
  def up do
    execute("DELETE FROM users_tokens WHERE context = 'login'")
    drop table(:site_settings)
  end

  def down do
    create table(:site_settings, primary_key: false) do
      add :id, :string, primary_key: true
      add :registration_enabled, :boolean, default: true, null: false
      add :magic_link_enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    execute(
      """
      INSERT INTO site_settings (id, registration_enabled, magic_link_enabled, inserted_at, updated_at)
      VALUES ('default', TRUE, TRUE, timezone('utc', now()), timezone('utc', now()))
      """,
      "DELETE FROM site_settings WHERE id = 'default'"
    )
  end
end
