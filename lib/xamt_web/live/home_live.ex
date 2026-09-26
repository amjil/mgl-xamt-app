defmodule XamtWeb.HomeLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts.User
  alias Xamt.Servers
  alias Xamt.Servers.Permissions
  alias Xamt.Servers.Server
  alias Xamt.SiteSettings
  alias Xamt.Slug

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SiteSettings.subscribe()

    scope = socket.assigns.current_scope

    {servers, discoverable} =
      if scope && scope.user do
        {Servers.list_servers_for_user(scope), Servers.list_discoverable_servers(scope)}
      else
        {[], []}
      end

    {:ok,
     socket
     |> assign(:page_title, "Xamt")
     |> assign(:servers, servers)
     |> assign(:discoverable, discoverable)
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
    {:noreply, assign(socket, :registration_enabled?, setting.registration_enabled)}
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
    <Layouts.home flash={@flash} current_scope={@current_scope}>
      <div class="xamt-home">
        <header class="xamt-home__hero">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Community")}</p>
          <p class="xamt-brand">Xamt</p>
          <h1 class="xamt-home__title mongol-text">{gettext("Mongolian community")}</h1>
          <p class="xamt-home__lead mongol-text">
            {gettext("Traditional Mongolian community & realtime chat")}
          </p>
        </header>

        <%= if @current_scope && @current_scope.user do %>
          <section class="xamt-home__panel">
            <div class="xamt-home__toolbar">
              <h2 class="xamt-section-title mongol-text">{gettext("Your servers")}</h2>
              <button
                :if={@can_create_server?}
                type="button"
                id="toggle-create-server"
                class="xamt-btn xamt-btn--soft mongol-text"
                phx-click="toggle_create"
              >
                {gettext("Create server")}
              </button>
            </div>

            <ul class="xamt-server-list">
              <li
                :for={server <- @servers}
                class={[
                  "xamt-server-list__item",
                  viewer_can_manage?(server, @current_scope) && "has-settings"
                ]}
              >
                <.link navigate={~p"/servers/#{server.slug}"} class="xamt-server-card">
                  <span class="xamt-server-card__icon">{server_initial(server.name)}</span>
                  <span class="xamt-server-card__meta">
                    <span class="xamt-server-card__name mongol-text">
                      {upright_text(server.name)}
                    </span>
                    <span
                      :if={present_text?(server.description)}
                      class="xamt-server-card__desc mongol-text"
                    >
                      {upright_text(server.description)}
                    </span>
                  </span>
                </.link>
                <button
                  :if={viewer_can_manage?(server, @current_scope)}
                  type="button"
                  id={"edit-server-#{server.id}"}
                  class="xamt-server-card__settings xamt-icon-btn"
                  phx-click="edit_server_request"
                  phx-value-id={server.id}
                  title={gettext("Server settings")}
                  aria-label={gettext("Server settings")}
                >
                  <.icon name="hero-cog-6-tooth" class="size-4" />
                </button>
              </li>
            </ul>

            <div :if={@servers == []} class="xamt-empty xamt-empty--card">
              <span class="xamt-ornament" aria-hidden="true"></span>
              <p class="mongol-text">
                <%= if @can_create_server? do %>
                  {gettext("No servers yet. Create one to start chatting.")}
                <% else %>
                  {gettext("No servers yet. Join a public server or wait for an invite.")}
                <% end %>
              </p>
            </div>
          </section>

          <section :if={@discoverable != []} class="xamt-home__panel" id="discover-panel">
            <div class="xamt-home__toolbar">
              <h2 class="xamt-section-title mongol-text">{gettext("Discover")}</h2>
            </div>

            <ul class="xamt-server-list">
              <li :for={server <- @discoverable} class="xamt-server-list__item">
                <.link navigate={~p"/servers/#{server.slug}"} class="xamt-server-card">
                  <span class="xamt-server-card__icon">{server_initial(server.name)}</span>
                  <span class="xamt-server-card__meta">
                    <span class="xamt-server-card__name mongol-text">
                      {upright_text(server.name)}
                    </span>
                    <span class="xamt-server-card__slug">/{server.slug}</span>
                  </span>
                </.link>
              </li>
            </ul>
          </section>
        <% else %>
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
        <% end %>
      </div>

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
              id="server_slug"
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
                id="create-server-submit"
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
