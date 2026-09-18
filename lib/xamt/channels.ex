defmodule Xamt.Channels do
  @moduledoc """
  Channels within servers.
  """

  import Ecto.Query, warn: false

  alias Xamt.Repo
  alias Xamt.Servers.Server
  alias Xamt.Channels.{Channel, ChannelRead}
  alias Xamt.Messages.Message
  alias Xamt.Slug

  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    channel
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :type, :position])
  end

  def create_channel(%Server{} = server, attrs) when is_map(attrs) do
    name = Map.get(attrs, "name") || Map.get(attrs, :name)
    slug = Map.get(attrs, "slug") || Map.get(attrs, :slug) || Slug.slugify(name)

    %Channel{}
    |> Channel.changeset(%{
      server_id: server.id,
      name: name,
      slug: slug,
      type: Map.get(attrs, "type") || Map.get(attrs, :type) || "text",
      position: Map.get(attrs, "position") || Map.get(attrs, :position) || 0
    })
    |> Repo.insert()
  end

  def list_channels(server_id) do
    from(c in Channel,
      where: c.server_id == ^server_id,
      order_by: [asc: c.position, asc: c.name]
    )
    |> Repo.all()
  end

  def get_channel!(id), do: Repo.get!(Channel, id)

  def get_channel_by_slug!(server_id, slug) when is_binary(slug) do
    Repo.get_by!(Channel, server_id: server_id, slug: slug)
  end

  @doc """
  Upserts the user's last-read message for a channel.
  """
  def mark_channel_as_read(user_id, channel_id, message_id)
      when is_binary(user_id) and is_binary(channel_id) and is_binary(message_id) do
    now = DateTime.utc_now(:second)

    %ChannelRead{}
    |> ChannelRead.changeset(%{
      user_id: user_id,
      channel_id: channel_id,
      last_read_message_id: message_id
    })
    |> Repo.insert(
      on_conflict: [set: [last_read_message_id: message_id, updated_at: now]],
      conflict_target: [:user_id, :channel_id]
    )
  end

  @doc """
  Returns channel IDs in the server that have messages newer than the user's last read.
  Channels the user has never opened are unread if they contain any messages.
  """
  def get_unread_channel_ids(user_id, server_id)
      when is_binary(user_id) and is_binary(server_id) do
    from(m in Message,
      join: c in Channel,
      on: c.id == m.channel_id and c.server_id == ^server_id,
      left_join: cr in ChannelRead,
      on: cr.channel_id == m.channel_id and cr.user_id == ^user_id,
      left_join: lr in Message,
      on: lr.id == cr.last_read_message_id,
      where:
        is_nil(m.deleted_at) and
          (is_nil(cr.id) or
             m.inserted_at > lr.inserted_at or
             (m.inserted_at == lr.inserted_at and m.id > lr.id)),
      distinct: true,
      select: m.channel_id
    )
    |> Repo.all()
  end
end
