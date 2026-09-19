defmodule Xamt.Messages.Mention do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "message_mentions" do
    belongs_to :message, Xamt.Messages.Message
    belongs_to :user, Xamt.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:message_id, :user_id])
    |> validate_required([:message_id, :user_id])
    |> unique_constraint([:message_id, :user_id])
  end
end
