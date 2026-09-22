defmodule Xamt.Messages.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "messages" do
    field :content, :map, default: %{}
    field :content_type, :string, default: "rich_text"
    field :content_html, :string
    field :search_text, :string
    field :link_preview, :map
    field :deleted_at, :utc_datetime
    field :mentioned_user_ids, {:array, :binary_id}, virtual: true, default: []
    # In-memory grouping flag: consecutive same-author messages hide the header.
    field :show_header, :boolean, virtual: true, default: true

    belongs_to :channel, Xamt.Channels.Channel
    belongs_to :user, Xamt.Accounts.User
    belongs_to :reply_to, Xamt.Messages.Message, foreign_key: :reply_to_id
    has_many :mentions, Xamt.Messages.Mention

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :channel_id,
      :user_id,
      :content,
      :content_type,
      :content_html,
      :search_text,
      :reply_to_id
    ])
    |> validate_required([:channel_id, :user_id, :content])
    |> validate_inclusion(:content_type, ~w(plain_text rich_text audio gallery))
    |> touch_edited_at()
  end

  # `updated_at` is second-precision. A same-second edit would otherwise
  # compare equal to `inserted_at` and skip the "edited" marker.
  defp touch_edited_at(changeset) do
    case {changeset.data.id, get_change(changeset, :content_html)} do
      {id, html} when is_binary(id) and is_binary(html) ->
        inserted_at = changeset.data.inserted_at
        now = DateTime.utc_now(:second)

        updated_at =
          cond do
            is_nil(inserted_at) -> now
            DateTime.compare(now, inserted_at) == :gt -> now
            true -> DateTime.add(inserted_at, 1, :second)
          end

        put_change(changeset, :updated_at, updated_at)

      _ ->
        changeset
    end
  end

  @doc false
  def delete_changeset(message) do
    change(message, deleted_at: DateTime.utc_now(:second))
  end
end
