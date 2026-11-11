defmodule XamtWeb.HomeLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts.User
  alias Xamt.AuthRateLimit
  alias Xamt.Servers
  alias Xamt.Servers.Permissions
  alias Xamt.Servers.Server
  alias Xamt.SiteSettings
  alias Xamt.Slug

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SiteSettings.subscribe()

    scope = socket.assigns.current_scope

    {servers, public_servers} =
      if scope && scope.user do
        {Servers.list_servers_for_user(scope), Servers.list_discoverable_servers(scope)}
      else
        {[], []}
      end

    {:ok,
     socket
     |> assign(:page_title, "Xamt")
     |> assign(:servers, servers)
     |> assign(:public_servers, public_servers)
     |> assign(:search_query, "")
     |> assign(:invite_code, "")
     |> assign(:unread_counts, %{})
     |> assign(:form, to_form(Servers.change_server(%Server{}), as: :server))
     |> assign(:show_create, false)
     |> assign(:show_join_code, false)
     |> assign(:suggested_slug, "")
     |> assign(:can_create_server?, can_create_server?(scope))
     |> clear_server_settings()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(
       socket,
       :show_create,
       params["create"] == "1" and socket.assigns.can_create_server?
     )}
  end

  @impl true
  def handle_info({:site_settings_updated, setting}, socket) do
    {:noreply,
     socket
     |> assign(:registration_enabled?, setting.registration_enabled)
     |> assign(:magic_link_enabled?, setting.magic_link_enabled)}
  end

  @impl true
  def handle_event("open_join_code", _params, socket) do
    {:noreply,
     socket
     |> close_create()
     |> clear_server_settings()
     |> assign(:show_join_code, true)}
  end

  def handle_event("close_join_code", _params, socket) do
    {:noreply, assign(socket, :show_join_code, false)}
  end

  def handle_event("toggle_create", _params, socket) do
    if socket.assigns.can_create_server? do
      {:noreply, open_create(socket)}
    else
      {:noreply, deny_create(socket)}
    end
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply, close_create(socket)}
  end

  def handle_event("validate_create", %{"server" => params}, socket) do
    if socket.assigns.can_create_server? do
      {params, suggested} = maybe_suggest_slug(params, socket.assigns.suggested_slug)

      {:noreply,
       socket
       |> assign(:form, to_form(Servers.change_server(%Server{}, params), as: :server))
       |> assign(:suggested_slug, suggested)}
    else
      {:noreply, deny_create(socket)}
    end
  end

  def handle_event("create_server", %{"server" => params}, socket) do
    if socket.assigns.can_create_server? do
      case Servers.create_server(socket.assigns.current_scope, params) do
        {:ok, server} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Server created"))
           |> push_navigate(to: ~p"/servers/#{server.slug}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: :server), show_create: true)}

        {:error, :unauthorized} ->
          {:noreply, deny_create(socket)}
      end
    else
      {:noreply, deny_create(socket)}
    end
  end

  def handle_event("join_by_code", %{"code" => code}, socket) do
    scope = socket.assigns.current_scope

    if is_nil(scope) or is_nil(scope.user) do
      {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    else
      case AuthRateLimit.check(:invite, scope.user.id) do
        {:error, :rate_limited} ->
          {:noreply, put_flash(socket, :error, gettext("Too many attempts. Try again shortly."))}

        :ok ->
          case Servers.redeem_invite(scope, String.trim(code)) do
            {:ok, server} ->
              {:noreply,
               socket
               |> assign(:show_join_code, false)
               |> put_flash(:info, gettext("Joined %{name}", name: server.name))
               |> push_navigate(to: ~p"/servers/#{server.slug}")}

            {:error, :not_found} ->
              {:noreply,
               socket
               |> assign(:invite_code, code)
               |> assign(:show_join_code, true)
               |> put_flash(:error, gettext("Invite not found"))}

            {:error, _} ->
              {:noreply,
               socket
               |> assign(:invite_code, code)
               |> assign(:show_join_code, true)
               |> put_flash(:error, gettext("Invite is invalid or expired"))}
          end
      end
    end
  end

  def handle_event("search_public", params, socket) do
    q = Map.get(params, "q", "") |> to_string()
    scope = socket.assigns.current_scope

    public_servers =
      if scope && scope.user do
        Servers.list_discoverable_servers(scope, query: q)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, q)
     |> assign(:public_servers, public_servers)}
  end

  def handle_event("join_public_server", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    if is_nil(scope) or is_nil(scope.user) do
      {:noreply, put_flash(socket, :error, gettext("Unauthorized"))}
    else
      case Servers.join_server(scope, id) do
        {:ok, _member} ->
          server = Servers.get_server!(id)

          {:noreply,
           socket
           |> put_flash(:info, gettext("Joined %{name}", name: server.name))
           |> push_navigate(to: ~p"/servers/#{server.slug}")}

        {:error, :already_member} ->
          server = Servers.get_server!(id)
          {:noreply, push_navigate(socket, to: ~p"/servers/#{server.slug}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not join this community"))}
      end
    end
  end

  def handle_event("edit_server_request", %{"id" => id}, socket) do
    case find_manageable_server(socket, id) do
      nil ->
        {:noreply, deny_manage(socket)}

      server ->
        {:noreply,
         socket
         |> close_create()
         |> assign(:show_join_code, false)
         |> assign(:editing_server, server)
         |> assign(:server_form, to_form(Servers.change_server(server), as: :server))
         |> assign(:invites, Servers.list_invites(server.id))}
    end
  end

  def handle_event("cancel_edit_server", _params, socket) do
    {:noreply, clear_server_settings(socket)}
  end

  def handle_event("save_server", %{"server" => params}, socket) do
    server = socket.assigns.editing_server

    cond do
      is_nil(server) ->
        {:noreply, deny_manage(socket)}

      not viewer_can_manage?(server, socket.assigns.current_scope) ->
        {:noreply, deny_manage(socket)}

      true ->
        case Servers.update_server(socket.assigns.current_scope, server.id, params) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> assign(:servers, refresh_user_servers(socket))
             |> clear_server_settings()
             |> put_flash(:info, gettext("Server updated"))}

          {:error, :unauthorized} ->
            {:noreply, deny_manage(socket)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :server_form, to_form(changeset, as: :server))}
        end
    end
  end

  def handle_event("create_invite", _params, socket) do
    case socket.assigns.editing_server do
      nil ->
        {:noreply, deny_manage(socket)}

      server ->
        case Servers.create_invite(socket.assigns.current_scope, server.id) do
          {:ok, _invite} ->
            {:noreply, assign(socket, :invites, Servers.list_invites(server.id))}

          {:error, _} ->
            {:noreply, deny_manage(socket)}
        end
    end
  end

  def handle_event("delete_invite", %{"id" => id}, socket) do
    case socket.assigns.editing_server do
      nil ->
        {:noreply, deny_manage(socket)}

      server ->
        case Servers.delete_invite(socket.assigns.current_scope, id) do
          {:ok, _} ->
            {:noreply, assign(socket, :invites, Servers.list_invites(server.id))}

          {:error, _} ->
            {:noreply, deny_manage(socket)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.home
      flash={@flash}
      current_scope={@current_scope}
      show_search={@show_search}
      global_search_query={@global_search_query}
      global_search_results={@global_search_results}
    >
      <%= if @current_scope && @current_scope.user do %>
        <main id="home-canvas" class="xamt-home-canvas" phx-hook="MongolianScroll">
          <%!-- Section 1: joined communities --%>
          <section class="xamt-home-section" id="home-my-servers">
            <header class="xamt-home-section__header">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-rectangle-stack" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
                <h2 class="font-bold text-base mongol-text">{gettext("Your servers")}</h2>
              </div>
              <span class="text-xs font-bold text-[var(--xamt-muted)]">
                {length(@servers)}
              </span>
            </header>

            <div class="flex flex-col gap-3 h-full">
              <div
                :for={server <- @servers}
                class={[
                  "xamt-home-card group relative",
                  viewer_can_manage?(server, @current_scope) && "has-settings"
                ]}
              >
                <.link navigate={~p"/servers/#{server.slug}"} class="contents">
                  <div class="flex flex-row items-center gap-3 h-full">
                    <div class="w-9 h-9 rounded-xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold shrink-0 group-hover:bg-[var(--xamt-accent)] group-hover:text-white transition-colors">
                      {server_initial(server.name)}
                    </div>
                    <span class="font-bold text-base tracking-wide text-[var(--xamt-text)] mongol-text xamt-server-card__name">
                      {upright_text(server.name)}
                    </span>
                    <span
                      :if={Map.get(@unread_counts, server.id, 0) > 0}
                      class="mt-auto px-1.5 py-2 rounded-full bg-[var(--xamt-accent)] text-white text-xs font-bold"
                    >
                      {Map.get(@unread_counts, server.id)}
                    </span>
                  </div>

                  <div class="flex flex-row items-center justify-between h-full text-xs text-[var(--xamt-muted)]">
                    <p class="line-clamp-1 mongol-text xamt-server-card__desc">
                      {cond do
                        present_text?(server.description) -> upright_text(server.description)
                        true -> gettext("Open channel scroll")
                      end}
                    </p>
                    <.icon
                      name="hero-arrow-right"
                      class="w-4 h-4 shrink-0 group-hover:translate-x-0.5 transition-transform"
                    />
                  </div>
                </.link>

                <button
                  :if={viewer_can_manage?(server, @current_scope)}
                  type="button"
                  id={"edit-server-#{server.id}"}
                  class="xamt-server-card__settings xamt-icon-btn absolute top-2 right-2"
                  phx-click="edit_server_request"
                  phx-value-id={server.id}
                  title={gettext("Server settings")}
                  aria-label={gettext("Server settings")}
                >
                  <.icon name="hero-cog-6-tooth" class="size-4" />
                </button>
              </div>

              <div
                :if={@servers == []}
                class="xamt-home-card justify-center items-center text-xs text-[var(--xamt-muted)] mongol-text"
              >
                <%= if @can_create_server? do %>
                  {gettext("No servers yet. Create one to start chatting.")}
                <% else %>
                  {gettext("No servers yet. Join a public server or wait for an invite.")}
                <% end %>
              </div>
            </div>
          </section>

          <%!-- Section 2: join & create triggers (opens Bot-style modals) --%>
          <section class="xamt-home-section" id="home-create-join">
            <header class="xamt-home-section__header">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-plus-circle" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
                <h2 class="font-bold text-base mongol-text">{gettext("Create or join")}</h2>
              </div>
            </header>

            <div class="flex flex-col gap-3 h-full">
              <%!-- Trigger 1: Join with invite code modal --%>
              <button
                type="button"
                id="home-open-join-code"
                phx-click="open_join_code"
                class="xamt-home-card items-center cursor-pointer text-start group"
                aria-label={gettext("Join with invite code")}
              >
                <div class="flex flex-row items-center gap-3 h-full">
                  <div class="w-9 h-9 rounded-xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center shrink-0 group-hover:bg-[var(--xamt-accent)] group-hover:text-white transition-colors">
                    <.icon name="hero-ticket" class="w-5 h-5" />
                  </div>
                  <span class="font-bold text-base text-[var(--xamt-text)] mongol-text">
                    {gettext("Join with invite code")}
                  </span>
                </div>

                <div class="flex flex-row items-center justify-between h-full text-xs text-[var(--xamt-muted)]">
                  <span class="mongol-text">{gettext("Enter invite code...")}</span>
                  <span class="xamt-btn xamt-btn--soft py-2.5 px-2 text-xs font-bold mongol-text">
                    {gettext("Join now")}
                  </span>
                </div>
              </button>

              <%!-- Trigger 2: Create server modal --%>
              <button
                :if={@can_create_server?}
                type="button"
                id="home-open-create"
                class="xamt-home-card items-center cursor-pointer text-start group"
                phx-click="toggle_create"
                aria-label={gettext("Create server")}
              >
                <div class="flex flex-row items-center gap-3 h-full">
                  <div class="w-9 h-9 rounded-xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center shrink-0 group-hover:bg-[var(--xamt-accent)] group-hover:text-white transition-colors">
                    <.icon name="hero-plus" class="w-5 h-5" />
                  </div>
                  <span class="font-bold text-base text-[var(--xamt-text)] mongol-text">
                    {gettext("Create Mongolian community")}
                  </span>
                </div>

                <div class="flex flex-row items-center justify-between h-full text-xs text-[var(--xamt-muted)]">
                  <span class="mongol-text">{gettext("Describe the community...")}</span>
                  <span class="xamt-btn xamt-btn--primary py-2.5 px-2 text-xs font-bold mongol-text">
                    {gettext("Create server")}
                  </span>
                </div>
              </button>
            </div>
          </section>

          <%!-- Section 3: discover public communities --%>
          <section class="xamt-home-section" id="discover-panel">
            <header class="xamt-home-section__header">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-globe-alt" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
                <h2 class="font-bold text-base mongol-text">{gettext("Discover")}</h2>
              </div>
            </header>

            <form
              phx-change="search_public"
              phx-submit="search_public"
              class="h-full shrink-0"
              id="public-server-search-form"
            >
              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Search communities")}</span>
                <input
                  id="public-server-search"
                  type="text"
                  name="q"
                  value={@search_query}
                  placeholder={gettext("Filter by keyword...")}
                  phx-debounce="250"
                  class="xamt-bot-input mongol-input"
                  phx-hook="MongolianIME"
                  onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
                />
              </label>
            </form>

            <div class="flex flex-col gap-3 h-full">
              <div
                :for={server <- @public_servers}
                class="xamt-home-card"
                id={"public-server-#{server.id}"}
              >
                <div class="flex flex-row items-center gap-2.5 h-full">
                  <div class="w-8 h-8 rounded-xl bg-emerald-500/15 text-emerald-500 flex items-center justify-center font-bold shrink-0">
                    {server_initial(server.name)}
                  </div>
                  <span class="font-bold text-base mongol-text">{upright_text(server.name)}</span>
                </div>

                <p class="text-xs text-[var(--xamt-muted)] h-full mongol-text">
                  {cond do
                    present_text?(server.description) -> upright_text(server.description)
                    true -> gettext("Join the public discussion")
                  end}
                </p>

                <button
                  type="button"
                  phx-click="join_public_server"
                  phx-value-id={server.id}
                  id={"join-public-#{server.id}"}
                  class="xamt-btn xamt-btn--primary h-full px-2.5 text-xs font-bold mongol-text"
                >
                  {gettext("Join")}
                </button>
              </div>

              <div
                :if={@public_servers == []}
                class="xamt-home-card justify-center items-center text-xs text-[var(--xamt-muted)] mongol-text"
              >
                {gettext("No more public communities")}
              </div>
            </div>
          </section>
        </main>
      <% else %>
        <main id="guest-home-canvas" class="xamt-home-canvas xamt-home" phx-hook="MongolianScroll">
          <%!-- 第 1 幕：品牌主视觉旌旗 --%>
          <header class="xamt-home-section xamt-home__hero !border-b-0">
            <div class="xamt-home-card items-center justify-between">
              <div class="flex flex-row items-center gap-4 h-full">
                <span class="xamt-ornament" aria-hidden="true"></span>
                <img
                  class="xamt-brand-logo !w-16 !h-16"
                  src={~p"/images/pwa-icon-512.png"}
                  alt="Xamt"
                  width="64"
                  height="64"
                  decoding="async"
                />
                <p class="xamt-kicker mongol-text">{gettext("Community")}</p>
                <p class="xamt-brand">Xamt</p>
              </div>

              <div class="flex flex-row items-center gap-3 h-full">
                <h1 class="xamt-home__title font-bold text-xl mongol-text">
                  {gettext("Mongolian community")}
                </h1>
                <p class="xamt-home__lead text-sm text-[var(--xamt-muted)] mongol-text">
                  {gettext("Traditional Mongolian community & realtime chat")}
                </p>
              </div>
            </div>
          </header>

          <%!-- 第 2 幕：登录与注册行动号召 --%>
          <section class="xamt-home-section">
            <header class="xamt-home-section__header">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-sparkles" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
                <h2 class="font-bold text-sm mongol-text">{gettext("Get Started")}</h2>
              </div>
            </header>

            <div class="xamt-home-card xamt-home__cta">
              <p class="xamt-home__cta-copy text-sm text-[var(--xamt-muted)] mongol-text h-full">
                {gettext("Join a community and start writing in traditional Mongolian.")}
              </p>

              <div class="flex flex-row items-center gap-3 h-full">
                <.link
                  navigate={~p"/login"}
                  class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold mongol-text"
                >
                  <.icon name="hero-arrow-right-end-on-rectangle" class="w-4 h-4 mb-1.5" />
                  <span>{gettext("Log in")}</span>
                </.link>

                <.link
                  :if={@registration_enabled?}
                  navigate={~p"/register"}
                  class="xamt-btn xamt-btn--soft h-full px-3 font-bold mongol-text"
                >
                  <.icon name="hero-user-plus" class="w-4 h-4 mb-1.5" />
                  <span>{gettext("Register")}</span>
                </.link>
              </div>
            </div>
          </section>
        </main>
      <% end %>

      <%!-- Modal 1: Join with Invite Code (Bot Manager style vertical-lr modal) --%>
      <div
        :if={@show_join_code}
        id="join-code-modal"
        class="xamt-modal"
        phx-window-keydown="close_join_code"
        phx-key="Escape"
      >
        <div class="xamt-modal-backdrop" phx-click="close_join_code"></div>

        <div
          id="join-code-card"
          class="xamt-bot-modal-card !w-auto relative z-10"
          phx-hook="MongolianScroll"
        >
          <%!-- Column 1: Title & Close --%>
          <div class="xamt-bot-pane !flex-row justify-between items-center">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-ticket" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="text-lg font-bold tracking-wider mongol-text">
                {gettext("Join with invite code")}
              </h2>
            </div>

            <button
              type="button"
              id="join-code-cancel"
              phx-click="close_join_code"
              class="xamt-icon-btn"
              title={gettext("Close")}
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <%!-- Column 2: Invite Code Form --%>
          <form phx-submit="join_by_code" id="home-join-by-code-form">
            <div class="xamt-bot-pane">
              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Invite code")}</span>
                <input
                  id="home-invite-code-input"
                  type="text"
                  name="code"
                  value={@invite_code}
                  required
                  placeholder={gettext("Enter invite code...")}
                  class="xamt-bot-input xamt-input--latin"
                  autocomplete="off"
                  spellcheck="false"
                />
              </label>

              <div class="flex flex-row items-center gap-3 h-full">
                <button
                  type="submit"
                  id="join-code-submit"
                  class="xamt-btn xamt-btn--primary h-full px-3 font-bold text-xs mongol-text"
                >
                  <.icon name="hero-arrow-right-end-on-rectangle" class="w-4 h-4 mb-1.5" />
                  <span>{gettext("Join now")}</span>
                </button>

                <button
                  type="button"
                  phx-click="close_join_code"
                  class="xamt-btn h-full px-2.5 text-xs mongol-text"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>

      <%!-- Modal 2: Create Server (Bot Manager style vertical-lr modal) --%>
      <div
        :if={@show_create}
        id="create-server-drawer"
        class="xamt-modal"
        phx-window-keydown="cancel_create"
        phx-key="Escape"
      >
        <div class="xamt-modal-backdrop" phx-click="cancel_create"></div>

        <div
          id="create-server"
          class="xamt-bot-modal-card !w-auto relative z-10"
          phx-hook="MongolianScroll"
        >
          <%!-- Column 1: Title & Close --%>
          <div class="xamt-bot-pane !flex-row justify-between items-center">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-plus-circle" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="text-lg font-bold tracking-wider mongol-text">
                {gettext("Create Mongolian community")}
              </h2>
            </div>

            <button
              type="button"
              phx-click="cancel_create"
              class="xamt-icon-btn"
              title={gettext("Close")}
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <%!-- Column 2: Create Server Form --%>
          <.form
            for={@form}
            id="create-server-form"
            phx-change="validate_create"
            phx-submit="create_server"
          >
            <div class="xamt-bot-pane">
              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Name")}</span>
                <input
                  id="server_name"
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  required
                  placeholder={gettext("Community name...")}
                  class="xamt-bot-input mongol-input"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                />
                <p
                  :for={msg <- Enum.map(@form[:name].errors, &translate_error(&1))}
                  class="text-xs text-red-500 mongol-text"
                >
                  {msg}
                </p>
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Slug")}</span>
                <input
                  id="server_slug"
                  type="text"
                  name={@form[:slug].name}
                  value={@form[:slug].value}
                  placeholder="my-server"
                  class="xamt-bot-input xamt-input--latin"
                  autocomplete="off"
                  spellcheck="false"
                />
                <p
                  :for={msg <- Enum.map(@form[:slug].errors, &translate_error(&1))}
                  class="text-xs text-red-500 mongol-text"
                >
                  {msg}
                </p>
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Description")}</span>
                <textarea
                  id="server_description"
                  name={@form[:description].name}
                  placeholder={gettext("Describe the community...")}
                  class="xamt-bot-input mongol-input !w-14"
                  phx-hook="MongolianIME"
                >{Phoenix.HTML.Form.normalize_value("textarea", @form[:description].value)}</textarea>
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Visibility")}</span>
                <div
                  id="create-server-visibility-host"
                  class="mn-select-host"
                  phx-hook="MnSelect"
                  phx-update="ignore"
                >
                  <select
                    id="server_visibility"
                    name={@form[:visibility].name}
                    class="xamt-bot-input"
                  >
                    <option
                      value="private"
                      selected={to_string(@form[:visibility].value || "private") == "private"}
                    >
                      {gettext("Private — invite only")}
                    </option>
                    <option
                      value="public"
                      selected={to_string(@form[:visibility].value) == "public"}
                    >
                      {gettext("Public — anyone can find and join")}
                    </option>
                  </select>
                </div>
              </label>

              <div class="flex flex-row items-center gap-3 h-full">
                <button
                  type="submit"
                  id="drawer-create-server-submit"
                  class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
                >
                  <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
                  <span>{gettext("Create server")}</span>
                </button>

                <button
                  type="button"
                  id="create-server-cancel"
                  class="xamt-btn h-full px-2.5 text-xs mongol-text"
                  phx-click="cancel_create"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Modal 3: Edit Server Settings & Invites (Bot Manager style vertical-lr modal) --%>
      <div
        :if={@editing_server}
        id="edit-server-drawer"
        class="xamt-modal"
        phx-window-keydown="cancel_edit_server"
        phx-key="Escape"
      >
        <div class="xamt-modal-backdrop" phx-click="cancel_edit_server"></div>

        <div
          id="server-settings"
          class="xamt-bot-modal-card !w-auto relative z-10"
          phx-hook="MongolianScroll"
        >
          <%!-- Column 1: Title & Close --%>
          <div class="xamt-bot-pane !flex-row justify-between items-center">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="text-lg font-bold tracking-wider mongol-text">
                {gettext("Server settings")}
              </h2>
            </div>

            <button
              type="button"
              phx-click="cancel_edit_server"
              class="xamt-icon-btn"
              title={gettext("Close")}
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <%!-- Column 2: Server Settings Form --%>
          <.form
            for={@server_form}
            id="edit-server-form"
            phx-submit="save_server"
          >
            <div class="xamt-bot-pane">
              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Name")}</span>
                <input
                  id="server-settings-name"
                  type="text"
                  name={@server_form[:name].name}
                  value={@server_form[:name].value}
                  phx-hook="MongolianIME"
                  class="xamt-bot-input mongol-input"
                  autocomplete="off"
                />
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Slug")}</span>
                <input
                  id="server-settings-slug"
                  type="text"
                  name={@server_form[:slug].name}
                  value={@server_form[:slug].value}
                  class="xamt-bot-input xamt-input--latin"
                  autocomplete="off"
                  spellcheck="false"
                />
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Description")}</span>
                <textarea
                  id="server-settings-description"
                  name={@server_form[:description].name}
                  phx-hook="MongolianIME"
                  class="xamt-bot-input mongol-input !w-14"
                >{Phoenix.HTML.Form.normalize_value("textarea", @server_form[:description].value)}</textarea>
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label mongol-text">{gettext("Visibility")}</span>
                <div
                  id="server-settings-visibility-host"
                  class="mn-select-host"
                  phx-hook="MnSelect"
                  phx-update="ignore"
                >
                  <select
                    id="server-settings-visibility"
                    name={@server_form[:visibility].name}
                    class="xamt-bot-input"
                  >
                    <option
                      value="private"
                      selected={to_string(@server_form[:visibility].value || "private") == "private"}
                    >
                      {gettext("Private — invite only")}
                    </option>
                    <option
                      value="public"
                      selected={to_string(@server_form[:visibility].value) == "public"}
                    >
                      {gettext("Public — anyone can find and join")}
                    </option>
                  </select>
                </div>
              </label>

              <div class="flex flex-row items-center gap-3 h-full">
                <button
                  type="submit"
                  id="server-settings-save"
                  class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
                >
                  <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
                  <span>{gettext("Save")}</span>
                </button>

                <button
                  type="button"
                  id="edit-server-cancel"
                  class="xamt-btn h-full px-2.5 text-xs mongol-text"
                  phx-click="cancel_edit_server"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </div>
          </.form>

          <%!-- Column 3: Invites Management --%>
          <div class="xamt-bot-pane">
            <div class="flex flex-row items-center justify-between h-full">
              <span class="font-bold text-sm text-[var(--xamt-accent)] mongol-text">
                {gettext("Invites")}
              </span>
              <button
                type="button"
                id="create-invite"
                class="xamt-btn xamt-btn--soft py-2.5 px-2 text-xs font-bold"
                phx-click="create_invite"
                aria-label={gettext("Create invite")}
              >
                <.icon name="hero-plus" class="w-4 h-4" />
              </button>
            </div>

            <ul class="xamt-invite-list h-full">
              <li :for={invite <- @invites} class="xamt-invite h-full">
                <code>/invite/{invite.code}</code>
                <span :if={invite.max_uses} class="xamt-invite__uses">
                  {invite.uses}/{invite.max_uses}
                </span>
                <button
                  type="button"
                  id={"copy-invite-#{invite.id}"}
                  class="xamt-icon-btn"
                  data-copy={url(~p"/invite/#{invite.code}")}
                  data-copied={gettext("Copied")}
                  data-copy-failed={gettext("Could not copy")}
                  aria-label={gettext("Copy invite link")}
                >
                  <.icon name="hero-clipboard" class="size-3.5" />
                </button>
                <button
                  type="button"
                  class="xamt-icon-btn text-[var(--xamt-error)]"
                  phx-click="delete_invite"
                  phx-value-id={invite.id}
                  aria-label={gettext("Delete invite")}
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.home>
    """
  end

  defp server_initial(name) when is_binary(name) do
    initial = name |> String.trim() |> String.first() || "?"
    upright_text(initial)
  end

  defp server_initial(_), do: "?"

  defp present_text?(text) when is_binary(text), do: String.trim(text) != ""
  defp present_text?(_), do: false

  defp maybe_suggest_slug(params, previous_suggested) do
    name = Map.get(params, "name") || ""
    slug = Map.get(params, "slug") || ""
    suggested = Slug.slugify(name)

    if slug == "" or slug == previous_suggested do
      {Map.put(params, "slug", suggested), suggested}
    else
      {params, previous_suggested}
    end
  end

  defp can_create_server?(%{user: %User{} = user}), do: User.can_create_server?(user)
  defp can_create_server?(_), do: false

  defp viewer_can_manage?(%Server{} = server, %{user: %User{} = user}) do
    Permissions.has_permission?(server.viewer_permissions, :manage_server) or
      server.owner_id == user.id
  end

  defp viewer_can_manage?(_, _), do: false

  defp find_manageable_server(socket, id) do
    server = Enum.find(socket.assigns.servers, &(&1.id == id))

    if server && viewer_can_manage?(server, socket.assigns.current_scope) do
      server
    end
  end

  defp refresh_user_servers(socket) do
    case socket.assigns.current_scope do
      %{user: %User{}} = scope -> Servers.list_servers_for_user(scope)
      _ -> []
    end
  end

  defp clear_server_settings(socket) do
    socket
    |> assign(:editing_server, nil)
    |> assign(:server_form, nil)
    |> assign(:invites, [])
  end

  defp open_create(socket) do
    socket
    |> clear_server_settings()
    |> assign(:show_join_code, false)
    |> assign(:show_create, true)
    |> assign(:suggested_slug, "")
    |> assign(:form, to_form(Servers.change_server(%Server{}), as: :server))
  end

  defp close_create(socket) do
    socket
    |> assign(:show_create, false)
    |> assign(:suggested_slug, "")
    |> assign(:form, to_form(Servers.change_server(%Server{}), as: :server))
  end

  defp deny_create(socket) do
    socket
    |> close_create()
    |> put_flash(:error, gettext("You don't have permission to create a server"))
  end

  defp deny_manage(socket) do
    socket
    |> clear_server_settings()
    |> put_flash(:error, gettext("Unauthorized"))
  end
end
