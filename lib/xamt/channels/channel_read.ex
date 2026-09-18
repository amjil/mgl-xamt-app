defmodule Xamt.Channels.ChannelRead do
  @moduledoc """
  Per-user per-channel read watermark.

  `last_read_at` mirrors the message's `inserted_at` so unread can be decided
  without relying on UUIDv4 message id ordering.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_reads" do
    belongs_to :user, Xamt.Accounts.User
    belongs_to :channel, Xamt.Channels.Channel
    belongs_to :last_read_message, Xamt.Messages.Message

    field :last_read_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(channel_read, attrs) do
    channel_read
    |> cast(attrs, [:user_id, :channel_id, :last_read_message_id, :last_read_at])
    |> validate_required([:user_id, :channel_id, :last_read_message_id, :last_read_at])
    |> unique_constraint([:user_id, :channel_id])
  end
end
