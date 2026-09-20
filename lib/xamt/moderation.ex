defmodule Xamt.Moderation do
  @moduledoc """
  Server-level moderation records.

  Writes go through the calling context's `Ecto.Multi` so the business change
  and the audit row commit atomically. This module is the read side.
  """

  import Ecto.Query, warn: false

  alias Xamt.Repo
  alias Xamt.Moderation.AuditLog

  def list_audit_logs(server_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(l in AuditLog,
      where: l.server_id == ^server_id,
      order_by: [desc: l.inserted_at, desc: l.id],
      limit: ^limit,
      preload: [:actor, :target_user]
    )
    |> Repo.all()
  end

  def list_audit_logs_for_resource(server_id, resource_id) when is_binary(resource_id) do
    from(l in AuditLog,
      where: l.server_id == ^server_id and l.target_resource_id == ^resource_id,
      order_by: [desc: l.inserted_at, desc: l.id],
      preload: [:actor, :target_user]
    )
    |> Repo.all()
  end
end
