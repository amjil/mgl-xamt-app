defmodule Xamt.Servers.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "server_invites" do
    field :code, :string
    field :expires_at, :utc_datetime
    field :max_uses, :integer
    field :uses, :integer, default: 0

    belongs_to :server, Xamt.Servers.Server
    belongs_to :created_by, Xamt.Accounts.User, foreign_key: :created_by_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:server_id, :created_by_id, :code, :expires_at, :max_uses])
    |> validate_required([:server_id, :created_by_id, :code])
    |> validate_number(:max_uses, greater_than: 0)
    |> unique_constraint(:code)
  end

  @doc """
  An invite is usable while it has not expired and has uses left.
  """
  def usable?(%__MODULE__{} = invite, now \\ DateTime.utc_now()) do
    not expired?(invite, now) and not exhausted?(invite)
  end

  defp expired?(%__MODULE__{expires_at: nil}, _now), do: false
  defp expired?(%__MODULE__{expires_at: at}, now), do: DateTime.compare(now, at) == :gt

  defp exhausted?(%__MODULE__{max_uses: nil}), do: false
  defp exhausted?(%__MODULE__{max_uses: max, uses: uses}), do: uses >= max
end
