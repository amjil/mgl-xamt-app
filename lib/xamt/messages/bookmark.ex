defmodule Xamt.Messages.Bookmark do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bookmarks" do
    field :note, :string

    belongs_to :user, Xamt.Accounts.User
    belongs_to :message, Xamt.Messages.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:user_id, :message_id, :note])
    |> validate_required([:user_id, :message_id])
    |> validate_length(:note, max: 200)
    |> unique_constraint([:user_id, :message_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:message_id)
  end
end
