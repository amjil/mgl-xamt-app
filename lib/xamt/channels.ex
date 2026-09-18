defmodule Xamt.Channels do
  @moduledoc """
  Channels within servers.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Repo
  alias Xamt.Servers
  alias Xamt.Servers.Server
  alias Xamt.Channels.{Channel, ChannelRead, LastMessageCache}
  alias Xamt.Slug

  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    channel
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :type, :position])
  end

  @doc """
  Creates a channel on behalf of a user. Only server admins and owners may.
  """
  def create_channel(%Scope{user: user}, %Server{} = server, attrs) when is_map(attrs) do
    if Servers.admin?(server.id, user.id) do
      create_channel(server, attrs)
    else
      {:error, :unauthorized}
    end
  end

  def update_channel(%Scope{user: user}, channel_id, attrs) when is_map(attrs) do
    channel = get_channel!(channel_id)

    if Servers.admin?(channel.server_id, user.id) do
      name = Map.get(attrs, "name") || Map.get(attrs, :name)

      channel
      |> Channel.changeset(%{
        server_id: channel.server_id,
        name: name,
        slug: Map.get(attrs, "slug") || Map.get(attrs, :slug) || Slug.slugify(name),
        type: Map.get(attrs, "type") || Map.get(attrs, :type) || channel.type
      })
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def delete_channel(%Scope{user: user}, channel_id) do
    channel = get_channel!(channel_id)

    cond do
      not Servers.admin?(channel.server_id, user.id) ->
        {:error, :unauthorized}

      last_channel?(channel.server_id) ->
        {:error, :last_channel}

      true ->
        with {:ok, channel} <- Repo.delete(channel) do
          LastMessageCache.delete(channel.id)
          {:ok, channel}
        end
    end
  end

  @doc """
  Moves a channel one slot up or down, renumbering positions to stay dense.
  """
  def move_channel(%Scope{user: user}, channel_id, direction) when direction in [:up, :down] do
    channel = get_channel!(channel_id)

    if Servers.admin?(channel.server_id, user.id) do
      ordered = list_channels(channel.server_id)
      index = Enum.find_index(ordered, &(&1.id == channel.id))
      target = if direction == :up, do: index - 1, else: index + 1

      if target < 0 or target >= length(ordered) do
        {:ok, ordered}
      else
        ordered
        |> swap(index, target)
        |> persist_positions()
      end
    else
      {:error, :unauthorized}
    end
  end

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)

    list
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end

  defp persist_positions(ordered) do
    Repo.transact(fn ->
      ordered
      |> Enum.with_index()
      |> Enum.each(fn {channel, position} ->
        from(c in Channel, where: c.id == ^channel.id)
        |> Repo.update_all(set: [position: position])
      end)

      {:ok, ordered}
    end)
  end

  defp last_channel?(server_id) do
    Repo.aggregate(from(c in Channel, where: c.server_id == ^server_id), :count) <= 1
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
  Returns channel IDs in the server that have unread messages.

  Uses ETS last-message cache instead of scanning the messages table.
  """
  def get_unread_channel_ids(user_id, server_id)
      when is_binary(user_id) and is_binary(server_id) do
    channel_ids =
      from(c in Channel, where: c.server_id == ^server_id, select: c.id)
      |> Repo.all()

    if channel_ids == [] do
      []
    else
      reads =
        from(cr in ChannelRead,
          where: cr.user_id == ^user_id and cr.channel_id in ^channel_ids,
          select: {cr.channel_id, cr.last_read_message_id}
        )
        |> Repo.all()
        |> Map.new()

      Enum.filter(channel_ids, fn cid ->
        latest_msg_id = LastMessageCache.get(cid)
        last_read_id = Map.get(reads, cid)

        cond do
          is_nil(latest_msg_id) -> false
          is_nil(last_read_id) -> true
          latest_msg_id != last_read_id -> true
          true -> false
        end
      end)
    end
  end
end
