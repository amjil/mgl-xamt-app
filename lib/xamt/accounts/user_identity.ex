defmodule Xamt.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  alias Xamt.Accounts.User
  alias Xamt.MglId

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_identities" do
    field :provider, :string
    field :issuer, :string
    field :subject, :string
    field :provider_username, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:user_id, :provider, :issuer, :subject, :provider_username])
    |> validate_required([:user_id, :provider, :issuer, :subject])
    |> update_change(:issuer, &trim_trailing_slash/1)
    |> validate_length(:provider, max: 50)
    |> validate_length(:provider_username, max: 255)
    |> unique_constraint([:provider, :issuer, :subject],
      name: :user_identities_provider_issuer_subject_index
    )
    |> unique_constraint([:user_id, :provider], name: :user_identities_user_provider_index)
    |> foreign_key_constraint(:user_id)
  end

  def mgl_attrs(user_id, claims) when is_map(claims) do
    issuer =
      Map.get(claims, "iss")
      |> to_string()
      |> trim_trailing_slash()

    %{
      user_id: user_id,
      provider: MglId.provider(),
      issuer: issuer,
      subject: claims["sub"],
      provider_username: claims["preferred_username"]
    }
  end

  defp trim_trailing_slash(nil), do: nil

  defp trim_trailing_slash(value) when is_binary(value) do
    String.trim_trailing(value, "/")
  end
end
