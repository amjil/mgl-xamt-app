defmodule Xamt.Servers do
  @moduledoc """
  Servers and membership.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Channels
  alias Xamt.Repo
  alias Xamt.Slug
  alias Xamt.Servers.{Server, ServerMember}

  @default_channel_name "general"

  def change_server(%Server{} = server, attrs \\ %{}) do
    server
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :description, :icon])
  end

  def create_server(%Scope{user: user}, attrs) when is_map(attrs) do
    name = Map.get(attrs, "name") || Map.get(attrs, :name)
    base_slug = Map.get(attrs, "slug") || Map.get(attrs, :slug) || Slug.slugify(name)
    slug = unique_server_slug(base_slug)

    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      with {:ok, server} <-
             %Server{}
             |> Server.changeset(%{
               owner_id: user.id,
               name: name,
               slug: slug,
               description: Map.get(attrs, "description") || Map.get(attrs, :description),
               icon: Map.get(attrs, "icon") || Map.get(attrs, :icon)
             })
             |> Repo.insert(),
           {:ok, _member} <-
             %ServerMember{}
             |> ServerMember.changeset(%{
               server_id: server.id,
               user_id: user.id,
               role: "owner",
               joined_at: now
             })
             |> Repo.insert(),
           {:ok, _channel} <-
             Channels.create_channel(server, %{
               name: @default_channel_name,
               slug: Slug.slugify(@default_channel_name),
               type: "text",
               position: 0
             }) do
        {:ok, get_server!(server.id)}
      end
    end)
  end

  def list_servers_for_user(%Scope{user: user}) do
    from(s in Server,
      join: m in ServerMember,
      on: m.server_id == s.id,
      where: m.user_id == ^user.id,
      order_by: [asc: s.name],
      preload: [:channels]
    )
    |> Repo.all()
  end

  def get_server!(id), do: Repo.get!(Server, id) |> Repo.preload([:channels, :members])

  def get_server_by_slug!(slug) when is_binary(slug) do
    Repo.get_by!(Server, slug: slug) |> Repo.preload([:channels, :members])
  end

  def join_server(%Scope{user: user}, server_id) do
    server = get_server!(server_id)

    if member?(server.id, user.id) do
      {:error, :already_member}
    else
      now = DateTime.utc_now(:second)

      %ServerMember{}
      |> ServerMember.changeset(%{
        server_id: server.id,
        user_id: user.id,
        role: "member",
        joined_at: now
      })
      |> Repo.insert()
    end
  end

  def list_members(server_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(m in ServerMember,
      where: m.server_id == ^server_id,
      order_by: [asc: m.inserted_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:user]
    )
    |> Repo.all()
  end

  def member?(server_id, user_id) do
    Repo.exists?(
      from m in ServerMember,
        where: m.server_id == ^server_id and m.user_id == ^user_id
    )
  end

  def get_member(server_id, user_id) do
    Repo.get_by(ServerMember, server_id: server_id, user_id: user_id)
  end

  def owner?(server_id, user_id) do
    match?(%ServerMember{role: "owner"}, get_member(server_id, user_id))
  end

  def admin?(server_id, user_id) do
    match?(
      %ServerMember{role: role} when role in ["owner", "admin"],
      get_member(server_id, user_id)
    )
  end

  defp unique_server_slug(slug, attempt \\ 0) do
    candidate = if attempt == 0, do: slug, else: "#{slug}-#{attempt}"

    if Repo.exists?(from s in Server, where: s.slug == ^candidate) do
      unique_server_slug(slug, attempt + 1)
    else
      candidate
    end
  end
end
