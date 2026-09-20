defmodule Xamt.Servers.ServerMember do
  use Ecto.Schema
  import Ecto.Changeset

  alias Xamt.Servers.Permissions

  @roles ~w(owner admin member)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "server_members" do
    field :role, :string
    field :nickname, :string
    field :joined_at, :utc_datetime
    field :permissions, :integer, default: Permissions.default_member_perms()

    belongs_to :server, Xamt.Servers.Server
    belongs_to :user, Xamt.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:server_id, :user_id, :role, :nickname, :joined_at])
    |> validate_required([:server_id, :user_id, :role, :joined_at])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:server_id, :user_id])
    |> put_role_permissions()
  end

  @doc """
  Writes a raw bitmask. Used for custom grants; role presets go through `changeset/2`.
  """
  def permissions_changeset(member, permissions) when is_integer(permissions) do
    member
    |> change()
    |> put_change(:permissions, permissions)
    |> validate_number(:permissions, greater_than_or_equal_to: 0)
  end

  defp put_role_permissions(changeset) do
    case get_change(changeset, :role) do
      nil -> changeset
      role -> put_change(changeset, :permissions, Permissions.for_role(role))
    end
  end
end
