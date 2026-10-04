defmodule Xamt.Uploads.Grant do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "upload_grants" do
    field :filename, :string

    belongs_to :server, Xamt.Servers.Server
    belongs_to :user, Xamt.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
