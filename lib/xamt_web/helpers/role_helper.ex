defmodule XamtWeb.RoleHelper do
  @moduledoc """
  Maps `global_role` (and future permission bits) to frontend-only visual config.

  Colors live in CSS — never persist hex codes on the user model.
  """

  use Gettext, backend: XamtWeb.Gettext

  @type role_ui :: %{
          color_class: String.t() | nil,
          bg_class: String.t() | nil,
          accent_class: String.t() | nil,
          label: String.t() | nil,
          icon: String.t() | nil
        }

  @doc """
  Visual config for a user struct, role string, or anything else (falls back).
  """
  @spec get_role_ui_config(term()) :: role_ui()
  def get_role_ui_config(%{global_role: role}) when is_binary(role),
    do: get_role_ui_config(role)

  def get_role_ui_config("admin") do
    %{
      color_class: "xamt-role--admin",
      bg_class: "xamt-role-badge--admin",
      accent_class: "xamt-profile--role-admin",
      label: gettext("Admin"),
      icon: "hero-shield-check"
    }
  end

  def get_role_ui_config("creator") do
    %{
      color_class: "xamt-role--creator",
      bg_class: "xamt-role-badge--creator",
      accent_class: "xamt-profile--role-creator",
      label: gettext("Creator"),
      icon: "hero-sparkles"
    }
  end

  def get_role_ui_config(_) do
    %{
      color_class: nil,
      bg_class: nil,
      accent_class: nil,
      label: nil,
      icon: nil
    }
  end
end
