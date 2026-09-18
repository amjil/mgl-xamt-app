defmodule Xamt.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "servers" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :icon, :string

    belongs_to :owner, Xamt.Accounts.User, foreign_key: :owner_id
    has_many :members, Xamt.Servers.ServerMember
    has_many :channels, Xamt.Channels.Channel

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(server, attrs) do
    server
    |> cast(attrs, [:owner_id, :name, :slug, :description, :icon])
    |> validate_required([:owner_id, :name, :slug])
    |> validate_length(:name, max: 100)
    |> validate_length(:slug, max: 100)
    |> unique_constraint(:slug)
  end
end
