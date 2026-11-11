defmodule XamtWeb.ProfileLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.Messages
  alias Xamt.Servers
  alias XamtWeb.RoleHelper

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_user_by_username(username) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("User not found."))
         |> push_navigate(to: ~p"/")}

      profile_user ->
        viewer = socket.assigns.current_scope && socket.assigns.current_scope.user

        {mutual_servers, recent_messages} =
          if viewer do
            {
              Servers.list_mutual_servers(viewer.id, profile_user.id),
              Messages.list_user_recent_messages(profile_user.id, viewer.id, limit: 10)
            }
          else
            {[], []}
          end

        {:ok,
         socket
         |> assign(:page_title, User.display_name(profile_user))
         |> assign(:profile_user, profile_user)
         |> assign(:mutual_servers, mutual_servers)
         |> assign(:recent_messages, recent_messages)}
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
      <main id="user-profile-canvas" class="xamt-home-canvas" phx-hook="MongolianScroll">
        <%!-- ==================== Section 1: Core identity banner ==================== --%>
        <aside class="xamt-home-section" id="profile-panel">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-user-circle" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h1 class="font-bold text-base tracking-widest mongol-text">
                {gettext("User Profile")}
              </h1>
            </div>

            <.link
              :if={@current_scope.user && @current_scope.user.id == @profile_user.id}
              navigate={~p"/settings"}
              id="profile-edit"
              class="xamt-btn py-2.5 px-2 text-xs font-bold mongol-text"
              title={gettext("Edit Profile")}
            >
              <.icon name="hero-pencil-square" class="w-4 h-4 mb-1" />
              <span>{gettext("Edit")}</span>
            </.link>
          </header>

          <%!-- User identity card --%>
          <div class="xamt-home-card items-center justify-between">
            <%!-- Left: avatar + display name + role badge --%>
            <div class="flex flex-row items-center gap-3 h-full">
              <div class="w-14 h-14 rounded-2xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-xl overflow-hidden border border-[var(--xamt-line)] shadow-sm shrink-0">
                <img
                  :if={@profile_user.avatar}
                  src={@profile_user.avatar}
                  alt={User.display_name(@profile_user)}
                  class="w-full h-full object-cover"
                />
                <span :if={!@profile_user.avatar}>
                  {initials(User.display_name(@profile_user))}
                </span>
              </div>

              <span class={[
                "text-xl font-bold tracking-wide text-[var(--xamt-text)] xamt-profile__display-name",
                RoleHelper.get_role_ui_config(@profile_user).color_class
              ]}>
                {User.display_name(@profile_user)}
              </span>

              <span class="text-xs text-[var(--xamt-muted)] xamt-profile__username">
                @{@profile_user.username}
              </span>

              <span :if={@profile_user.is_bot} class="xamt-role-pill xamt-role-pill--bot">
                BOT
              </span>

              <span
                :if={!@profile_user.is_bot && RoleHelper.global_role_label(@profile_user.global_role)}
                id="profile-role-badge"
                class={[
                  "xamt-role-pill",
                  @profile_user.global_role == "admin" && "xamt-role-pill--admin",
                  @profile_user.global_role == "creator" && "xamt-role-pill--creator"
                ]}
              >
                {RoleHelper.global_role_label(@profile_user.global_role)}
              </span>
            </div>

            <%!-- Right: custom status and join date --%>
            <div class="flex flex-row items-center justify-between h-full gap-3">
              <div
                :if={@profile_user.status_emoji || @profile_user.status_text}
                class="flex flex-row items-center gap-1.5 px-1.5 py-2.5 rounded-xl bg-[var(--xamt-bg)] border border-[var(--xamt-line)] text-xs"
              >
                <span :if={@profile_user.status_emoji}>
                  {@profile_user.status_emoji}
                </span>
                <span :if={@profile_user.status_text} class="text-[var(--xamt-text)]">
                  {@profile_user.status_text}
                </span>
              </div>

              <div class="flex flex-row items-center gap-1.5 text-xs text-[var(--xamt-muted)] mt-auto">
                <.icon name="hero-calendar-days" class="w-4 h-4 shrink-0" />
                <span>
                  {gettext("Joined %{date}",
                    date: Calendar.strftime(@profile_user.inserted_at, "%Y-%m-%d")
                  )}
                </span>
              </div>
            </div>
          </div>
        </aside>

        <%!-- ==================== Section 2: Bio ==================== --%>
        <section :if={@profile_user.bio && @profile_user.bio != ""} class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-document-text" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm">{gettext("Bio")}</h2>
            </div>
          </header>

          <div class="xamt-home-card">
            <p class="text-sm leading-relaxed text-[var(--xamt-text)] whitespace-pre-line h-full">
              {@profile_user.bio}
            </p>
          </div>
        </section>

        <%!-- ==================== Section 3: Mutual servers ==================== --%>
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-user-group" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm">{gettext("Mutual Servers")}</h2>
            </div>
            <span class="text-xs font-bold text-[var(--xamt-muted)]">
              {length(@mutual_servers)}
            </span>
          </header>

          <div class="flex flex-col gap-3 h-full">
            <div
              :if={@mutual_servers == []}
              class="xamt-user-strip justify-center text-xs text-[var(--xamt-muted)] px-3"
            >
              {gettext("No mutual servers.")}
            </div>

            <.link
              :for={server <- @mutual_servers}
              navigate={~p"/servers/#{server.slug}"}
              class="xamt-user-strip justify-between group"
            >
              <div class="flex flex-row items-center gap-2.5">
                <div class="w-8 h-8 rounded-xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-xs shrink-0 overflow-hidden group-hover:bg-[var(--xamt-accent)] group-hover:text-white transition-colors">
                  <img :if={server.icon} src={server.icon} class="w-full h-full object-cover" />
                  <span :if={!server.icon}>
                    {initials(server.name)}
                  </span>
                </div>
                <span class="font-bold text-sm text-[var(--xamt-text)]">{server.name}</span>
              </div>

              <.icon
                name="hero-arrow-right"
                class="w-4 h-4 text-[var(--xamt-muted)] group-hover:text-[var(--xamt-accent)] shrink-0"
              />
            </.link>
          </div>
        </section>

        <%!-- ==================== Section 4: Recent messages ==================== --%>
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon
                name="hero-chat-bubble-left-right"
                class="w-5 h-5 text-[var(--xamt-accent)] shrink-0"
              />
              <h2 class="font-bold text-sm">{gettext("Recent Messages")}</h2>
            </div>
            <span class="text-xs font-bold text-[var(--xamt-muted)]">
              {length(@recent_messages)}
            </span>
          </header>

          <div class="flex flex-col gap-3 h-full">
            <div
              :if={@recent_messages == []}
              class="xamt-user-strip justify-center text-xs text-[var(--xamt-muted)] px-3"
            >
              {gettext("No recent messages.")}
            </div>

            <.link
              :for={msg <- @recent_messages}
              navigate={~p"/servers/#{msg.channel.server.slug}/#{msg.channel.slug}"}
              class="xamt-home-card group"
            >
              <%!-- Left: server/channel context + sent time --%>
              <div class="flex flex-row items-center justify-between h-full text-xs text-[var(--xamt-muted)] border-r border-[var(--xamt-line)] pr-2">
                <span class="font-bold text-[var(--xamt-accent)]">
                  {msg.channel.server.name} · #{msg.channel.name}
                </span>
                <span class="font-mono text-[11px]">
                  {Calendar.strftime(msg.inserted_at, "%m-%d %H:%M")}
                </span>
              </div>

              <%!-- Right: message body preview --%>
              <div class="flex flex-row items-center justify-between h-full pl-1">
                <p class="text-sm text-[var(--xamt-text)] line-clamp-2">
                  {Messages.plain_text(msg)}
                </p>
                <.icon
                  name="hero-arrow-top-right-on-square"
                  class="w-4 h-4 text-[var(--xamt-muted)] group-hover:text-[var(--xamt-accent)] shrink-0 mt-auto"
                />
              </div>
            </.link>
          </div>
        </section>
      </main>
    </Layouts.home>
    """
  end

  defp initials(name) when is_binary(name) and name != "" do
    name |> String.first() |> String.upcase()
  end

  defp initials(_), do: "?"
end
