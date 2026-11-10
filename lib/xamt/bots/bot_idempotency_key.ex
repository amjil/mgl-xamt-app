defmodule Xamt.Bots.BotIdempotencyKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_idempotency_keys" do
    field :nonce, :string

    belongs_to :bot_installation, Xamt.Bots.BotInstallation
    belongs_to :message, Xamt.Messages.Message

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, [:bot_installation_id, :nonce, :message_id])
    |> validate_required([:bot_installation_id, :nonce, :message_id])
    |> validate_length(:nonce, min: 1, max: 128)
    |> unique_constraint([:bot_installation_id, :nonce])
  end
end
