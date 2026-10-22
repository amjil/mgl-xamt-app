defmodule Xamt.Bots.BotToken do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_tokens" do
    field :token_hash, :binary
    field :token_prefix, :string
    field :scopes, {:array, :string}, default: []
    field :last_used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :bot, Xamt.Bots.Bot
    belongs_to :bot_installation, Xamt.Bots.BotInstallation

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end
end
