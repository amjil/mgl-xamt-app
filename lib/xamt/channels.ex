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
  Advances the user's read watermark for a channel.

  Only moves forward: a concurrent or out-of-order mark with an older
  `message_inserted_at` will not regress the watermark.
  """
  def mark_as_read(user_id, channel_id, message_id, message_inserted_at)
      when is_binary(user_id) and is_binary(channel_id) and is_binary(message_id) do
    inserted_at = normalize_datetime(message_inserted_at)
    now = DateTime.utc_now(:second)

    %ChannelRead{}
    |> ChannelRead.changeset(%{
      user_id: user_id,
      channel_id: channel_id,
      last_read_message_id: message_id,
      last_read_at: inserted_at
    })
    |> Repo.insert(
      on_conflict:
        from(cr in ChannelRead,
          update: [
            set: [
              last_read_message_id: fragment("EXCLUDED.last_read_message_id"),
              last_read_at: fragment("EXCLUDED.last_read_at"),
              updated_at: ^now
            ]
          ],
          where: is_nil(cr.last_read_at) or cr.last_read_at < fragment("EXCLUDED.last_read_at")
        ),
      conflict_target: [:user_id, :channel_id]
    )
  end

  @doc """
  Deprecated name — prefer `mark_as_read/4`.
  """
  def mark_channel_as_read(user_id, channel_id, message_id, message_inserted_at \\ nil)

  def mark_channel_as_read(user_id, channel_id, message_id, nil)
      when is_binary(user_id) and is_binary(channel_id) and is_binary(message_id) do
    case Repo.get(Xamt.Messages.Message, message_id) do
      %{inserted_at: inserted_at} ->
        mark_as_read(user_id, channel_id, message_id, inserted_at)

      nil ->
        {:error, :not_found}
    end
  end

  def mark_channel_as_read(user_id, channel_id, message_id, message_inserted_at)
      when is_binary(user_id) and is_binary(channel_id) and is_binary(message_id) do
    mark_as_read(user_id, channel_id, message_id, message_inserted_at)
  end

  @doc """
  Lists channels for a server with a virtual `has_unread` flag for the user.
  """
  def list_channels_with_unread_status(server_id, user_id)
      when is_binary(server_id) and is_binary(user_id) do
    unread_ids = MapSet.new(get_unread_channel_ids(user_id, server_id))

    server_id
    |> list_channels()
    |> Enum.map(fn channel ->
      %{channel | has_unread: MapSet.member?(unread_ids, channel.id)}
    end)
  end

  @doc """
  Returns channel IDs in the server that have unread messages.

  Compares ETS-cached latest message timestamps against each user's watermark.
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
          select: {cr.channel_id, cr.last_read_at}
        )
        |> Repo.all()
        |> Map.new()

      Enum.filter(channel_ids, fn cid ->
        case LastMessageCache.get(cid) do
          nil ->
            false

          {_latest_id, latest_at} ->
            case Map.get(reads, cid) do
              nil -> true
              last_read_at -> DateTime.compare(latest_at, last_read_at) == :gt
            end
        end
      end)
    end
  end

  defp normalize_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp normalize_datetime(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} ->
        DateTime.truncate(dt, :second)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(iso) do
          {:ok, ndt} -> normalize_datetime(ndt)
          {:error, _} -> DateTime.utc_now(:second)
        end
    end
  end
end
