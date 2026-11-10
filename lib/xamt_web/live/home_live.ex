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
               |> put_flash(:info, gettext("Joined %{name}", name: server.name))
               |> push_navigate(to: ~p"/servers/#{server.slug}")}

            {:error, :not_found} ->
              {:noreply,
               socket
               |> assign(:invite_code, code)
               |> put_flash(:error, gettext("Invite not found"))}

            {:error, _} ->
              {:noreply,
               socket
               |> assign(:invite_code, code)
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
          <%!-- Section 1: brand & personal controls --%>
          <aside class="xamt-home-section" id="home-identity-rail">
            <div class="flex flex-row items-center justify-between h-full py-1">
              <div class="flex flex-row items-center gap-3">
                <div class="w-10 h-10 rounded-2xl bg-[var(--xamt-accent)] text-white flex items-center justify-center font-bold text-lg shadow-md shrink-0">
                  ᠬ
                </div>
                <h1 class="text-xl font-bold tracking-widest text-[var(--xamt-text)] mongol-text">
                  {gettext("Xamt community hall")}
                </h1>
              </div>

              <div class="flex flex-row items-center gap-3">
                <button
                  type="button"
                  id="home-open-search"
                  class="xamt-icon-btn"
                  phx-click="open_search"
                  title={gettext("Search")}
                  aria-label={gettext("Search")}
                >
                  <.icon name="hero-magnifying-glass" class="w-5 h-5" />
                </button>

                <.link
                  navigate={~p"/saved"}
                  class="xamt-icon-btn"
                  title={gettext("Saved")}
                >
                  <.icon name="hero-bookmark" class="w-5 h-5" />
                </.link>

                <.link
                  navigate={~p"/profile/#{@current_scope.user.username}"}
                  class="xamt-icon-btn"
                  title={gettext("Profile")}
                >
                  <.icon name="hero-user-circle" class="w-5 h-5" />
                </.link>

                <.link
                  navigate={~p"/settings"}
                  class="xamt-icon-btn"
                  title={gettext("Settings")}
                >
                  <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
                </.link>

                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="xamt-icon-btn"
                  title={gettext("Log out")}
                >
                  <.icon name="hero-arrow-right-start-on-rectangle" class="w-5 h-5" />
                </.link>
              </div>
            </div>
          </aside>

          <%!-- Section 2: joined communities --%>
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

          <%!-- Section 3: join & create --%>
          <section class="xamt-home-section" id="home-create-join">
            <header class="xamt-home-section__header">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-plus-circle" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
                <h2 class="font-bold text-base mongol-text">{gettext("Create or join")}</h2>
              </div>
            </header>

            <form phx-submit="join_by_code" id="home-join-by-code-form" class="xamt-home-card">
              <div class="font-bold text-xs text-[var(--xamt-accent)] mongol-text">
                {gettext("Join with invite code")}
              </div>

              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Invite code")}</span>
                <input
                  type="text"
                  name="code"
                  value={@invite_code}
                  required
                  placeholder={gettext("Enter invite code...")}
                  class="xamt-bot-input"
                  onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
                />
              </label>

              <button type="submit" class="xamt-btn xamt-btn--primary h-full px-2.5 font-bold text-xs">
                <.icon name="hero-arrow-right-end-on-rectangle" class="w-4 h-4 mb-1.5" />
                <span class="mongol-text">{gettext("Join now")}</span>
              </button>
            </form>

            <.form
              :if={@can_create_server?}
              for={@form}
              id="home-create-server-form"
              phx-change="validate_create"
              phx-submit="create_server"
              class="xamt-home-card"
            >
              <div class="font-bold text-xs text-[var(--xamt-accent)] mongol-text">
                {gettext("Create Mongolian community")}
              </div>

              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Name")}</span>
                <input
                  id="create-server-name"
                  type="text"
                  name="server[name]"
                  value={@form[:name].value}
                  required
                  placeholder={gettext("Community name...")}
                  class="xamt-bot-input mongol-input"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                  onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
                />
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Slug")}</span>
                <input
                  id="server_slug"
                  type="text"
                  name="server[slug]"
                  value={@form[:slug].value}
                  placeholder="my-server"
                  class="xamt-bot-input xamt-input--latin"
                  autocomplete="off"
                  spellcheck="false"
                  onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
                />
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Description")}</span>
                <input
                  id="create-server-desc"
                  type="text"
                  name="server[description]"
                  value={@form[:description].value}
                  placeholder={gettext("Describe the community...")}
                  class="xamt-bot-input mongol-input"
                  phx-hook="MongolianIME"
                  onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
                />
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Visibility")}</span>
                <div
                  id="create-server-visibility-host"
                  class="mn-select-host"
                  phx-hook="MnSelect"
                  phx-update="ignore"
                >
                  <select
                    id="create-server-visibility"
                    name="server[visibility]"
                    class="xamt-bot-input"
                  >
                    <option
                      value="public"
                      selected={to_string(@form[:visibility].value) == "public"}
                    >
                      {gettext("Public")}
                    </option>
                    <option
                      value="private"
                      selected={to_string(@form[:visibility].value || "private") == "private"}
                    >
                      {gettext("Private")}
                    </option>
                  </select>
                </div>
              </label>

              <button
                type="submit"
                id="create-server-submit"
                class="xamt-btn xamt-btn--primary h-full px-3 font-bold text-xs"
              >
                <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
                <span class="mongol-text">{gettext("Create server")}</span>
              </button>
            </.form>
          </section>

          <%!-- Section 4: discover public communities --%>
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
        <div class="xamt-home">
          <header class="xamt-home__hero">
            <span class="xamt-ornament" aria-hidden="true"></span>
            <img
              class="xamt-brand-logo"
              src={~p"/images/pwa-icon-512.png"}
              alt="Xamt"
              width="112"
              height="112"
              decoding="async"
            />
            <p class="xamt-kicker mongol-text">{gettext("Community")}</p>
            <p class="xamt-brand">Xamt</p>
            <h1 class="xamt-home__title mongol-text">{gettext("Mongolian community")}</h1>
            <p class="xamt-home__lead mongol-text">
              {gettext("Traditional Mongolian community & realtime chat")}
            </p>
          </header>

          <section class="xamt-home__cta xamt-surface">
            <p class="xamt-home__cta-copy mongol-text">
              {gettext("Join a community and start writing in traditional Mongolian.")}
            </p>
            <.link navigate={~p"/login"} class="xamt-btn xamt-btn--primary mongol-text">
              {gettext("Log in")}
            </.link>
            <.link
              :if={@registration_enabled?}
              navigate={~p"/register"}
              class="xamt-btn mongol-text"
            >
              {gettext("Register")}
            </.link>
          </section>
        </div>
      <% end %>

      <.drawer
        :if={@show_create}
        id="create-server-drawer"
        show
        on_cancel={JS.push("cancel_create")}
      >
        <div id="create-server" class="xamt-sheet-form">
          <h2 class="xamt-section-title mongol-text">{gettext("Create server")}</h2>

          <.form
            for={@form}
            id="create-server-form"
            phx-change="validate_create"
            phx-submit="create_server"
            class="xamt-form xamt-form--vertical"
          >
            <.input
              field={@form[:name]}
              id="server_name"
              label={gettext("Name")}
              required
              class="xamt-input mongol-input"
              phx-hook="MongolianIME"
              autocomplete="off"
            />
            <.input
              field={@form[:slug]}
              id="drawer_server_slug"
              label={gettext("Slug")}
              class="xamt-input xamt-input--latin"
              autocomplete="off"
              spellcheck="false"
              placeholder="my-server"
            />
            <.input
              field={@form[:description]}
              id="server_description"
              type="textarea"
              label={gettext("Description")}
              class="xamt-textarea mongol-input"
              phx-hook="MongolianIME"
            />
            <.input
              field={@form[:visibility]}
              id="server_visibility"
              type="select"
              label={gettext("Visibility")}
              options={[
                {gettext("Private — invite only"), "private"},
                {gettext("Public — anyone can find and join"), "public"}
              ]}
            />
            <div class="xamt-form__actions">
              <button
                type="submit"
                id="drawer-create-server-submit"
                class="xamt-btn xamt-btn--primary mongol-text"
              >
                {gettext("Create")}
              </button>
              <button
                type="button"
                id="create-server-cancel"
                class="xamt-btn mongol-text"
                phx-click="cancel_create"
              >
                {gettext("Cancel")}
              </button>
            </div>
          </.form>
        </div>
      </.drawer>

      <.drawer
        :if={@editing_server}
        id="edit-server-drawer"
        show
        on_cancel={JS.push("cancel_edit_server")}
      >
        <div id="server-settings" class="xamt-sheet-form">
          <h2 class="xamt-section-title mongol-text">{gettext("Server settings")}</h2>

          <.form
            for={@server_form}
            id="edit-server-form"
            phx-submit="save_server"
            class="xamt-form xamt-form--vertical"
          >
            <.input
              field={@server_form[:name]}
              id="server-settings-name"
              label={gettext("Name")}
              phx-hook="MongolianIME"
              class="xamt-input mongol-input"
              autocomplete="off"
            />
            <.input
              field={@server_form[:slug]}
              id="server-settings-slug"
              label={gettext("Slug")}
              class="xamt-input xamt-input--latin"
              autocomplete="off"
              spellcheck="false"
            />
            <.input
              field={@server_form[:description]}
              id="server-settings-description"
              type="textarea"
              label={gettext("Description")}
              phx-hook="MongolianIME"
              class="xamt-textarea mongol-input"
            />
            <.input
              field={@server_form[:visibility]}
              id="server-settings-visibility"
              type="select"
              label={gettext("Visibility")}
              options={[
                {gettext("Private — invite only"), "private"},
                {gettext("Public — anyone can find and join"), "public"}
              ]}
            />
            <div class="xamt-form__actions">
              <button
                type="submit"
                id="server-settings-save"
                class="xamt-btn xamt-btn--primary mongol-text"
              >
                {gettext("Save")}
              </button>
              <button
                type="button"
                id="edit-server-cancel"
                class="xamt-btn mongol-text"
                phx-click="cancel_edit_server"
              >
                {gettext("Cancel")}
              </button>
            </div>
          </.form>

          <div class="xamt-rail__section-head">
            <span class="mongol-text">{gettext("Invites")}</span>
            <button
              type="button"
              id="create-invite"
              class="xamt-icon-btn"
              phx-click="create_invite"
              aria-label={gettext("Create invite")}
            >
              +
            </button>
          </div>

          <ul class="xamt-invite-list">
            <li :for={invite <- @invites} class="xamt-invite">
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
                <.icon name="hero-clipboard" class="size-3" />
              </button>
              <button
                type="button"
                class="xamt-icon-btn"
                phx-click="delete_invite"
                phx-value-id={invite.id}
                aria-label={gettext("Delete invite")}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </li>
          </ul>
        </div>
      </.drawer>
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
