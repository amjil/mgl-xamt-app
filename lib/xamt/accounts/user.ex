defmodule Xamt.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :username, :string
    field :display_name, :string
    field :avatar, :string
    field :bio, :string
    field :status, :string, default: "offline"
    field :status_emoji, :string
    field :status_text, :string
    field :global_role, :string, default: "user"
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
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

  @doc false
  def invite_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :username])
    |> validate_required([:email, :username])
    |> validate_registration_email(opts)
    |> validate_username(opts)
  end

  @doc """
  A user changeset for registration with email, username, display name, and password.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :username, :display_name, :password])
    |> validate_required([:email, :username, :password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_registration_email(opts)
    |> validate_username(opts)
    |> validate_password(opts)
    |> maybe_confirm_on_register()
  end

  @doc """
  Registration changeset used by site admins.

  Same as `registration_changeset/3`, but allows assigning a `global_role`.
  Keep this out of the public register form so users cannot escalate themselves.
  """
  def admin_registration_changeset(user, attrs, opts \\ []) do
    user
    |> registration_changeset(attrs, opts)
    |> cast(attrs, [:global_role])
    |> validate_required([:global_role])
    |> validate_inclusion(:global_role, @global_roles)
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
  def profile_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :display_name, :avatar, :bio, :status])
    |> validate_username(Keyword.put_new(opts, :validate_unique, false))
    |> validate_length(:display_name, max: 100)
    |> validate_length(:bio, max: 500)
    |> validate_inclusion(:status, ~w(online idle dnd offline), message: "is invalid")
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

  defp validate_registration_email(changeset, opts) do
    changeset
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> then(fn cs ->
      if Keyword.get(opts, :validate_unique, true) do
        cs
        |> unsafe_validate_unique(:email, Xamt.Repo)
        |> unique_constraint(:email)
      else
        cs
      end
    end)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Xamt.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
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
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Xamt.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
