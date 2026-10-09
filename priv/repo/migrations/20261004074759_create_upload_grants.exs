defmodule Xamt.Repo.Migrations.CreateUploadGrants do
  use Ecto.Migration

  def change do
    create table(:upload_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :filename, :string, null: false

      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:upload_grants, [:filename])
    create index(:upload_grants, [:server_id])

    execute(&backfill_upload_grants/0, fn -> :ok end)
  end

  # Earliest remaining message wins, so a later quote of the same filename
  # cannot take the grant away from the server that first stored it.
  defp backfill_upload_grants do
    flush()

    repo().query!("""
    INSERT INTO upload_grants (id, filename, server_id, user_id, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      filename,
      server_id,
      user_id,
      (now() AT TIME ZONE 'utc'),
      (now() AT TIME ZONE 'utc')
    FROM (
      SELECT DISTINCT ON (filename)
        filename,
        server_id,
        user_id
      FROM (
        SELECT
          substring(paths.path from '^/uploads/([A-Za-z0-9._-]+)$') AS filename,
          c.server_id,
          m.user_id,
          m.inserted_at
        FROM messages m
        INNER JOIN channels c ON c.id = m.channel_id
        CROSS JOIN LATERAL (
          SELECT img.value->>'original' AS path
          FROM jsonb_array_elements(
            CASE
              WHEN jsonb_typeof(m.content -> 'images') = 'array' THEN m.content -> 'images'
              ELSE '[]'::jsonb
            END
          ) AS img(value)
          UNION ALL
          SELECT img.value->>'thumb'
          FROM jsonb_array_elements(
            CASE
              WHEN jsonb_typeof(m.content -> 'images') = 'array' THEN m.content -> 'images'
              ELSE '[]'::jsonb
            END
          ) AS img(value)
          UNION ALL
          SELECT m.content->>'url'
        ) AS paths(path)
        WHERE m.deleted_at IS NULL
          AND m.user_id IS NOT NULL

        UNION ALL

        SELECT
          matched.groups[1] AS filename,
          c.server_id,
          m.user_id,
          m.inserted_at
        FROM messages m
        INNER JOIN channels c ON c.id = m.channel_id
        CROSS JOIN LATERAL regexp_matches(
          coalesce(m.content_html, ''),
          '/uploads/([A-Za-z0-9._-]+)',
          'g'
        ) AS matched(groups)
        WHERE m.deleted_at IS NULL
          AND m.user_id IS NOT NULL
      ) AS refs
      WHERE filename IS NOT NULL
        AND filename <> ''
        AND char_length(filename) <= 255
      ORDER BY filename, inserted_at ASC
    ) AS earliest
    """)
  end
end
