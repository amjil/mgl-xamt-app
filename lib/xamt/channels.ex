defmodule Xamt.Channels do
  @moduledoc """
  Channels within servers.
  """

  import Ecto.Query, warn: false

  alias Xamt.Repo
  alias Xamt.Servers.Server
  alias Xamt.Channels.Channel
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
end
