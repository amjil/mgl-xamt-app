defmodule Xamt.Repo.Migrations.AddIndexesForUnreadChannels do
  use Ecto.Migration

  def change do
    # Composite index for unread N+1 predicates
    # (m.channel_id == ^server_id AND m.inserted_at ...)
    # so the DB can decide "latest message" from the index alone.
    drop_if_exists index(:messages, [:channel_id, :inserted_at])
    create index(:messages, [:channel_id, :inserted_at, :id])

    # unique_index([:user_id, :channel_id]) on channel_reads already exists in the create migration
  end
end
