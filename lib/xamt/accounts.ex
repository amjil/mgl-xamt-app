defmodule Xamt.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Xamt.Repo

  alias Xamt.Accounts.{Scope, User, UserIdentity, UserToken}
  alias Xamt.MglId

  ## Database getters

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Users matching `query` for a site admin.

  A blank query returns accounts ordered by username. A non-blank query
  treats each whitespace-separated token as a case-insensitive substring
  that must appear in the username or display name.
  """
  def search_users_as_admin(%Scope{user: %User{} = actor}, query \\ "", opts \\ []) do
    if User.admin?(actor) do
      {:ok, load_users_for_admin(query, opts)}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Returns a changeset for the admin edit-user form.
  """
  def change_user_admin_update(user, attrs \\ %{}, opts \\ []) do
    User.admin_update_changeset(
      user,
      attrs,
      opts
      |> Keyword.put_new(:validate_unique, false)
    )
  end

  @doc """
  Updates an account on behalf of a site admin.

  Independent of the public profile flow. The last
  remaining admin cannot be demoted.
  """
  def update_user_as_admin(%Scope{user: %User{} = actor}, %User{} = user, attrs)
      when is_map(attrs) do
    if User.admin?(actor) do
      user
      |> User.admin_update_changeset(attrs)
      |> maybe_protect_last_admin(user)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  defp maybe_protect_last_admin(changeset, %User{} = user) do
    new_role = Ecto.Changeset.get_field(changeset, :global_role)

    if User.admin?(user) and new_role != "admin" and admin_count() <= 1 do
      Ecto.Changeset.add_error(changeset, :global_role, "cannot remove the last admin")
    else
      changeset
    end
  end

  defp admin_count do
    Repo.aggregate(from(u in User, where: u.global_role == "admin"), :count)
  end

  defp load_users_for_admin(query, opts) do
    limit = Keyword.get(opts, :limit, 100)
    tokens = search_tokens(query)

    from(u in User, order_by: [asc: u.username], limit: ^limit)
    |> apply_user_search(tokens)
    |> Repo.all()
  end

  defp search_tokens(query) do
    query
    |> to_string()
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.trim_leading(&1, "@"))
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(5)
  end

  defp apply_user_search(query, []), do: query

  defp apply_user_search(query, tokens) do
    Enum.reduce(tokens, query, fn token, acc ->
      pattern = like_pattern(token)

      from(u in acc,
        where:
          ilike(u.username, ^pattern) or
            ilike(fragment("coalesce(?, '')", u.display_name), ^pattern)
      )
    end)
  end

  defp like_pattern(token) do
    escaped =
      token
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end

  @doc """
  Updates a user's profile.
  """
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking profile changes.
  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs, validate_unique: false)
  end

  @custom_status_presets [
    %{"emoji" => "💼", "text" => "Working"},
    %{"emoji" => "🔥", "text" => "Busy"},
    %{"emoji" => "🏖️", "text" => "On vacation"},
    %{"emoji" => "📅", "text" => "In a meeting"},
    %{"emoji" => "📚", "text" => "Studying"}
  ]

  @doc """
  Preset custom statuses for the picker UI.
  """
  def custom_status_presets, do: @custom_status_presets

  @doc """
  Updates a user's custom status (emoji + text).
  """
  def update_user_custom_status(user, attrs) do
    user
    |> User.custom_status_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking custom status changes.
  """
  def change_user_custom_status(user, attrs \\ %{}) do
    User.custom_status_changeset(user, attrs)
  end

  @doc """
  Assigns a global role from the operator console or seeds.

  Valid roles are `user`, `creator`, and `admin`.
  """
  def update_user_global_role(%User{} = user, global_role) when is_binary(global_role) do
    user
    |> User.admin_changeset(%{global_role: global_role})
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Revokes every session token for the user (log out all devices).
  """
  def revoke_all_user_sessions(%User{} = user) do
    {count, _} =
      Repo.delete_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "session")
      )

    {:ok, count}
  end

  ## Mgl ID identities

  @doc """
  Returns a `UserIdentity` with preloaded user for the given Mgl issuer + sub.
  """
  def get_user_by_mgl_identity(issuer, subject)
      when is_binary(issuer) and is_binary(subject) do
    issuer = String.trim_trailing(issuer, "/")

    from(i in UserIdentity,
      where: i.provider == ^MglId.provider() and i.issuer == ^issuer and i.subject == ^subject,
      preload: [:user]
    )
    |> Repo.one()
  end

  @doc """
  Returns the Mgl identity for a local user, or nil.
  """
  def get_mgl_identity(%User{id: user_id}) do
    Repo.get_by(UserIdentity, user_id: user_id, provider: MglId.provider())
  end

  @doc """
  Creates a local user and Mgl identity in one transaction from verified claims.

  Never matches existing users by username.
  """
  def provision_user_from_mgl(claims) when is_map(claims) do
    preferred = claims["preferred_username"] || claims["name"]
    display_name = normalize_display_name(claims["name"])

    if is_binary(claims["sub"]) and claims["sub"] != "" do
      Repo.transact(fn ->
        with {:ok, username} <- unique_username(preferred),
             {:ok, user} <-
               %User{}
               |> User.oidc_registration_changeset(%{
                 username: username,
                 display_name: display_name
               })
               |> Repo.insert(),
             {:ok, _identity} <- insert_mgl_identity(user, claims) do
          {:ok, user}
        else
          {:error, reason} -> {:error, reason}
        end
      end)
    else
      {:error, :missing_sub}
    end
  end

  defp normalize_display_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 100)
    end
  end

  defp normalize_display_name(_), do: nil

  @doc """
  Links a verified Mgl identity to an existing local user.
  """
  def link_mgl_identity(%User{} = user, claims) when is_map(claims) do
    issuer =
      claims
      |> Map.get("iss", MglId.issuer())
      |> to_string()
      |> String.trim_trailing("/")

    subject = claims["sub"]

    cond do
      not is_binary(subject) or subject == "" ->
        {:error, :missing_sub}

      identity = get_user_by_mgl_identity(issuer, subject) ->
        if identity.user_id == user.id do
          {:ok, identity}
        else
          {:error, :already_linked_other_user}
        end

      existing = get_mgl_identity(user) ->
        if existing.subject == subject and existing.issuer == issuer do
          {:ok, existing}
        else
          {:error, :user_already_linked}
        end

      true ->
        insert_mgl_identity(user, claims)
    end
  end

  defp insert_mgl_identity(%User{} = user, claims) do
    %UserIdentity{}
    |> UserIdentity.changeset(UserIdentity.mgl_attrs(user.id, claims))
    |> Repo.insert()
    |> case do
      {:ok, identity} ->
        {:ok, identity}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :provider) or
             Keyword.has_key?(changeset.errors, :user_id) or
             unique_constraint_error?(changeset) do
          {:error, :identity_conflict}
        else
          {:error, changeset}
        end
    end
  end

  defp unique_constraint_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {_field, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp unique_username(preferred) do
    cleaned =
      preferred
      |> to_string()
      |> String.trim()
      |> String.replace(~r/[^a-zA-Z0-9_]+/, "_")
      |> String.trim("_")
      |> String.slice(0, 24)

    base =
      cond do
        not Regex.match?(~r/[a-zA-Z0-9]/, cleaned) ->
          # Fall back to a readable random handle when IdP only supplies Mongolian script.
          "mgl_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

        String.length(cleaned) < 3 ->
          cleaned <> String.duplicate("0", 3 - String.length(cleaned))

        true ->
          cleaned
      end

    find_unique_username(base, 0)
  end

  defp find_unique_username(base, attempt) when attempt < 50 do
    candidate =
      if attempt == 0 do
        base
      else
        suffix = Integer.to_string(attempt)
        String.slice(base, 0, max(3, 32 - String.length(suffix))) <> suffix
      end

    case Repo.get_by(User, username: candidate) do
      nil -> {:ok, candidate}
      _ -> find_unique_username(base, attempt + 1)
    end
  end

  defp find_unique_username(_base, _attempt) do
    {:ok, "user" <> Integer.to_string(System.unique_integer([:positive]))}
  end
end
