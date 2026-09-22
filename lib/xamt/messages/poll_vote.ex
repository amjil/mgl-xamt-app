defmodule Xamt.Messages.PollVote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "poll_votes" do
    belongs_to :poll, Xamt.Messages.Poll
    belongs_to :poll_option, Xamt.Messages.PollOption
    belongs_to :user, Xamt.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:poll_id, :poll_option_id, :user_id])
    |> validate_required([:poll_id, :poll_option_id, :user_id])
    |> unique_constraint([:poll_option_id, :user_id])
  end
end
