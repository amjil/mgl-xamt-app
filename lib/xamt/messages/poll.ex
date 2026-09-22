defmodule Xamt.Messages.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "polls" do
    field :question, :string
    field :allow_multiple, :boolean, default: false
    field :results_open, :boolean, default: true

    belongs_to :message, Xamt.Messages.Message
    has_many :poll_options, Xamt.Messages.PollOption
    has_many :poll_votes, Xamt.Messages.PollVote

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(poll, attrs) do
    poll
    |> cast(attrs, [:message_id, :question, :allow_multiple, :results_open])
    |> validate_required([:message_id, :question])
    |> validate_length(:question, min: 1, max: 280)
    |> unique_constraint(:message_id)
  end
end
