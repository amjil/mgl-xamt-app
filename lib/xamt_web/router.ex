defmodule XamtWeb.Router do
  use XamtWeb, :router

  import XamtWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {XamtWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", XamtWeb do
    pipe_through [:browser]

    live_session :public,
      on_mount: [{XamtWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive, :index
      live "/profile/:username", ProfileLive, :show
    end
  end

  scope "/", XamtWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{XamtWeb.UserAuth, :ensure_authenticated}] do
      live "/invite/:code", InviteLive, :show
      live "/servers/:server_slug", ServerLive, :show
      live "/servers/:server_slug/:channel_slug/new", ServerLive, :new_channel
      live "/servers/:server_slug/:channel_slug/edit/:edit_slug", ServerLive, :edit_channel
      live "/servers/:server_slug/:channel_slug/settings", ServerLive, :edit_server
      live "/servers/:server_slug/:channel_slug", ServerLive, :show
      live "/settings", SettingsLive, :edit
    end
  end

  ## Authentication route aliases (spec: /login /register)
  scope "/", XamtWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", UserSessionController, :new
    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", XamtWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", XamtWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    post "/login", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:xamt, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: XamtWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
