defmodule Xamt.Messages.PollOption do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "poll_options" do
    field :text, :string
    field :votes_count, :integer, default: 0
    field :position, :integer, default: 0

    belongs_to :poll, Xamt.Messages.Poll
    has_many :poll_votes, Xamt.Messages.PollVote
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:poll_id, :text, :position, :votes_count])
    |> validate_required([:poll_id, :text, :position])
    |> validate_length(:text, min: 1, max: 120)
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
