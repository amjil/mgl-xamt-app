defmodule Xamt.Messages.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "messages" do
    field :content, :map, default: %{}
    field :content_type, :string, default: "rich_text"
    field :content_html, :string
    field :deleted_at, :utc_datetime

    belongs_to :channel, Xamt.Channels.Channel
    belongs_to :user, Xamt.Accounts.User
    belongs_to :reply_to, Xamt.Messages.Message, foreign_key: :reply_to_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:channel_id, :user_id, :content, :content_type, :content_html, :reply_to_id])
    |> validate_required([:channel_id, :user_id, :content])
    |> validate_inclusion(:content_type, ~w(plain_text rich_text))
  end

  @doc false
  def delete_changeset(message) do
    change(message, deleted_at: DateTime.utc_now(:second))
  end
end
