defmodule Xamt.Repo.Migrations.AddLastReadAtToChannelReads do
  use Ecto.Migration

  def up do
    alter table(:channel_reads) do
      add :last_read_at, :utc_datetime
    end

    # Backfill from the referenced message's inserted_at (UUIDv4 cannot be ordered).
    execute("""
    UPDATE channel_reads AS cr
    SET last_read_at = m.inserted_at
    FROM messages AS m
    WHERE m.id = cr.last_read_message_id
    """)

    # Any orphaned rows without a message still need a non-null watermark.
    execute("""
    UPDATE channel_reads
    SET last_read_at = COALESCE(updated_at, inserted_at, NOW() AT TIME ZONE 'utc')
    WHERE last_read_at IS NULL
    """)

    alter table(:channel_reads) do
      modify :last_read_at, :utc_datetime, null: false
    end

    create index(:channel_reads, [:user_id, :last_read_at])
  end

  def down do
    drop_if_exists index(:channel_reads, [:user_id, :last_read_at])

    alter table(:channel_reads) do
      remove :last_read_at
    end
  end
end
