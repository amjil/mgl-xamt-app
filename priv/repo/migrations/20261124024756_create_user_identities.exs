defmodule Xamt.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :provider, :string, null: false
      add :issuer, :text, null: false
      add :subject, :text, null: false
      add :provider_username, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_identities, [:provider, :issuer, :subject],
             name: :user_identities_provider_issuer_subject_index
           )

    create unique_index(:user_identities, [:user_id, :provider],
             name: :user_identities_user_provider_index
           )

    create index(:user_identities, [:user_id])
  end
end
