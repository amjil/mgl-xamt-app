defmodule XamtWeb.ServerLive.Rails do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Helpers
  import XamtWeb.ServerLive.Overlays

  def servers_rail(assigns) do
    ~H"""
    <aside class="xamt-rail xamt-rail--servers">
      <button
        type="button"
        id="drawer-close"
        class="xamt-drawer-close"
        phx-click="set_mobile_panel"
        phx-value-panel="messages"
        aria-label={gettext("Close panel")}
      >
        <.icon name="hero-x-mark" class="size-5" />
      </button>

      <.link
        navigate={~p"/"}
        id="drawer-home"
        class="xamt-brand-mark"
        title={gettext("Home")}
        aria-label={gettext("Home")}
      >
        <img
          src={~p"/images/pwa-icon-192.png"}
          alt=""
          width="42"
          height="42"
          decoding="async"
        />
      </.link>

      <span class="xamt-leftnav__rule" aria-hidden="true"></span>

      <ul class="xamt-leftnav__links">
        <li>
          <.link navigate={~p"/"} class="mongol-text">{gettext("Home")}</.link>
        </li>
        <li :if={
          @current_scope && @current_scope.user && Xamt.Accounts.User.admin?(@current_scope.user)
        }>
          <.link navigate={~p"/admin/users"} class="mongol-text">
            {gettext("Users")}
          </.link>
        </li>
        <li>
          <button
            type="button"
            id="rail-open-search"
            class="xamt-leftnav__link-btn mongol-text"
            phx-click="open_search"
            title={gettext("Search")}
            aria-label={gettext("Search")}
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4 shrink-0" />
            <span>{gettext("Search")}</span>
          </button>
        </li>
      </ul>

      <div class="xamt-leftnav__foot">
        <.chat_user_menu
          :if={@current_scope && @current_scope.user}
          id="chat-rail-user-menu"
          avatar_id="rail-profile-avatar"
          palette_id="xamt-theme-palette-rail"
          user={@current_scope.user}
        />
      </div>
    </aside>
    """
  end

  def channels_rail(assigns) do
    ~H"""
    <aside class="xamt-rail xamt-rail--channels">
      <div class="xamt-rail__pane xamt-rail__pane--top">
        <button
          type="button"
          id="server-info"
          class="xamt-rail__header"
          phx-click="toggle_server_menu"
          aria-label={gettext("Server info")}
          aria-expanded={@show_server_menu}
        >
          <h1 class="xamt-rail__title mongol-text">{upright_text(@server.name)}</h1>
        </button>

        <div class="xamt-rail__section">
          <div class="xamt-rail__section-head">
            <span class="mongol-text">{gettext("Channels")}</span>
            <div class="xamt-rail__section-actions">
              <button
                :if={@can_manage_server?}
                type="button"
                id="open-bot-manager"
                phx-click="open_bot_manager"
                class="xamt-icon-btn"
                title={gettext("Manage bot integrations")}
                aria-label={gettext("Manage bot integrations")}
              >
                <.icon name="hero-cpu-chip" class="w-5 h-5" />
              </button>
              <.link
                :if={@can_manage_channels? and @active_channel}
                id="toggle-channel-form"
                patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/new"}
                class="xamt-icon-btn"
                aria-label={gettext("Create channel")}
              >
                +
              </.link>
            </div>
          </div>

          <.form
            for={to_form(%{"q" => @channel_filter})}
            id="channel-filter-form"
            phx-change="filter_channels"
            phx-submit="filter_channels"
            class="xamt-channel-filter"
          >
            <.input
              type="search"
              name="q"
              id="channel-filter-q"
              value={@channel_filter}
              label={gettext("Filter channels")}
              placeholder={gettext("Filter channels")}
              class="xamt-input mongol-input xamt-channel-filter__input"
              phx-hook="MongolianIME"
              phx-debounce="200"
              autocomplete="off"
              spellcheck="false"
            />
          </.form>

          <nav class="xamt-channel-nav" id="channel-nav">
            <div
              :if={@filtered_channels == [] and @channel_filter != ""}
              id="channel-filter-empty"
              class="xamt-channel-filter__empty mongol-text"
            >
              {gettext("No matching channels")}
            </div>
            <div :for={ch <- @filtered_channels} class="xamt-channel-item">
              <.link
                patch={~p"/servers/#{@server.slug}/#{ch.slug}"}
                id={"channel-link-#{ch.slug}"}
                class={[
                  "xamt-channel-link",
                  @active_channel && ch.id == @active_channel.id && "is-active",
                  MapSet.member?(@unread_channels, ch.id) && "has-unread"
                ]}
              >
                <span class="xamt-channel-hash">#</span>
                <span class={[
                  "mongol-text",
                  MapSet.member?(@unread_channels, ch.id) && "font-bold text-[var(--xamt-text)]"
                ]}>
                  {ch.name}
                </span>
                <span
                  :if={
                    MapSet.member?(@unread_channels, ch.id) &&
                      !(@active_channel && ch.id == @active_channel.id)
                  }
                  class="xamt-unread-dot"
                  aria-hidden="true"
                >
                </span>
              </.link>

              <.action_menu
                :if={@can_manage_channels?}
                id={"channel-menu-#{ch.id}"}
                label={gettext("Channel actions")}
              >
                <button
                  type="button"
                  class="xamt-icon-btn"
                  phx-click="move_channel"
                  phx-value-id={ch.id}
                  phx-value-direction="up"
                  aria-label={gettext("Move earlier")}
                >
                  <.icon name="hero-chevron-up" class="size-3" />
                </button>
                <button
                  type="button"
                  class="xamt-icon-btn"
                  phx-click="move_channel"
                  phx-value-id={ch.id}
                  phx-value-direction="down"
                  aria-label={gettext("Move later")}
                >
                  <.icon name="hero-chevron-down" class="size-3" />
                </button>
                <.link
                  :if={@active_channel}
                  patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/edit/#{ch.slug}"}
                  id={"edit-channel-#{ch.id}"}
                  class="xamt-icon-btn"
                  aria-label={gettext("Rename channel")}
                >
                  <.icon name="hero-pencil" class="size-3" />
                </.link>
                <button
                  type="button"
                  class="xamt-icon-btn"
                  phx-click="delete_channel"
                  phx-value-id={ch.id}
                  data-confirm={gettext("Delete this channel and all its messages?")}
                  aria-label={gettext("Delete channel")}
                >
                  <.icon name="hero-trash" class="size-3" />
                </button>
              </.action_menu>
            </div>
          </nav>
        </div>
      </div>

      <div class="xamt-rail__pane xamt-rail__pane--members">
        <div class="xamt-rail__section">
          <h3 class="xamt-rail__section-head mongol-text">{gettext("Online")}</h3>
          <ul class="xamt-member-list">
            <li :for={user <- @online_users} class="xamt-member">
              <% online_role = RoleHelper.get_role_ui_config(user) %>
              <.status_avatar
                user={user}
                id={"online-avatar-#{user.id}"}
                class="xamt-avatar xamt-avatar--sm"
                clickable?={own_presence_user?(user, @current_scope.user)}
              />
              <span class="xamt-presence is-online"></span>
              <span class={["xamt-member__name mongol-text", online_role.color_class]}>
                {user.display_name}
              </span>
              <div
                :if={online_role.label}
                class={["xamt-role-badge", online_role.bg_class]}
              >
                <.icon name={online_role.icon} class="w-3 h-3 shrink-0" />
                <span>{online_role.label}</span>
              </div>
            </li>
          </ul>

          <h3 class="xamt-rail__section-head mongol-text">{gettext("Members")}</h3>
          <ul id="server-members-list" class="xamt-member-list" phx-update="stream">
            <li :for={{dom_id, member} <- @streams.members} id={dom_id} class="xamt-member">
              <% member_role = RoleHelper.get_role_ui_config(member.user) %>
              <.status_avatar
                user={member.user}
                id={"member-avatar-#{member.user_id}"}
                class="xamt-avatar xamt-avatar--sm"
                clickable?={member.user_id == @current_scope.user.id}
              />
              <span class="xamt-presence"></span>
              <span class={["xamt-member__name mongol-text", member_role.color_class]}>
                {display_name(member.user)}
              </span>
              <div
                :if={member_role.label}
                class={["xamt-role-badge", member_role.bg_class]}
              >
                <.icon name={member_role.icon} class="w-3 h-3 shrink-0" />
                <span>{member_role.label}</span>
              </div>
              <span :if={member.role != "member"} class="xamt-role">
                {member.role}
              </span>

              <.action_menu
                :if={
                  (@can_kick_members? or @can_manage_server?) and member.role != "owner" and
                    member.user_id != @current_scope.user.id
                }
                id={"member-menu-#{member.user_id}"}
                label={gettext("Member actions")}
              >
                <button
                  :if={@can_manage_server?}
                  type="button"
                  class="xamt-icon-btn"
                  phx-click="set_member_role"
                  phx-value-user-id={member.user_id}
                  phx-value-role={if member.role == "admin", do: "member", else: "admin"}
                  aria-label={gettext("Change role")}
                >
                  <.icon
                    name={if member.role == "admin", do: "hero-arrow-down", else: "hero-arrow-up"}
                    class="size-3"
                  />
                </button>
                <button
                  :if={@can_kick_members?}
                  type="button"
                  class="xamt-icon-btn"
                  phx-click="kick_member"
                  phx-value-user-id={member.user_id}
                  data-confirm={gettext("Remove this member?")}
                  aria-label={gettext("Remove member")}
                >
                  <.icon name="hero-user-minus" class="size-3" />
                </button>
              </.action_menu>
            </li>
            <li
              :if={@has_more_members}
              id="members-infinite-scroll"
              phx-hook="InfiniteScroll"
              data-event="load_more_members"
              class="xamt-scroll-sentinel"
            >
            </li>
          </ul>
        </div>
      </div>
    </aside>
    """
  end

  def main_header(assigns) do
    ~H"""
    <header class="xamt-main__header xamt-mobile-toolbar">
      <button
        type="button"
        id="mobile-nav-menu"
        class="xamt-mobile-nav__btn xamt-mobile-nav__menu"
        phx-click="set_mobile_panel"
        phx-value-panel="channels"
        aria-label={gettext("Servers and channels")}
        aria-expanded={@mobile_panel in [:channels, :servers]}
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>
      <h2 class="xamt-main__title">
        <span class="xamt-channel-hash">#</span>
        <span class="mongol-text">{@active_channel && @active_channel.name}</span>
      </h2>
      <button
        :if={@active_channel}
        type="button"
        id="toggle-pinned-drawer"
        class={[
          "xamt-icon-btn xamt-pinned-entry",
          @show_pinned_drawer && "is-active"
        ]}
        phx-click="toggle_pinned_drawer"
        aria-label={gettext("Pinned messages")}
        aria-expanded={@show_pinned_drawer}
        aria-haspopup="dialog"
        title={gettext("Pinned messages")}
      >
        <.icon name="hero-bookmark-square" class="size-5" />
      </button>
      <button
        type="button"
        id="mobile-nav-search"
        class="xamt-icon-btn xamt-search-entry"
        phx-click="open_search"
        aria-label={gettext("Search")}
        title={gettext("Search")}
      >
        <.icon name="hero-magnifying-glass" class="size-5" />
      </button>
      <button
        type="button"
        id="mobile-nav-members"
        class="xamt-mobile-nav__btn xamt-mobile-nav__members"
        phx-click="set_mobile_panel"
        phx-value-panel="members"
        aria-label={gettext("Members")}
        aria-expanded={@mobile_panel == :members}
      >
        <.icon name="hero-users" class="size-5" />
      </button>

      <.chat_user_menu
        :if={@current_scope.user}
        id="chat-toolbar-user-menu"
        avatar_id="nav-profile-avatar"
        profile_link_id="nav-profile"
        palette_id="xamt-theme-palette-toolbar"
        user={@current_scope.user}
      />
    </header>
    """
  end

  attr :id, :string, required: true
  attr :avatar_id, :string, required: true
  attr :palette_id, :string, required: true
  attr :profile_link_id, :string, default: nil
  attr :user, :map, required: true

  defp chat_user_menu(assigns) do
    ~H"""
    <details id={@id} class="xamt-user-menu">
      <summary
        class="xamt-nav-profile"
        title={gettext("Profile")}
        aria-label={gettext("Profile")}
      >
        <.avatar
          user={@user}
          id={@avatar_id}
          class="xamt-avatar xamt-avatar--sm"
        />
      </summary>

      <div class="xamt-user-menu__popover" role="menu">
        <div class="xamt-user-menu__header">
          <span class="font-bold text-sm text-[var(--xamt-text)] mongol-text">
            {@user.display_name || @user.username}
          </span>
          <span class="text-xs text-[var(--xamt-muted)] mongol-text">
            @{@user.username}
          </span>
        </div>

        <span class="xamt-user-menu__divider" aria-hidden="true"></span>

        <.link
          id={@profile_link_id}
          navigate={~p"/profile/#{@user.username}"}
          class="xamt-user-menu__item mongol-text"
          role="menuitem"
        >
          <.icon name="hero-user-circle" class="w-4 h-4 shrink-0" />
          <span>{gettext("Profile")}</span>
        </.link>

        <.link
          navigate={~p"/saved"}
          class="xamt-user-menu__item mongol-text"
          role="menuitem"
        >
          <.icon name="hero-bookmark" class="w-4 h-4 shrink-0" />
          <span>{gettext("Saved")}</span>
        </.link>

        <.link
          navigate={~p"/settings"}
          class="xamt-user-menu__item mongol-text"
          role="menuitem"
        >
          <.icon name="hero-cog-6-tooth" class="w-4 h-4 shrink-0" />
          <span>{gettext("Settings")}</span>
        </.link>

        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="xamt-user-menu__item xamt-user-menu__item--danger mongol-text"
          role="menuitem"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="w-4 h-4 shrink-0" />
          <span>{gettext("Log out")}</span>
        </.link>

        <span class="xamt-user-menu__divider" aria-hidden="true"></span>

        <div class="xamt-user-menu__theme">
          <span class="text-xs text-[var(--xamt-muted)] mongol-text">
            {gettext("Theme")}
          </span>
          <Layouts.theme_palette id={@palette_id} />
        </div>
      </div>
    </details>
    """
  end
end
