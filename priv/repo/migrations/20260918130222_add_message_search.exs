defmodule Xamt.Repo.Migrations.AddMessageSearch do
  use Ecto.Migration

  def up do
    alter table(:messages) do
      # Search-normalised plain text: tags stripped, NNBSP/MVS turned into
      # spaces and free variation selectors removed. See Xamt.Messages.
      add :search_text, :text
    end

    # Rough backfill — new and edited messages get the proper normalisation
    execute """
    UPDATE messages
    SET search_text = btrim(regexp_replace(regexp_replace(coalesce(content_html, ''), '<[^>]+>', ' ', 'g'), '\\s+', ' ', 'g'))
    """

    execute """
    ALTER TABLE messages
    ADD COLUMN search_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('simple', coalesce(search_text, ''))) STORED
    """

    execute "CREATE INDEX messages_search_tsv_index ON messages USING GIN (search_tsv)"
  end

  def down do
    execute "DROP INDEX IF EXISTS messages_search_tsv_index"
    execute "ALTER TABLE messages DROP COLUMN IF EXISTS search_tsv"

    alter table(:messages) do
      remove :search_text
    end
  end
end
