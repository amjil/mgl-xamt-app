defmodule Xamt.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(text announcement)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channels" do
    field :name, :string
    field :slug, :string
    field :type, :string, default: "text"
    field :position, :integer, default: 0
    field :has_unread, :boolean, virtual: true, default: false

    belongs_to :server, Xamt.Servers.Server
    has_many :messages, Xamt.Messages.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:server_id, :name, :slug, :type, :position])
    |> validate_required([:server_id, :name, :slug])
    |> validate_inclusion(:type, @types)
    |> unique_constraint(:slug, name: :channels_server_id_slug_index)
  end
end
