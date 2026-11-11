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
    user_id = socket.assigns.current_scope.user.id

    case Xamt.AuthRateLimit.check(:invite, user_id) do
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, gettext("Too many attempts. Try again shortly."))}

      :ok ->
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
      <main id="invite-panel" class="xamt-home-canvas" phx-hook="MongolianScroll">
        <aside class="xamt-home-section">
          <div class="flex flex-row items-center justify-between h-full py-1">
            <div class="flex flex-row items-center gap-3">
              <.link navigate={~p"/"} id="invite-back" class="xamt-icon-btn" title={gettext("Back")}>
                <.icon name="hero-arrow-left" class="w-5 h-5" />
              </.link>
              <span class="xamt-ornament !h-10" aria-hidden="true"></span>
              <p class="xamt-kicker mongol-text">{gettext("Invitation")}</p>
            </div>
          </div>
        </aside>

        <section class="xamt-home-section">
          <%= if @usable? do %>
            <div class="xamt-home-card items-center">
              <div class="flex flex-row items-center gap-3 h-full">
                <div class="w-12 h-12 rounded-2xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-lg shrink-0">
                  {String.first(@invite.server.name) || "?"}
                </div>
                <h1 class="text-xl font-bold mongol-text">
                  {upright_text(@invite.server.name)}
                </h1>
                <span class="text-xs text-[var(--xamt-muted)] font-mono">
                  /{@invite.server.slug}
                </span>
              </div>

              <p
                :if={@invite.server.description}
                class="text-sm text-[var(--xamt-muted)] mongol-text h-full px-1"
              >
                {upright_text(@invite.server.description)}
              </p>

              <button
                type="button"
                id="accept-invite"
                class="xamt-btn xamt-btn--primary h-full px-4 font-bold mongol-text"
                phx-click="accept"
              >
                <.icon name="hero-check-badge" class="w-5 h-5 mb-2" />
                <span>{gettext("Join server")}</span>
              </button>
            </div>
          <% else %>
            <div class="xamt-home-card justify-center items-center" id="invite-invalid">
              <span class="xamt-ornament" aria-hidden="true"></span>
              <p class="text-sm text-[var(--xamt-muted)] mongol-text">
                {gettext("This invitation is no longer valid.")}
              </p>
            </div>
          <% end %>
        </section>
      </main>
    </Layouts.home>
    """
  end
end
