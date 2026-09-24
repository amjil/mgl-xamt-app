defmodule XamtWeb.AdminUsersLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> assign(:query, "")
     |> assign_users("")}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign_users(query)}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  defp assign_users(socket, query) do
    {:ok, users} = Accounts.search_users_as_admin(socket.assigns.current_scope, query)

    socket
    |> assign(:users_count, length(users))
    |> stream(:users, users, reset: true)
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}) when is_binary(name), do: name
  defp display_name(_), do: "?"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="xamt-stack" id="admin-users-page">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Site")}</p>
        </div>
        <.header>
          <span class="mongol-text">{gettext("Users")}</span>
          <:subtitle>
            {gettext("Find an account and update their details.")}
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/admin/users/new"}
              id="admin-users-create"
              class="xamt-btn xamt-btn--primary mongol-text"
            >
              {gettext("Create user")}
            </.link>
          </:actions>
        </.header>

        <.form
          for={to_form(%{"q" => @query})}
          id="admin-users-search"
          phx-change="search"
          phx-submit="search"
          class="xamt-form xamt-form--vertical xamt-form--compact xamt-admin-users__search"
        >
          <.input
            type="text"
            name="q"
            id="admin-users-q"
            value={@query}
            label={gettext("Search users")}
            class="xamt-input mongol-input"
            phx-hook="MongolianIME"
            phx-debounce="300"
            autocomplete="off"
            spellcheck="false"
          />
        </.form>

        <p id="admin-users-count" class="xamt-muted mongol-text">
          {gettext("%{count} accounts", count: @users_count)}
        </p>

        <div id="admin-users" class="xamt-admin-users__list" phx-update="stream">
          <div id="admin-users-empty" class="hidden only:block xamt-admin-users__empty mongol-text">
            <%= if @query == "" do %>
              {gettext("No users yet")}
            <% else %>
              {gettext("No matching users")}
            <% end %>
          </div>
          <article
            :for={{id, user} <- @streams.users}
            id={id}
            class={[
              "xamt-admin-user",
              RoleHelper.get_role_ui_config(user).accent_class
            ]}
          >
            <% role_ui = RoleHelper.get_role_ui_config(user) %>
            <.avatar user={user} id={"admin-user-avatar-#{user.id}"} class="xamt-avatar" />
            <p class={["xamt-admin-user__name mongol-text", role_ui.color_class]}>
              {display_name(user)}
            </p>
            <p class="xamt-admin-user__username">@{user.username}</p>
            <p class="xamt-admin-user__email">{user.email}</p>
            <div :if={role_ui.label} class={["xamt-role-badge", role_ui.bg_class]}>
              <.icon name={role_ui.icon} class="w-3 h-3 shrink-0" />
              <span>{role_ui.label}</span>
            </div>
            <.link
              navigate={~p"/admin/users/#{user.id}/edit"}
              id={"admin-user-edit-#{user.id}"}
              class="xamt-btn xamt-btn--soft xamt-btn--sm mongol-text"
            >
              {gettext("Edit")}
            </.link>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
