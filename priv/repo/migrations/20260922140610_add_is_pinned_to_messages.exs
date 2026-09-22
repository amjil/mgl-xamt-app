defmodule Xamt.Repo.Migrations.AddIsPinnedToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :is_pinned, :boolean, default: false, null: false
    end

    # Speeds up "all pinned messages in this channel" (ordered by time).
    create index(:messages, [:channel_id, :inserted_at],
             where: "is_pinned = true AND deleted_at IS NULL",
             name: :messages_channel_id_pinned_index
           )
  end
end
