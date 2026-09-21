defmodule XamtWeb.HomeLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts.User
  alias Xamt.Servers
  alias Xamt.Servers.Server

  @impl true
  def mount(_params, _session, socket) do
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
     |> assign(:can_create_server?, can_create_server?(scope))}
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
  def handle_event("toggle_create", _params, socket) do
    if socket.assigns.can_create_server? do
      {:noreply, assign(socket, :show_create, !socket.assigns.show_create)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="xamt-page-inner">
      <Layouts.flash_group flash={@flash} current_scope={@current_scope} />
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
                {if @show_create, do: gettext("Cancel"), else: gettext("Create server")}
              </button>
            </div>

            <form
              :if={@show_create}
              id="create-server-form"
              phx-submit="create_server"
              class="xamt-form xamt-form--vertical"
            >
              <label class="xamt-label">
                <span class="xamt-field__label mongol-text">{gettext("Name")}</span>
                <input
                  type="text"
                  name="server[name]"
                  id="server_name"
                  required
                  class="xamt-input mongol-input"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                />
              </label>
              <label class="xamt-label">
                <span class="xamt-field__label mongol-text">{gettext("Description")}</span>
                <textarea
                  name="server[description]"
                  id="server_description"
                  rows="2"
                  class="xamt-input mongol-input"
                  phx-hook="MongolianIME"
                ></textarea>
              </label>
              <label class="xamt-label">
                <span class="xamt-field__label mongol-text">{gettext("Visibility")}</span>
                <select name="server[visibility]" id="server_visibility" class="xamt-select">
                  <option value="private">{gettext("Private — invite only")}</option>
                  <option value="public">{gettext("Public — anyone can find and join")}</option>
                </select>
              </label>
              <button
                type="submit"
                id="create-server-submit"
                class="xamt-btn xamt-btn--primary mongol-text"
              >
                {gettext("Create")}
              </button>
            </form>

            <ul class="xamt-server-list">
              <li :for={server <- @servers} class="xamt-server-list__item">
                <.link navigate={~p"/servers/#{server.slug}"} class="xamt-server-card">
                  <span class="xamt-server-card__icon">{server_initial(server.name)}</span>
                  <span class="xamt-server-card__meta">
                    <span class="xamt-server-card__name mongol-text">{server.name}</span>
                    <span class="xamt-server-card__slug">/{server.slug}</span>
                  </span>
                </.link>
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
                    <span class="xamt-server-card__name mongol-text">{server.name}</span>
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
            <.link navigate={~p"/register"} class="xamt-btn mongol-text">{gettext("Register")}</.link>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  defp server_initial(name) when is_binary(name) do
    name |> String.trim() |> String.first() || "?"
  end

  defp server_initial(_), do: "?"

  defp can_create_server?(%{user: %User{} = user}), do: User.can_create_server?(user)
  defp can_create_server?(_), do: false

  defp deny_create(socket) do
    socket
    |> assign(:show_create, false)
    |> put_flash(:error, gettext("You don't have permission to create a server"))
  end
end
