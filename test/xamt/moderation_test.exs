defmodule Xamt.ModerationTest do
  use Xamt.DataCase, async: true

  alias Xamt.Moderation.AuditLog

  test "requires server, actor, and a known action" do
    changeset = AuditLog.changeset(%AuditLog{}, %{})

    assert %{
             server_id: ["can't be blank"],
             actor_id: ["can't be blank"],
             action: ["can't be blank"]
           } =
             errors_on(changeset)
  end

  test "rejects unknown actions so the log stays queryable" do
    changeset =
      AuditLog.changeset(%AuditLog{}, %{
        server_id: Ecto.UUID.generate(),
        actor_id: Ecto.UUID.generate(),
        action: "not_a_real_action"
      })

    assert "is invalid" in errors_on(changeset).action
  end

  test "caps reason length" do
    changeset =
      AuditLog.changeset(%AuditLog{}, %{
        server_id: Ecto.UUID.generate(),
        actor_id: Ecto.UUID.generate(),
        action: "message_deleted",
        reason: String.duplicate("x", 501)
      })

    assert "should be at most 500 character(s)" in errors_on(changeset).reason
  end
end
