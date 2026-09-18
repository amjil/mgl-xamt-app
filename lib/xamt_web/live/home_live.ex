defmodule XamtWeb.HomeLive do
  use XamtWeb, :live_view

  alias Xamt.Servers
  alias Xamt.Servers.Server

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    servers =
      if scope && scope.user do
        Servers.list_servers_for_user(scope)
      else
        []
      end

    {:ok,
     socket
     |> assign(:page_title, "Xamt")
     |> assign(:servers, servers)
     |> assign(:form, to_form(Servers.change_server(%Server{}), as: :server))
     |> assign(:show_create, false)}
  end

  @impl true
  def handle_event("toggle_create", _params, socket) do
    {:noreply, assign(socket, :show_create, !socket.assigns.show_create)}
  end

  def handle_event("create_server", %{"server" => params}, socket) do
    scope = socket.assigns.current_scope

    case Servers.create_server(scope, params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Server created"))
         |> push_navigate(to: ~p"/servers/#{server.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :server), show_create: true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="xamt-page-inner">
      <Layouts.flash_group flash={@flash} />
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
                {gettext("No servers yet. Create one to start chatting.")}
              </p>
            </div>
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
end
