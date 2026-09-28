defmodule Xamt.SiteSettings do
  @moduledoc """
  Singleton site-wide configuration, starting with whether public
  registration and email magic-link login are open.
  """

  alias Xamt.Accounts.User
  alias Xamt.Repo
  alias Xamt.SiteSettings.Setting

  @default_id "default"
  @topic "site_settings"

  @doc "Returns the persisted site settings, or in-memory defaults."
  def get do
    Repo.get(Setting, @default_id) ||
      %Setting{id: @default_id, registration_enabled: true, magic_link_enabled: true}
  end

  @doc "True when new accounts may register."
  def registration_enabled? do
    get().registration_enabled
  end

  @doc "True when people may request and use email magic-link login."
  def magic_link_enabled? do
    get().magic_link_enabled
  end

  @doc """
  Updates the registration switch. Only a global admin may change it.
  """
  def update_registration_enabled(%User{} = actor, enabled) when is_boolean(enabled) do
    update_as_admin(actor, %{registration_enabled: enabled})
  end

  @doc """
  Updates the magic-link login switch. Only a global admin may change it.
  """
  def update_magic_link_enabled(%User{} = actor, enabled) when is_boolean(enabled) do
    update_as_admin(actor, %{magic_link_enabled: enabled})
  end

  @doc """
  Writes the registration switch without an actor check.

  Used by tests, seeds, and operator consoles. Prefer
  `update_registration_enabled/2` from user-facing code.
  """
  def put_registration_enabled!(enabled) when is_boolean(enabled) do
    put!(%{registration_enabled: enabled})
  end

  @doc """
  Writes the magic-link login switch without an actor check.

  Used by tests, seeds, and operator consoles. Prefer
  `update_magic_link_enabled/2` from user-facing code.
  """
  def put_magic_link_enabled!(enabled) when is_boolean(enabled) do
    put!(%{magic_link_enabled: enabled})
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Xamt.PubSub, @topic)
  end

  defp update_as_admin(%User{} = actor, attrs) do
    if User.admin?(actor) do
      {:ok, put!(attrs)}
    else
      {:error, :unauthorized}
    end
  end

  defp put!(attrs) when is_map(attrs) do
    setting =
      get()
      |> Setting.changeset(attrs)
      |> Repo.insert_or_update!()

    broadcast(setting)
    setting
  end

  defp broadcast(%Setting{} = setting) do
    Phoenix.PubSub.broadcast(Xamt.PubSub, @topic, {:site_settings_updated, setting})
    setting
  end
end
