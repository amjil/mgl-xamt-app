defmodule Xamt.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  @visibilities ~w(public private)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "servers" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :icon, :string
    field :visibility, :string, default: "private"
    field :viewer_permissions, :integer, virtual: true

    belongs_to :owner, Xamt.Accounts.User, foreign_key: :owner_id
    has_many :members, Xamt.Servers.ServerMember
    has_many :channels, Xamt.Channels.Channel
    has_many :invites, Xamt.Servers.Invite

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def public?(%__MODULE__{visibility: "public"}), do: true
  def public?(_), do: false

  @doc false
  def changeset(server, attrs) do
    server
    |> cast(attrs, [:owner_id, :name, :slug, :description, :icon, :visibility])
    |> update_change(:slug, &Xamt.Slug.slugify/1)
    |> validate_required([:owner_id, :name, :slug])
    |> validate_length(:name, max: 100)
    |> validate_length(:slug, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint(:slug)
  end
end
