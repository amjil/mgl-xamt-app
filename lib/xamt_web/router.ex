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
    plug :assign_site_settings
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Session-cookie JSON API for the Service Worker. Background Sync cannot use
  # the LiveView WebSocket, so queued messages are POSTed here with the same
  # browser session + CSRF token that LiveView already uses.
  pipeline :session_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  scope "/api", XamtWeb do
    pipe_through [:session_api, :require_authenticated_user_api]

    post "/messages/sync", MessageApiController, :sync
  end

  # Bot REST API — Bearer bot token auth (not user session cookies).
  # Kept under /api/v1/bot for compatibility with existing installations.
  scope "/api/v1/bot", XamtWeb do
    pipe_through :api

    get "/me", BotApiController, :me
    get "/channels", BotApiController, :list_channels
    get "/channels/:channel_id", BotApiController, :show_channel
    get "/channels/:channel_id/messages", BotApiController, :list_messages
    post "/channels/:channel_id/messages", BotApiController, :create_message
    patch "/messages/:message_id", BotApiController, :update_message
    delete "/messages/:message_id", BotApiController, :delete_message
    get "/events/subscriptions", BotApiController, :list_event_subscriptions
    post "/interactions", BotApiController, :create_interaction
    post "/interactions/respond", BotApiController, :respond_interaction
    post "/interactions/:interaction_id/respond", BotApiController, :respond_interaction
  end

  scope "/", XamtWeb do
    pipe_through [:browser]

    # Uploads are not in Plug.Static — this controller checks membership
    # (or a public avatar/icon reference) before sending the file.
    get "/uploads/:filename", UploadController, :show

    live_session :public,
      on_mount: [
        {XamtWeb.UserAuth, :mount_current_scope},
        {XamtWeb.SearchPaletteHook, :default}
      ] do
      live "/", HomeLive, :index
      live "/profile/:username", ProfileLive, :show
    end
  end

  scope "/", XamtWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [
        {XamtWeb.UserAuth, :ensure_authenticated},
        {XamtWeb.SearchPaletteHook, :default}
      ] do
      live "/invite/:code", InviteLive, :show
      live "/servers/:server_slug", ServerLive, :show
      live "/servers/:server_slug/:channel_slug/new", ServerLive, :new_channel
      live "/servers/:server_slug/:channel_slug/edit/:edit_slug", ServerLive, :edit_channel
      live "/servers/:server_slug/:channel_slug", ServerLive, :show
      live "/settings", SettingsLive, :edit
      live "/saved", SavedLive, :index
    end
  end

  # Admin operator pages. Same authenticated browser pipeline so the session
  # is required at HTTP; `:ensure_admin` then gates global site admins only.
  scope "/", XamtWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin,
      on_mount: [
        {XamtWeb.UserAuth, :ensure_authenticated},
        {XamtWeb.UserAuth, :ensure_admin},
        {XamtWeb.SearchPaletteHook, :default}
      ] do
      live "/admin/users", AdminUsersLive, :index
      live "/admin/users/:id/edit", AdminUserLive, :edit
    end
  end

  ## Authentication route alias (spec: /login)
  scope "/", XamtWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", UserSessionController, :new
  end

  scope "/", XamtWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    delete "/users/log-out", UserSessionController, :delete

    # Mgl ID OIDC — must not use redirect_if_user_is_authenticated so
    # the callback can create a local session for first-time users.
    get "/auth/mgl", MglAuthController, :start
    get "/auth/mgl/callback", MglAuthController, :callback
  end

  # Account linking requires an existing Xamt session.
  # `/account/link` is the Mgl ID → Xamt token receiver (ownership proof).
  # OIDC link entry remains under `/settings/account/identities/mgl/*`.
  scope "/", XamtWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/account/link", MglAuthController, :account_link
    get "/settings/account/identities/mgl/connect", MglAuthController, :link_start
    get "/settings/account/identities/mgl/callback", MglAuthController, :link_callback
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
