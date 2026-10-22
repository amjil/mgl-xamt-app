defmodule Xamt.Bots.BotCommand do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bot_commands" do
    field :name, :string
    field :description, :string
    field :parameters_schema, {:array, :map}, default: []
    field :is_enabled, :boolean, default: true

    belongs_to :bot, Xamt.Bots.Bot

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(cmd, attrs) do
    cmd
    |> cast(attrs, [:bot_id, :name, :description, :parameters_schema, :is_enabled])
    |> validate_required([:bot_id, :name, :description])
  end
end
