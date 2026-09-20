defmodule Xamt.Servers.Permissions do
  @moduledoc """
  Bitmask permission flags for `server_members.permissions`.

  A 64-bit integer stores up to 63 independently togglable flags (bit 63 is
  reserved so the value stays in PostgreSQL `bigint`'s signed positive range).
  Role names like `"owner"` remain UI labels; this module is the source of
  truth for authorization.
  """

  import Bitwise

  @u63 0x7FFF_FFFF_FFFF_FFFF

  @flags %{
    view_channel: 1 <<< 0,
    send_messages: 1 <<< 1,
    manage_messages: 1 <<< 2,
    kick_members: 1 <<< 3,
    ban_members: 1 <<< 4,
    manage_channels: 1 <<< 5,
    manage_server: 1 <<< 6
  }

  @flag_names Map.keys(@flags)

  def flags, do: @flags

  def flag_names, do: @flag_names

  def flag!(perm) when is_atom(perm), do: Map.fetch!(@flags, perm)

  @doc "Checks whether `user_perms` includes the given flag."
  def has_permission?(user_perms, perm) when is_integer(user_perms) and is_atom(perm) do
    flag = flag!(perm)
    (user_perms &&& flag) == flag
  end

  def has_permission?(_user_perms, _perm), do: false

  @doc "True if any of the given flags are set."
  def has_any?(user_perms, perms) when is_integer(user_perms) and is_list(perms) do
    Enum.any?(perms, &has_permission?(user_perms, &1))
  end

  def has_any?(_user_perms, _perms), do: false

  @doc "Grants one flag or a list of flags."
  def grant(user_perms, perm) when is_integer(user_perms) and is_atom(perm) do
    user_perms ||| flag!(perm)
  end

  def grant(user_perms, perms) when is_integer(user_perms) and is_list(perms) do
    Enum.reduce(perms, user_perms, &grant(&2, &1))
  end

  @doc "Revokes one flag or a list of flags without touching the others."
  def revoke(user_perms, perm) when is_integer(user_perms) and is_atom(perm) do
    user_perms &&& bnot(flag!(perm)) &&& @u63
  end

  def revoke(user_perms, perms) when is_integer(user_perms) and is_list(perms) do
    Enum.reduce(perms, user_perms, &revoke(&2, &1))
  end

  @doc "All defined flags OR'd together."
  def all do
    Enum.reduce(Map.values(@flags), 0, fn flag, acc -> acc ||| flag end)
  end

  @doc "Base guest/member combination: view + speak."
  def default_member_perms do
    grant(0, [:view_channel, :send_messages])
  end

  @doc "Staff preset: member perms plus moderation and channel/server management."
  def admin_perms do
    grant(default_member_perms(), [
      :manage_messages,
      :kick_members,
      :ban_members,
      :manage_channels,
      :manage_server
    ])
  end

  def owner_perms, do: all()

  @doc "Role label → preset bitmask. Custom grants should use `grant/2` instead."
  def for_role("owner"), do: owner_perms()
  def for_role("admin"), do: admin_perms()
  def for_role("member"), do: default_member_perms()
  def for_role(_role), do: default_member_perms()

  @doc "Atoms whose bits are set on `user_perms`."
  def enabled_flags(user_perms) when is_integer(user_perms) do
    Enum.filter(@flag_names, &has_permission?(user_perms, &1))
  end

  @doc """
  Ecto query fragment: `WHERE permissions & flag = flag`.

  Bind it from a context that already `import Ecto.Query`:

      where([sm], has_perm(sm.permissions, :kick_members))
  """
  defmacro has_perm(field, perm_name) when is_atom(perm_name) do
    flag = Map.fetch!(@flags, perm_name)

    quote do
      fragment("(? & ?) = ?", unquote(field), unquote(flag), unquote(flag))
    end
  end
end
