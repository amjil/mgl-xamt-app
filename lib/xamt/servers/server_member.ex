defmodule Xamt.Servers.ServerMember do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner admin member)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "server_members" do
    field :role, :string
    field :nickname, :string
    field :joined_at, :utc_datetime

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
  end
end
