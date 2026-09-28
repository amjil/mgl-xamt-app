defmodule Xamt.SiteSettings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "site_settings" do
    field :registration_enabled, :boolean, default: true
    field :magic_link_enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:registration_enabled, :magic_link_enabled])
    |> validate_required([:registration_enabled, :magic_link_enabled])
  end
end
