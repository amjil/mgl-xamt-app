defmodule Xamt.Repo do
  use Ecto.Repo,
    otp_app: :xamt,
    adapter: Ecto.Adapters.Postgres
end
