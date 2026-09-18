defmodule Xamt.Servers do
  @moduledoc """
  Servers and membership.
  """

  import Ecto.Query, warn: false

  alias Xamt.Accounts.Scope
  alias Xamt.Channels
  alias Xamt.Repo
  alias Xamt.Slug
  alias Xamt.Servers.{Invite, Server, ServerMember}

  @default_channel_name "general"
  @invite_code_bytes 9

  def change_server(%Server{} = server, attrs \\ %{}) do
    server
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :description, :icon, :visibility])
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
               icon: Map.get(attrs, "icon") || Map.get(attrs, :icon),
               visibility:
                 Map.get(attrs, "visibility") || Map.get(attrs, :visibility) || "private"
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

  @doc """
  Public servers the user has not joined yet, for discovery on the home page.
  """
  def list_discoverable_servers(%Scope{user: user}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    joined =
      from(m in ServerMember, where: m.user_id == ^user.id, select: m.server_id)

    from(s in Server,
      where: s.visibility == "public" and s.id not in subquery(joined),
      order_by: [asc: s.name],
      limit: ^limit
    )
    |> Repo.all()
  end

  def update_server(%Scope{user: user}, server_id, attrs) do
    server = get_server!(server_id)

    if admin?(server.id, user.id) do
      server
      |> Server.changeset(Map.put(normalize_attrs(attrs), "owner_id", server.owner_id))
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  ## Invites

  def create_invite(%Scope{user: user}, server_id, attrs \\ %{}) do
    if admin?(server_id, user.id) do
      %Invite{}
      |> Invite.changeset(%{
        server_id: server_id,
        created_by_id: user.id,
        code: generate_invite_code(),
        expires_at: Map.get(attrs, "expires_at") || Map.get(attrs, :expires_at),
        max_uses: Map.get(attrs, "max_uses") || Map.get(attrs, :max_uses)
      })
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def list_invites(server_id) do
    from(i in Invite, where: i.server_id == ^server_id, order_by: [desc: i.inserted_at])
    |> Repo.all()
  end

  def get_invite_by_code(code) when is_binary(code) do
    Repo.get_by(Invite, code: code) |> Repo.preload(:server)
  end

  def delete_invite(%Scope{user: user}, invite_id) do
    invite = Repo.get!(Invite, invite_id)

    if admin?(invite.server_id, user.id) do
      Repo.delete(invite)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Joins the server behind an invite code and counts the use.

  Returns `{:ok, server}`, or `{:error, :not_found | :invalid}`.
  """
  def redeem_invite(%Scope{} = scope, code) when is_binary(code) do
    case get_invite_by_code(code) do
      nil ->
        {:error, :not_found}

      invite ->
        cond do
          not Invite.usable?(invite) ->
            {:error, :invalid}

          member?(invite.server_id, scope.user.id) ->
            {:ok, invite.server}

          true ->
            Repo.transact(fn ->
              with {:ok, _member} <- join_server(scope, invite.server_id),
                   {1, _} <- bump_invite_uses(invite.id) do
                {:ok, invite.server}
              else
                {:error, reason} -> {:error, reason}
                _ -> {:error, :invalid}
              end
            end)
        end
    end
  end

  defp bump_invite_uses(invite_id) do
    from(i in Invite, where: i.id == ^invite_id)
    |> Repo.update_all(inc: [uses: 1])
  end

  defp generate_invite_code do
    @invite_code_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
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

  @doc """
  Removes a member. Owners cannot be kicked, and admins cannot kick each other.
  """
  def kick_member(%Scope{user: actor}, server_id, user_id) do
    with :ok <- authorize_member_change(server_id, actor.id, user_id),
         %ServerMember{} = member <- get_member(server_id, user_id) do
      Repo.delete(member)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def change_role(%Scope{user: actor}, server_id, user_id, role) when role in ~w(admin member) do
    with :ok <- authorize_member_change(server_id, actor.id, user_id),
         %ServerMember{} = member <- get_member(server_id, user_id) do
      member
      |> ServerMember.changeset(%{
        server_id: member.server_id,
        user_id: member.user_id,
        role: role,
        joined_at: member.joined_at
      })
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_member_change(server_id, actor_id, target_id) do
    target = get_member(server_id, target_id)

    cond do
      actor_id == target_id -> {:error, :unauthorized}
      not admin?(server_id, actor_id) -> {:error, :unauthorized}
      match?(%ServerMember{role: "owner"}, target) -> {:error, :unauthorized}
      owner?(server_id, actor_id) -> :ok
      match?(%ServerMember{role: "admin"}, target) -> {:error, :unauthorized}
      true -> :ok
    end
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
