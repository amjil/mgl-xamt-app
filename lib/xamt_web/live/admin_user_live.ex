defmodule XamtWeb.AdminUserLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.Accounts.{Scope, User}
  alias Xamt.Servers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket
      |> change_user(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save_user(socket, socket.assigns.live_action, params)
  end

  def handle_event("save_profile", %{"user" => params}, socket) do
    target = socket.assigns.target_user

    case Accounts.update_user_profile(target, Map.take(params, ["display_name", "bio"])) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:target_user, user)
         |> assign(:user, user)
         |> assign(:profile_form, to_form(Accounts.change_user_profile(user), as: :user))
         |> put_flash(:info, gettext("Updated @%{username}", username: user.username))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, as: :user))}
    end
  end

  def handle_event("set_role", %{"role" => role}, socket) do
    target = socket.assigns.target_user

    if target.id == socket.assigns.current_scope.user.id do
      {:noreply, put_flash(socket, :error, gettext("Could not update role"))}
    else
      case Accounts.update_user_as_admin(socket.assigns.current_scope, target, %{
             "global_role" => role
           }) do
        {:ok, user} ->
          {:noreply,
           socket
           |> assign(:target_user, user)
           |> assign(:user, user)
           |> put_flash(:info, gettext("Updated @%{username}", username: user.username))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update role"))}
      end
    end
  end

  def handle_event("save_admin_account", %{"user" => params}, socket) do
    save_user(socket, :edit, params)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("Create user"))
    |> assign(:user, %User{})
    |> assign(:target_user, nil)
    |> assign(:profile_form, nil)
    |> assign(:servers, [])
    |> assign(:form, to_form(Accounts.change_user_admin_registration(%User{}), as: :user))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = Accounts.get_user!(id)
    servers = Servers.list_servers_for_user(Scope.for_user(user))

    socket
    |> assign(:page_title, gettext("Edit user"))
    |> assign(:user, user)
    |> assign(:target_user, user)
    |> assign(:servers, servers)
    |> assign(:profile_form, to_form(Accounts.change_user_profile(user), as: :user))
    |> assign(:form, to_form(Accounts.change_user_admin_update(user), as: :user))
  end

  defp change_user(%{assigns: %{live_action: :new}}, params) do
    Accounts.change_user_admin_registration(%User{}, params)
  end

  defp change_user(%{assigns: %{live_action: :edit, user: user}}, params) do
    Accounts.change_user_admin_update(user, params)
  end

  defp save_user(socket, :new, params) do
    case Accounts.create_user_as_admin(socket.assigns.current_scope, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Created @%{username}", username: user.username))
         |> assign(:form, to_form(Accounts.change_user_admin_registration(%User{}), as: :user))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to create users."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  defp save_user(socket, :edit, params) do
    case Accounts.update_user_as_admin(socket.assigns.current_scope, socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> maybe_refresh_scope(user)
         |> put_flash(:info, gettext("Updated @%{username}", username: user.username))
         |> push_navigate(to: ~p"/admin/users")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to update users."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  defp maybe_refresh_scope(socket, user) do
    current = socket.assigns.current_scope.user

    if current && current.id == user.id do
      assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})
    else
      socket
    end
  end

  defp role_options do
    [
      {gettext("User"), "user"},
      {gettext("Creator"), "creator"},
      {gettext("Admin"), "admin"}
    ]
  end

  defp role_label("admin"), do: gettext("Admin")
  defp role_label("creator"), do: gettext("Creator")
  defp role_label(_), do: gettext("Member")

  defp display_initial(%{display_name: name}) when is_binary(name) and name != "",
    do: String.first(name)

  defp display_initial(%{username: name}) when is_binary(name) and name != "",
    do: String.first(name)

  defp display_initial(_), do: "?"

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
      <%= if @live_action == :new do %>
        <.create_user_canvas form={@form} role_options={role_options()} />
      <% else %>
        <.edit_user_canvas
          target_user={@target_user}
          profile_form={@profile_form}
          form={@form}
          servers={@servers}
          current_scope={@current_scope}
        />
      <% end %>
    </Layouts.home>
    """
  end

  attr :form, :any, required: true
  attr :role_options, :list, required: true

  defp create_user_canvas(assigns) do
    ~H"""
    <main id="admin-create-user" class="xamt-home-canvas" phx-hook="MongolianScroll">
      <aside class="xamt-home-section">
        <div class="flex flex-row items-center justify-between h-full py-1">
          <div class="flex flex-row items-center gap-3">
            <.link
              navigate={~p"/admin/users"}
              class="xamt-icon-btn"
              id="admin-user-back"
              title={gettext("Back")}
            >
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>

            <h1 class="text-xl font-bold tracking-widest mongol-text">
              {gettext("Create user")}
            </h1>
          </div>
        </div>
      </aside>

      <section class="xamt-home-section">
        <header class="xamt-home-section__header">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-user-plus" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 class="font-bold text-sm mongol-text">{gettext("Account")}</h2>
          </div>
        </header>

        <.form
          for={@form}
          id="admin-create-user-form"
          phx-change="validate"
          phx-submit="save"
          class="xamt-home-card"
        >
          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Display name")}</span>
            <input
              type="text"
              name={@form[:display_name].name}
              id={@form[:display_name].id}
              value={@form[:display_name].value}
              class="xamt-bot-input mongol-input"
              phx-hook="MongolianIME"
              autocomplete="nickname"
              onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
            />
          </label>

          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Username")}</span>
            <input
              type="text"
              name={@form[:username].name}
              id={@form[:username].id}
              value={@form[:username].value}
              class="xamt-bot-input"
              autocomplete="off"
              spellcheck="false"
              required
            />
            <p
              :for={msg <- Enum.map(@form[:username].errors, &translate_error(&1))}
              class="text-xs text-red-500"
            >
              {msg}
            </p>
          </label>

          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Email")}</span>
            <input
              type="email"
              name={@form[:email].name}
              id={@form[:email].id}
              value={@form[:email].value}
              class="xamt-bot-input"
              autocomplete="off"
              spellcheck="false"
              required
            />
            <p
              :for={msg <- Enum.map(@form[:email].errors, &translate_error(&1))}
              class="text-xs text-red-500"
            >
              {msg}
            </p>
          </label>

          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Password")}</span>
            <input
              type="password"
              name={@form[:password].name}
              id={@form[:password].id}
              value={@form[:password].value}
              class="xamt-bot-input"
              autocomplete="new-password"
              minlength="8"
              maxlength="72"
              required
            />
          </label>

          <p class="text-xs text-[var(--xamt-muted)] mongol-text">
            {gettext("At least 8 characters, with English letters, a number, and a symbol.")}
          </p>

          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Confirm password")}</span>
            <input
              type="password"
              name={@form[:password_confirmation].name}
              id={@form[:password_confirmation].id}
              value={@form[:password_confirmation].value}
              class="xamt-bot-input"
              autocomplete="new-password"
              required
            />
          </label>

          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Role")}</span>
            <div
              id="admin-create-role-host"
              class="mn-select-host"
              phx-hook="MnSelect"
              phx-update="ignore"
            >
              <select
                id="admin-create-role-select"
                name={@form[:global_role].name}
                class="xamt-bot-input"
              >
                <option
                  :for={{label, value} <- @role_options}
                  value={value}
                  selected={to_string(@form[:global_role].value) == value}
                >
                  {label}
                </option>
              </select>
            </div>
          </label>

          <button
            type="submit"
            id="create-user-submit"
            class="xamt-btn xamt-btn--primary h-full px-3 font-bold text-xs mongol-text"
          >
            <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
            <span>{gettext("Create user")}</span>
          </button>
        </.form>
      </section>
    </main>
    """
  end

  attr :target_user, :map, required: true
  attr :profile_form, :any, required: true
  attr :form, :any, required: true
  attr :servers, :list, required: true
  attr :current_scope, :map, required: true

  defp edit_user_canvas(assigns) do
    ~H"""
    <main id="admin-user-detail-canvas" class="xamt-home-canvas" phx-hook="MongolianScroll">
      <%!-- Zone 1: back + identity --%>
      <aside class="xamt-home-section" id="admin-edit-user">
        <div class="flex flex-row items-center justify-between h-full py-1">
          <div class="flex flex-row items-center gap-3">
            <.link
              navigate={~p"/admin/users"}
              id="admin-user-back"
              class="xamt-icon-btn"
              title={gettext("Back")}
            >
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>

            <h1 class="text-xl font-bold tracking-widest mongol-text">
              {gettext("Edit user")}
            </h1>
          </div>

          <span class="text-xs font-mono text-[var(--xamt-muted)]">
            ID: {String.slice(@target_user.id, 0, 8)}
          </span>
        </div>

        <div class="xamt-user-strip justify-start gap-4">
          <div class="w-12 h-12 rounded-2xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-lg shrink-0 overflow-hidden">
            <%= if is_binary(@target_user.avatar) and @target_user.avatar != "" do %>
              <img src={@target_user.avatar} class="w-full h-full rounded-2xl object-cover" />
            <% else %>
              {display_initial(@target_user)}
            <% end %>
          </div>

          <div class="flex flex-row items-center gap-2">
            <span class="font-bold text-lg text-[var(--xamt-text)] mongol-text">
              {@target_user.display_name || @target_user.username}
            </span>
            <span class="text-xs text-[var(--xamt-muted)]">
              @{@target_user.username}
            </span>
          </div>

          <span class={[
            "xamt-role-pill",
            @target_user.global_role == "admin" && "xamt-role-pill--admin",
            @target_user.global_role == "creator" && "xamt-role-pill--creator",
            @target_user.global_role not in ["admin", "creator"] && "xamt-role-pill--member"
          ]}>
            {role_label(@target_user.global_role)}
          </span>

          <div class="text-xs text-[var(--xamt-muted)] font-mono mt-auto">
            {@target_user.email}
          </div>
        </div>
      </aside>

      <%!-- Zone 2: profile fields --%>
      <section class="xamt-home-section">
        <header class="xamt-home-section__header">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-pencil-square" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 class="font-bold text-sm mongol-text">{gettext("Profile")}</h2>
          </div>
        </header>

        <.form
          for={@profile_form}
          id="admin-edit-profile-form"
          phx-submit="save_profile"
          class="xamt-home-card"
        >
          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Display name")}</span>
            <input
              id="admin-user-display-name"
              type="text"
              name={@profile_form[:display_name].name}
              value={@profile_form[:display_name].value}
              placeholder={gettext("Display name")}
              class="xamt-bot-input mongol-input"
              phx-hook="MongolianIME"
              onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
            />
          </label>

          <label class="xamt-bot-field">
            <span class="xamt-label">{gettext("Bio")}</span>
            <textarea
              id="admin-user-bio"
              name={@profile_form[:bio].name}
              placeholder={gettext("Bio")}
              class="xamt-bot-input mongol-input !w-16"
              phx-hook="MongolianIME"
              onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
            >{Phoenix.HTML.Form.normalize_value("textarea", @profile_form[:bio].value)}</textarea>
          </label>

          <button
            type="submit"
            class="xamt-btn xamt-btn--primary h-full px-3 font-bold text-xs mongol-text"
          >
            <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
            <span>{gettext("Save")}</span>
          </button>
        </.form>
      </section>

      <%!-- Zone 3: role + account --%>
      <section class="xamt-home-section">
        <header class="xamt-home-section__header">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-shield-exclamation" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 class="font-bold text-sm mongol-text">{gettext("Role")}</h2>
          </div>
        </header>

        <div class="flex flex-col gap-3 h-full">
          <form
            :if={
              @current_scope.user.global_role == "admin" &&
                @target_user.id != @current_scope.user.id
            }
            id="admin-detail-role-form"
            phx-change="set_role"
            class="xamt-home-card"
          >
            <div class="font-bold text-xs text-[var(--xamt-accent)] mongol-text">
              {gettext("Role")}
            </div>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Role")}</span>
              <div
                id={"admin-detail-role-host-#{@target_user.global_role}"}
                class="mn-select-host"
                phx-hook="MnSelect"
                phx-update="ignore"
              >
                <select id="admin-detail-role-select" name="role" class="xamt-bot-input">
                  <option value="user" selected={@target_user.global_role == "user"}>
                    {gettext("Member")}
                  </option>
                  <option value="creator" selected={@target_user.global_role == "creator"}>
                    {gettext("Creator")}
                  </option>
                  <option value="admin" selected={@target_user.global_role == "admin"}>
                    {gettext("Admin")}
                  </option>
                </select>
              </div>
            </label>
          </form>

          <.form
            for={@form}
            id="admin-edit-user-form"
            phx-change="validate"
            phx-submit="save_admin_account"
            class="xamt-home-card"
          >
            <div class="font-bold text-xs text-[var(--xamt-accent)] mongol-text">
              {gettext("Account")}
            </div>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Username")}</span>
              <input
                type="text"
                name={@form[:username].name}
                id={@form[:username].id}
                value={@form[:username].value}
                class="xamt-bot-input"
                autocomplete="off"
                spellcheck="false"
                required
              />
              <p
                :for={msg <- Enum.map(@form[:username].errors, &translate_error(&1))}
                class="text-xs text-red-500"
              >
                {msg}
              </p>
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Email")}</span>
              <input
                type="email"
                name={@form[:email].name}
                id={@form[:email].id}
                value={@form[:email].value}
                class="xamt-bot-input"
                autocomplete="off"
                spellcheck="false"
                required
              />
              <p
                :for={msg <- Enum.map(@form[:email].errors, &translate_error(&1))}
                class="text-xs text-red-500"
              >
                {msg}
              </p>
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("New password")}</span>
              <input
                type="password"
                name={@form[:password].name}
                id={@form[:password].id}
                value={@form[:password].value}
                class="xamt-bot-input"
                autocomplete="new-password"
                minlength="8"
                maxlength="72"
              />
            </label>

            <p class="text-xs text-[var(--xamt-muted)] mongol-text">
              {gettext("Leave blank to keep the current password.")}
            </p>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Confirm password")}</span>
              <input
                type="password"
                name={@form[:password_confirmation].name}
                id={@form[:password_confirmation].id}
                value={@form[:password_confirmation].value}
                class="xamt-bot-input"
                autocomplete="new-password"
              />
            </label>

            <input type="hidden" name={@form[:global_role].name} value={@target_user.global_role} />

            <button
              type="submit"
              id="edit-user-submit"
              class="xamt-btn xamt-btn--primary h-full px-3 font-bold text-xs mongol-text"
            >
              <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Save user")}</span>
            </button>
          </.form>
        </div>
      </section>

      <%!-- Zone 4: joined communities --%>
      <section class="xamt-home-section">
        <header class="xamt-home-section__header">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-building-library" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 class="font-bold text-sm mongol-text">{gettext("Communities")}</h2>
          </div>
        </header>

        <div class="flex flex-col gap-2.5 h-full">
          <div
            :if={@servers == []}
            class="xamt-user-strip justify-center text-xs text-[var(--xamt-muted)] mongol-text"
          >
            {gettext("No communities yet")}
          </div>

          <div :for={srv <- @servers} class="xamt-user-strip justify-between">
            <span class="font-bold text-sm mongol-text">{srv.name}</span>
            <.link
              navigate={~p"/servers/#{srv.slug}"}
              class="text-xs text-[var(--xamt-accent)] hover:underline mongol-text"
            >
              {gettext("View")}
            </.link>
          </div>
        </div>
      </section>
    </main>
    """
  end
end
