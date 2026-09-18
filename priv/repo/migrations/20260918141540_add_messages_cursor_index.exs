defmodule Xamt.Repo.Migrations.AddMessagesCursorIndex do
  use Ecto.Migration

  # CREATE INDEX CONCURRENTLY cannot run inside a transaction.
  # Without advisory-lock migration_lock on the Repo, both must be disabled.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Matches list_messages: channel_id + order_by [desc: inserted_at, desc: id]
    # + where is_nil(deleted_at). Message ids are UUIDs, so id alone is not time-ordered.
    create index(
             :messages,
             [:channel_id, "inserted_at DESC", "id DESC"],
             concurrently: true,
             where: "deleted_at IS NULL",
             name: :messages_channel_cursor_idx
           )
  end
end
