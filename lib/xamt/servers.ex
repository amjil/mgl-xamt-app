defmodule Xamt.Servers do
  @moduledoc """
  Servers and membership.
  """

  import Ecto.Query, warn: false
  import Xamt.Servers.Permissions, only: [has_perm: 2]

  alias Xamt.Accounts.{Scope, User}
  alias Xamt.Channels
  alias Xamt.Channels.ChannelListCache
  alias Xamt.Repo
  alias Xamt.Slug
  alias Xamt.Servers.{Invite, Server, ServerCache, ServerMember, Permissions}

  @default_channel_name "general"
  @invite_code_bytes 9

  def change_server(%Server{} = server, attrs \\ %{}) do
    server
    |> Ecto.Changeset.cast(attrs, [:name, :slug, :description, :icon, :visibility])
    |> maybe_slugify_slug()
    |> Ecto.Changeset.validate_length(:name, max: 100)
    |> Ecto.Changeset.validate_length(:slug, max: 100)
    |> validate_slug_format()
    |> Ecto.Changeset.validate_inclusion(:visibility, Server.visibilities())
  end

  defp maybe_slugify_slug(changeset) do
    case Ecto.Changeset.get_change(changeset, :slug) do
      slug when is_binary(slug) ->
        if String.trim(slug) == "" do
          changeset
        else
          Ecto.Changeset.put_change(changeset, :slug, Slug.slugify(slug))
        end

      _ ->
        changeset
    end
  end

  defp validate_slug_format(changeset) do
    case Ecto.Changeset.get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        Ecto.Changeset.validate_format(
          changeset,
          :slug,
          ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
          message: "must use lowercase letters, numbers, and hyphens"
        )

      _ ->
        changeset
    end
  end

  @doc """
  Creates a server. Only users with a global role of `admin` or `creator` may call this.
  """
  def create_server(%Scope{user: user} = scope, attrs) when is_map(attrs) do
    if User.can_create_server?(user) do
      insert_server(scope, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp insert_server(%Scope{user: user}, attrs) do
    name = Map.get(attrs, "name") || Map.get(attrs, :name)
    slug = unique_server_slug(requested_slug(attrs, name))

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
           {:ok, channel} <-
             Channels.create_channel(server, %{
               name: @default_channel_name,
               slug: Slug.slugify(@default_channel_name),
               type: "text",
               position: 0
             }) do
        ServerCache.put(server)
        ChannelListCache.put(server.id, [channel])
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
      select: %{s | viewer_permissions: m.permissions}
    )
    |> Repo.all()
    |> Repo.preload(:channels)
  end

  def get_server!(id) do
    case ServerCache.get(id) do
      %Server{} = server ->
        server

      nil ->
        server = Repo.get!(Server, id)
        ServerCache.put(server)
        server
    end
  end

  @doc """
  Fetches a server by slug, preferring the ETS `ServerCache`.

  Does not preload associations — members and channels are loaded separately
  on the LiveView hot path.
  """
  def get_server_by_slug!(slug) when is_binary(slug) do
    case ServerCache.get_by_slug(slug) do
      %Server{} = server ->
        server

      nil ->
        server = Repo.get_by!(Server, slug: slug)
        ServerCache.put(server)
        server
    end
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

    if can?(server.id, user.id, :manage_server) do
      old_slug = server.slug

      case server
           |> Server.changeset(Map.put(normalize_attrs(attrs), "owner_id", server.owner_id))
           |> Repo.update() do
        {:ok, updated} ->
          ServerCache.put(updated, old_slug: old_slug)
          {:ok, updated}

        other ->
          other
      end
    else
      {:error, :unauthorized}
    end
  end

  ## Invites

  def create_invite(%Scope{user: user}, server_id, attrs \\ %{}) do
    if can?(server_id, user.id, :manage_server) do
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

    if can?(invite.server_id, user.id, :manage_server) do
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
  Members whose username or display name contains `query`.

  An empty query returns the earliest members of the server, used for the
  mention picker right after `@`.
  """
  def search_members(server_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 8)
    q = query |> to_string() |> String.trim()

    base =
      from(m in ServerMember,
        join: u in assoc(m, :user),
        where: m.server_id == ^server_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        preload: [user: u]
      )

    query =
      if q == "" do
        base
      else
        from([m, u] in base,
          where:
            fragment("strpos(lower(?), lower(?)) > 0", u.username, ^q) or
              fragment("strpos(lower(coalesce(?, '')), lower(?)) > 0", u.display_name, ^q)
        )
      end

    Repo.all(query)
  end

  @doc """
  Members of `server_id` whose bitmask includes `perm`.

  Filters in PostgreSQL with `&` so only matching rows are loaded.
  """
  def list_members_with_perm(server_id, perm) when is_atom(perm) do
    flag = Permissions.flag!(perm)

    from(sm in ServerMember,
      where: sm.server_id == ^server_id,
      where: fragment("(? & ?) = ?", sm.permissions, ^flag, ^flag),
      order_by: [asc: sm.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc "Members who can kick others — typical moderators."
  def list_moderators(server_id) do
    ServerMember
    |> where([sm], sm.server_id == ^server_id)
    |> where([sm], has_perm(sm.permissions, :kick_members))
    |> order_by([sm], asc: sm.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Removes a member. Owners cannot be kicked, and only the owner may kick an admin.
  Requires `:kick_members` on the actor.
  """
  def kick_member(%Scope{user: actor}, server_id, user_id) do
    with :ok <- authorize_kick(server_id, actor.id, user_id),
         %ServerMember{} = member <- get_member(server_id, user_id) do
      Repo.delete(member)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def change_role(%Scope{user: actor}, server_id, user_id, role) when role in ~w(admin member) do
    with :ok <- authorize_role_change(server_id, actor.id, user_id),
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

  def grant_permission(%Scope{user: actor}, server_id, user_id, perm) do
    update_member_permissions(actor.id, server_id, user_id, &Permissions.grant(&1, perm))
  end

  def revoke_permission(%Scope{user: actor}, server_id, user_id, perm) do
    update_member_permissions(actor.id, server_id, user_id, &Permissions.revoke(&1, perm))
  end

  defp update_member_permissions(actor_id, server_id, user_id, fun) do
    with :ok <- require_perm(server_id, actor_id, :manage_server),
         %ServerMember{} = member <- get_member(server_id, user_id) do
      member
      |> ServerMember.permissions_changeset(fun.(member.permissions))
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_kick(server_id, actor_id, target_id) do
    with :ok <- require_perm(server_id, actor_id, :kick_members) do
      authorize_member_hierarchy(server_id, actor_id, target_id)
    end
  end

  defp authorize_role_change(server_id, actor_id, target_id) do
    with :ok <- require_perm(server_id, actor_id, :manage_server) do
      authorize_member_hierarchy(server_id, actor_id, target_id)
    end
  end

  defp authorize_member_hierarchy(server_id, actor_id, target_id) do
    target = get_member(server_id, target_id)

    cond do
      actor_id == target_id -> {:error, :unauthorized}
      match?(%ServerMember{role: "owner"}, target) -> {:error, :unauthorized}
      owner?(server_id, actor_id) -> :ok
      match?(%ServerMember{role: "admin"}, target) -> {:error, :unauthorized}
      true -> :ok
    end
  end

  defp require_perm(server_id, user_id, perm) do
    if can?(server_id, user_id, perm), do: :ok, else: {:error, :unauthorized}
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

  @doc "True when the member's bitmask includes `perm`."
  def can?(server_id, user_id, perm) when is_atom(perm) do
    case get_member(server_id, user_id) do
      %ServerMember{permissions: perms} -> Permissions.has_permission?(perms, perm)
      _ -> false
    end
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

  defp requested_slug(attrs, name) do
    case present_slug(Map.get(attrs, "slug") || Map.get(attrs, :slug)) do
      nil -> Slug.slugify(name)
      slug -> Slug.slugify(slug)
    end
  end

  defp present_slug(slug) when is_binary(slug) do
    case String.trim(slug) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_slug(_), do: nil

  defp unique_server_slug(slug, attempt \\ 0) do
    candidate = if attempt == 0, do: slug, else: "#{slug}-#{attempt}"

    if Repo.exists?(from s in Server, where: s.slug == ^candidate) do
      unique_server_slug(slug, attempt + 1)
    else
      candidate
    end
  end
end
