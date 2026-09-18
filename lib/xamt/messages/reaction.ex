defmodule Xamt.Messages.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  @emojis ~w(👍 ❤️ 😂 🎉)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "message_reactions" do
    field :emoji, :string

    belongs_to :message, Xamt.Messages.Message
    belongs_to :user, Xamt.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Emoji the first version allows, in display order."
  def emojis, do: @emojis

  @doc false
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:message_id, :user_id, :emoji])
    |> validate_required([:message_id, :user_id, :emoji])
    |> validate_inclusion(:emoji, @emojis)
    |> unique_constraint([:message_id, :user_id, :emoji])
  end
end
