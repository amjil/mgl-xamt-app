defmodule XamtWeb.AdminUsersLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.SiteSettings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> assign(:query, "")
     |> assign(:magic_link_enabled?, SiteSettings.magic_link_enabled?())
     |> assign_users("")}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign_users(query)}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_magic_link", _params, socket) do
    enabled = !socket.assigns.magic_link_enabled?

    case SiteSettings.update_magic_link_enabled(socket.assigns.current_scope.user, enabled) do
      {:ok, setting} ->
        {:noreply, assign(socket, :magic_link_enabled?, setting.magic_link_enabled)}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to change this."))}
    end
  end

  def handle_event("set_role", %{"user_id" => user_id, "role" => role}, socket) do
    target = Accounts.get_user!(user_id)

    case Accounts.update_user_as_admin(socket.assigns.current_scope, target, %{
           "global_role" => role
         }) do
      {:ok, _updated} ->
        {:noreply, assign_users(socket, socket.assigns.query)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update role"))}
    end
  end

  defp assign_users(socket, query) do
    {:ok, users} = Accounts.search_users_as_admin(socket.assigns.current_scope, query)

    socket
    |> assign(:users_count, length(users))
    |> stream(:users, users, reset: true)
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}) when is_binary(name), do: name
  defp display_name(_), do: "?"

  defp role_label("admin"), do: gettext("Admin")
  defp role_label("creator"), do: gettext("Creator")
  defp role_label(_), do: gettext("Member")

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
      <main id="admin-users-canvas" class="xamt-home-canvas" phx-hook="MongolianScroll">
        <%!-- Zone 1: overview + site auth toggle --%>
        <aside class="xamt-home-section" id="admin-users-identity-rail">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-users" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h1 class="font-bold text-base tracking-widest mongol-text">
                {gettext("Users")}
              </h1>
            </div>

            <div class="flex flex-row items-center gap-2 text-xs text-[var(--xamt-muted)]">
              <span id="admin-users-count" class="mongol-text">
                {gettext("%{count} accounts", count: @users_count)}
              </span>

              <.link
                navigate={~p"/admin/users/new"}
                id="admin-users-create"
                class="xamt-btn xamt-btn--primary py-2.5 px-2 text-xs font-bold mongol-text"
              >
                {gettext("Create user")}
              </.link>
            </div>
          </header>

          <div class="xamt-user-strip justify-between">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-envelope-open" class="w-4 h-4 text-[var(--xamt-accent)] shrink-0" />
              <span class="font-bold text-xs mongol-text">{gettext("Magic link login")}</span>
            </div>

            <button
              type="button"
              id="admin-users-magic-link-toggle"
              phx-click="toggle_magic_link"
              class={[
                "xamt-btn py-3 px-2 text-xs font-bold mongol-text",
                @magic_link_enabled? && "xamt-btn--primary"
              ]}
            >
              {if @magic_link_enabled?, do: gettext("On"), else: gettext("Off")}
            </button>
          </div>
        </aside>

        <%!-- Zone 2: search --%>
        <section class="xamt-home-section" id="admin-users-search-rail">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-magnifying-glass" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm mongol-text">{gettext("Search users")}</h2>
            </div>
          </header>

          <form
            id="admin-users-search"
            phx-change="search"
            phx-submit="search"
            class="flex flex-col gap-3 h-full"
          >
            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Keyword")}</span>
              <input
                id="admin-users-q"
                type="text"
                name="q"
                value={@query}
                placeholder={gettext("Username, nickname, or email...")}
                phx-debounce="300"
                class="xamt-bot-input mongol-input"
                phx-hook="MongolianIME"
                autocomplete="off"
                spellcheck="false"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <button
              :if={@query != ""}
              type="button"
              id="admin-users-clear-search"
              phx-click="search"
              phx-value-q=""
              class="xamt-btn h-full px-2 text-xs text-[var(--xamt-muted)] mongol-text"
            >
              <.icon name="hero-x-mark" class="w-4 h-4 mb-1" />
              <span>{gettext("Clear")}</span>
            </button>
          </form>
        </section>

        <%!-- Zone 3: roster --%>
        <section class="xamt-home-section" id="admin-users-roster-rail">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-identification" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm mongol-text">{gettext("Roster")}</h2>
            </div>
          </header>

          <div id="admin-users" class="flex flex-col gap-3 h-full" phx-update="stream">
            <div
              id="admin-users-empty"
              class="hidden only:block xamt-user-strip justify-center text-xs text-[var(--xamt-muted)] px-4 mongol-text"
            >
              <%= if @query == "" do %>
                {gettext("No users yet")}
              <% else %>
                {gettext("No matching users")}
              <% end %>
            </div>

            <div
              :for={{id, u} <- @streams.users}
              id={id}
              class={[
                "xamt-user-strip",
                RoleHelper.get_role_ui_config(u).accent_class
              ]}
            >
              <.link
                navigate={~p"/admin/users/#{u.id}/edit"}
                class="xamt-user-strip__avatar hover:opacity-80 transition-opacity"
                title={display_name(u)}
              >
                <.avatar user={u} id={"admin-user-avatar-#{u.id}"} class="xamt-avatar !w-9 !h-9" />
              </.link>

              <%!-- Below avatar: two side-by-side pillars --%>
              <div class="xamt-user-strip__cols">
                <div class="xamt-user-strip__main">
                  <.link
                    navigate={~p"/admin/users/#{u.id}/edit"}
                    class="flex flex-row items-center gap-2 hover:opacity-80 transition-opacity"
                  >
                    <span class="font-bold text-base text-[var(--xamt-text)] mongol-text xamt-admin-user__name">
                      {display_name(u)}
                    </span>

                    <span class="text-xs text-[var(--xamt-muted)] xamt-admin-user__username">
                      @{u.username}
                    </span>
                  </.link>

                  <div class="flex flex-row items-center gap-2">
                    <span :if={u.is_bot} class="xamt-role-pill xamt-role-pill--bot">BOT</span>

                    <span
                      :if={!u.is_bot && u.id == @current_scope.user.id}
                      class={[
                        "xamt-role-pill",
                        u.global_role == "admin" && "xamt-role-pill--admin",
                        u.global_role == "creator" && "xamt-role-pill--creator",
                        u.global_role not in ["admin", "creator"] && "xamt-role-pill--member"
                      ]}
                    >
                      {role_label(u.global_role)}
                    </span>

                    <form
                      :if={!u.is_bot && u.id != @current_scope.user.id}
                      id={"admin-user-role-form-#{u.id}"}
                      phx-change="set_role"
                      class="xamt-role-select-form shrink-0"
                    >
                      <input type="hidden" name="user_id" value={u.id} />
                      <div class={[
                        "xamt-role-pill xamt-role-select",
                        u.global_role == "admin" && "xamt-role-pill--admin",
                        u.global_role == "creator" && "xamt-role-pill--creator",
                        u.global_role not in ["admin", "creator"] && "xamt-role-pill--member"
                      ]}>
                        <div
                          id={"role-select-host-#{u.id}-#{u.global_role}"}
                          class="mn-select-host"
                          phx-hook="MnSelect"
                          phx-update="ignore"
                        >
                          <select id={"role-select-#{u.id}"} name="role">
                            <option value="user" selected={u.global_role == "user"}>
                              {gettext("Member")}
                            </option>
                            <option value="creator" selected={u.global_role == "creator"}>
                              {gettext("Creator")}
                            </option>
                            <option value="admin" selected={u.global_role == "admin"}>
                              {gettext("Admin")}
                            </option>
                          </select>
                        </div>
                      </div>
                    </form>
                  </div>

                  <div class="flex flex-row items-center gap-2 mt-auto">
                    <.link
                      navigate={~p"/admin/users/#{u.id}/edit"}
                      id={"admin-user-edit-#{u.id}"}
                      class="xamt-icon-btn"
                      title={gettext("Edit user")}
                    >
                      <.icon name="hero-chevron-right" class="w-4 h-4" />
                    </.link>
                  </div>
                </div>

                <div class="xamt-user-strip__email">
                  <span class="xamt-admin-user__email">{u.email}</span>
                </div>
              </div>
            </div>
          </div>
        </section>
      </main>
    </Layouts.home>
    """
  end
end
