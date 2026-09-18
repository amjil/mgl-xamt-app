defmodule XamtWeb.InviteLive do
  use XamtWeb, :live_view

  alias Xamt.Servers
  alias Xamt.Servers.Invite

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    invite = Servers.get_invite_by_code(code)

    {:ok,
     socket
     |> assign(:page_title, gettext("Invitation"))
     |> assign(:code, code)
     |> assign(:invite, invite)
     |> assign(:usable?, invite != nil and Invite.usable?(invite))}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    case Servers.redeem_invite(socket.assigns.current_scope, socket.assigns.code) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Joined %{name}", name: server.name))
         |> push_navigate(to: ~p"/servers/#{server.slug}")}

      {:error, :not_found} ->
        {:noreply, assign(socket, invite: nil, usable?: false)}

      {:error, _} ->
        {:noreply, assign(socket, :usable?, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="xamt-stack" id="invite-panel">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Invitation")}</p>
        </div>

        <%= if @usable? do %>
          <.header>
            <span class="mongol-text">{@invite.server.name}</span>
            <:subtitle>
              <span class="xamt-upright">/{@invite.server.slug}</span>
            </:subtitle>
          </.header>

          <p :if={@invite.server.description} class="xamt-profile__bio mongol-text">
            {@invite.server.description}
          </p>

          <button
            type="button"
            id="accept-invite"
            class="xamt-btn xamt-btn--primary mongol-text"
            phx-click="accept"
          >
            {gettext("Join server")}
          </button>
        <% else %>
          <div class="xamt-empty xamt-empty--card" id="invite-invalid">
            <span class="xamt-ornament" aria-hidden="true"></span>
            <p class="mongol-text">{gettext("This invitation is no longer valid.")}</p>
          </div>
        <% end %>

        <.link navigate={~p"/"} id="invite-back" class="xamt-btn mongol-text">
          {gettext("Back")}
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
