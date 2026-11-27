defmodule Xamt.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :username, :string
    field :display_name, :string
    field :avatar, :string
    field :bio, :string
    field :status, :string, default: "offline"
    field :status_emoji, :string
    field :status_text, :string
    field :global_role, :string, default: "user"
    field :is_bot, :boolean, default: false
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @global_roles ~w(user creator admin)
  @server_creator_roles ~w(creator admin)

  def global_roles, do: @global_roles

  @doc """
  True when the user may create a new server (admin or creator).
  """
  def can_create_server?(%__MODULE__{global_role: role}) when role in @server_creator_roles,
    do: true

  def can_create_server?(_), do: false

  @doc """
  True when the user is a global admin (site-wide settings, etc.).
  """
  def admin?(%__MODULE__{global_role: "admin"}), do: true
  def admin?(_), do: false

  @doc """
  Prefer display name; fall back to username for UI labels.
  """
  def display_name(%__MODULE__{display_name: name}) when is_binary(name) and name != "", do: name
  def display_name(%__MODULE__{username: name}) when is_binary(name) and name != "", do: name
  def display_name(_), do: "?"

  @doc """
  Registration via verified Mgl ID claims.

  Marks the account confirmed because the IdP already authenticated the user.
  """
  def oidc_registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :display_name])
    |> validate_required([:username])
    |> validate_length(:display_name, max: 100)
    |> validate_username(opts)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  Creation changeset used by seeds and test fixtures.

  Allows assigning a `global_role`, so it must never be reachable from a
  user-facing form. Accounts for real people are provisioned by Mgl ID on
  first sign-in; a row created here has no Mgl identity and cannot sign in.
  """
  def admin_registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :display_name, :global_role])
    |> validate_required([:username, :global_role])
    |> validate_username(opts)
    |> validate_inclusion(:global_role, @global_roles)
    |> maybe_confirm_on_register()
  end

  defp maybe_confirm_on_register(changeset) do
    if changeset.valid? do
      put_change(changeset, :confirmed_at, DateTime.utc_now(:second))
    else
      changeset
    end
  end

  @doc """
  A user changeset for updating profile fields.
  """
  def profile_changeset(user, attrs, _opts \\ []) do
    user
    |> cast(attrs, [:display_name, :bio])
    |> put_safe_avatar(attrs)
    |> validate_length(:display_name, max: 100)
    |> validate_length(:bio, max: 500)
  end

  defp put_safe_avatar(changeset, attrs) do
    has_avatar_key? = Map.has_key?(attrs, "avatar") or Map.has_key?(attrs, :avatar)
    avatar = Map.get(attrs, "avatar", Map.get(attrs, :avatar))

    cond do
      not has_avatar_key? ->
        changeset

      is_nil(avatar) or avatar == "" ->
        put_change(changeset, :avatar, nil)

      is_binary(avatar) and Regex.match?(~r|^/uploads/[A-Za-z0-9._-]+$|, avatar) ->
        put_change(changeset, :avatar, avatar)

      true ->
        changeset
    end
  end

  @doc """
  A changeset for updating the user's custom status (emoji + text).
  Blank emoji and text clear the status to nil.
  """
  def custom_status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status_emoji, :status_text])
    |> update_change(:status_emoji, &blank_to_nil/1)
    |> update_change(:status_text, &blank_to_nil/1)
    |> validate_length(:status_emoji, max: 10)
    |> validate_length(:status_text, max: 50)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp validate_username(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:username])
      |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
        message: "must contain only letters, numbers, and underscores"
      )
      |> validate_length(:username, min: 3, max: 32)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Xamt.Repo)
      |> unique_constraint(:username)
    else
      changeset
    end
  end

  @doc """
  Changeset for operators to assign a global role.

  Keep `:global_role` out of registration and profile changesets so users
  cannot escalate themselves via public forms.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:global_role])
    |> validate_required([:global_role])
    |> validate_inclusion(:global_role, @global_roles)
  end

  @doc """
  Changeset for site admins to update another account.

  Accepts profile fields, username, and role. Keep this out of public
  forms so users cannot escalate themselves.
  """
  def admin_update_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :display_name, :bio, :global_role])
    |> validate_required([:username, :global_role])
    |> validate_inclusion(:global_role, @global_roles)
    |> validate_length(:display_name, max: 100)
    |> validate_length(:bio, max: 500)
    |> validate_username(opts)
  end
end
