defmodule Xamt.Bots.Bot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bots" do
    field :name, :string
    field :avatar_url, :string
    field :description, :string
    field :webhook_url, :string
    field :signing_secret, :string
    field :requested_scopes, {:array, :string}, default: []
    field :status, :string, default: "active"

    belongs_to :creator, Xamt.Accounts.User
    belongs_to :bot_user, Xamt.Accounts.User

    has_many :installations, Xamt.Bots.BotInstallation
    has_many :commands, Xamt.Bots.BotCommand

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(bot, attrs) do
    bot
    |> cast(attrs, [
      :name,
      :avatar_url,
      :description,
      :webhook_url,
      :requested_scopes,
      :status,
      :creator_id,
      :bot_user_id
    ])
    |> validate_required([:name, :webhook_url, :creator_id, :bot_user_id])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_inclusion(:status, ["active", "suspended", "draft"])
    |> put_signing_secret()
  end

  defp put_signing_secret(changeset) do
    if get_field(changeset, :signing_secret) do
      changeset
    else
      secret = "whsec_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      put_change(changeset, :signing_secret, secret)
    end
  end
end
