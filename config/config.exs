# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :xamt, :scopes,
  user: [
    default: true,
    module: Xamt.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Xamt.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :xamt,
  ecto_repos: [Xamt.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Remote candidate backend for mgl-web-ime. Dev defaults to http://dev1:3003;
# set XAMT_IME_BASE_URL to override, or empty / "local" for the bundled dictionary.
config :xamt, :ime_base_url, nil

# Message send rate limit (ETS sliding window). Tests override limit.
config :xamt, Xamt.Messages.RateLimiter, limit: 5, window_seconds: 3

# Local VAPID pair for development. Production reads env vars in runtime.exs.
# Generate a new pair with: mix web_push_ex.vapid
config :web_push_ex, :vapid,
  subject: "mailto:admin@xamt.app",
  public_key:
    "BLN44unPgkRn4KHf5szEzGg8oHEKcJXrkgWU3G6zLzmLFTcOkQMkf3yM-M0lx5MZssNCYdaodHTB051uQ0EPbQQ",
  private_key: "5j5nvktvZE_EziNxh_KdIk7T4pvehV5rGZIPmGtNcFg"

# Configure the endpoint
config :xamt, XamtWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: XamtWeb.ErrorHTML, json: XamtWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Xamt.PubSub,
  live_view: [signing_salt: "V4s9gPYr"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :xamt, Xamt.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  xamt: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  xamt: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
