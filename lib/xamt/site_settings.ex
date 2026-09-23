defmodule Xamt.SiteSettings do
  @moduledoc """
  Singleton site-wide configuration, starting with whether public
  registration is open.
  """

  alias Xamt.Accounts.User
  alias Xamt.Repo
  alias Xamt.SiteSettings.Setting

  @default_id "default"
  @topic "site_settings"

  @doc "Returns the persisted site settings, or in-memory defaults."
  def get do
    Repo.get(Setting, @default_id) ||
      %Setting{id: @default_id, registration_enabled: true}
  end

  @doc "True when new accounts may register."
  def registration_enabled? do
    get().registration_enabled
  end

  @doc """
  Updates the registration switch. Only a global admin may change it.
  """
  def update_registration_enabled(%User{} = actor, enabled) when is_boolean(enabled) do
    if User.admin?(actor) do
      {:ok, put_registration_enabled!(enabled)}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Writes the registration switch without an actor check.

  Used by tests, seeds, and operator consoles. Prefer
  `update_registration_enabled/2` from user-facing code.
  """
  def put_registration_enabled!(enabled) when is_boolean(enabled) do
    setting =
      get()
      |> Setting.changeset(%{registration_enabled: enabled})
      |> Repo.insert_or_update!()

    broadcast(setting)
    setting
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Xamt.PubSub, @topic)
  end

  defp broadcast(%Setting{} = setting) do
    Phoenix.PubSub.broadcast(Xamt.PubSub, @topic, {:site_settings_updated, setting})
    setting
  end
end
