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
        X
      </.link>
    </aside>
    """
  end

  def channels_rail(assigns) do
    ~H"""
    <aside class="xamt-rail xamt-rail--channels">
      <div class="xamt-rail__pane xamt-rail__pane--top">
        <header id="server-info" class="xamt-rail__header">
          <h1 class="xamt-rail__title mongol-text">{upright_text(@server.name)}</h1>
        </header>

        <div class="xamt-rail__section">
          <div class="xamt-rail__section-head">
            <span class="mongol-text">{gettext("Channels")}</span>
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

          <nav class="xamt-channel-nav">
            <div :for={ch <- @channels} class="xamt-channel-item">
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
      <form
        id="channel-search"
        phx-change="search"
        phx-submit="search"
        class={["xamt-search", @mobile_search? && "is-open"]}
      >
        <button
          type="button"
          id="mobile-nav-search"
          class="xamt-icon-btn xamt-search__toggle"
          phx-click={
            if @mobile_search? do
              JS.push("toggle_mobile_search")
            else
              JS.push("toggle_mobile_search") |> JS.focus(to: "#channel-search-q")
            end
          }
          aria-label={gettext("Search")}
          aria-expanded={@mobile_search?}
        >
          <.icon name="hero-magnifying-glass" class="size-5" />
        </button>
        <label class="xamt-search__field">
          <span class="sr-only">{gettext("Search")}</span>
          <textarea
            name="q"
            id="channel-search-q"
            rows="1"
            placeholder={gettext("Search")}
            class="xamt-input mongol-input"
            phx-hook="MongolianIME"
            inputmode="none"
            virtualkeyboardpolicy="manual"
            autocomplete="off"
            wrap="off"
          >{@search_q}</textarea>
        </label>
        <button
          :if={@search_results}
          type="button"
          id="clear-search"
          class="xamt-icon-btn"
          phx-click="clear_search"
          aria-label={gettext("Clear search")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </form>
      <button
        type="button"
        id="mobile-nav-server"
        class="xamt-mobile-nav__btn xamt-mobile-nav__server"
        phx-click="toggle_server_menu"
        aria-label={gettext("Server info")}
        aria-expanded={@show_server_menu}
        aria-haspopup="dialog"
      >
        <.icon name="hero-information-circle" class="size-5" />
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
    </header>
    """
  end
end
