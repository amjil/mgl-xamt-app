defmodule Xamt.Repo.Migrations.AddPermissionsToServerMembers do
  use Ecto.Migration

  import Bitwise

  # Keep these in lockstep with `Xamt.Servers.Permissions` at the time of this
  # migration. Bit 0 = view_channel, bit 1 = send_messages, bits 2-6 = staff.
  @member_perms 1 <<< 0 ||| 1 <<< 1
  @staff_perms @member_perms ||| 1 <<< 2 ||| 1 <<< 3 ||| 1 <<< 4 ||| 1 <<< 5 |||
                 1 <<< 6

  def change do
    alter table(:server_members) do
      add :permissions, :bigint, null: false, default: @member_perms
    end

    execute(
      """
      UPDATE server_members
      SET permissions = #{@staff_perms}
      WHERE role IN ('owner', 'admin')
      """,
      "UPDATE server_members SET permissions = #{@member_perms}"
    )
  end
end
