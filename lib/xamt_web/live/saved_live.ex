defmodule XamtWeb.SavedLive do
  use XamtWeb, :live_view

  import XamtWeb.SearchPalette

  alias Xamt.Messages

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Saved"))
     |> assign_bookmarks()}
  end

  @impl true
  def handle_event("toggle_bookmark", %{"msg-id" => id}, socket) do
    case Messages.toggle_bookmark(socket.assigns.current_scope, id) do
      {:ok, _message} ->
        {:noreply, assign_bookmarks(socket)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Permission denied"))}

      {:error, :deleted} ->
        {:noreply, put_flash(socket, :error, gettext("Message was deleted"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update bookmark"))}
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
      <div class="xamt-home xamt-saved" id="saved-page">
        <header class="xamt-home__hero">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Library")}</p>
          <h1 class="xamt-home__title mongol-text">{gettext("Saved")}</h1>
          <p class="xamt-home__lead mongol-text">
            {gettext("Messages you starred, across every server you can still read.")}
          </p>
        </header>

        <section class="xamt-home__panel">
          <div class="xamt-home__toolbar">
            <h2 class="xamt-section-title mongol-text">{gettext("Bookmarks")}</h2>
            <button
              type="button"
              id="saved-open-search"
              class="xamt-btn xamt-btn--soft"
              phx-click="open_search"
            >
              <.icon name="hero-magnifying-glass" class="size-4" />
              <span>{gettext("Search")}</span>
              <kbd class="xamt-search-palette__kbd xamt-search-palette__kbd--inline">⌘K</kbd>
            </button>
          </div>

          <div
            :if={@bookmarks == []}
            id="saved-empty"
            class="xamt-empty xamt-empty--card"
          >
            <span class="xamt-ornament" aria-hidden="true"></span>
            <p class="mongol-text">{gettext("No saved messages yet.")}</p>
          </div>

          <div id="saved-list" class="xamt-saved__list">
            <article
              :for={message <- @bookmarks}
              id={"saved-msg-#{message.id}"}
              class="xamt-saved__card"
            >
              <.link
                id={"saved-jump-#{message.id}"}
                navigate={jump_path(message)}
                class="xamt-search-result xamt-saved__jump"
              >
                <.message_result_body
                  message={message}
                  current_user_id={@current_scope.user.id}
                />
              </.link>
              <button
                type="button"
                id={"unsave-message-#{message.id}"}
                class="xamt-saved__unsave"
                phx-click="toggle_bookmark"
                phx-value-msg-id={message.id}
                title={gettext("Remove bookmark")}
                aria-label={gettext("Remove bookmark")}
              >
                <.icon name="hero-star-solid" class="size-4" />
              </button>
            </article>
          </div>
        </section>
      </div>
    </Layouts.home>
    """
  end

  defp assign_bookmarks(socket) do
    assign(socket, :bookmarks, Messages.list_user_bookmarks(socket.assigns.current_scope))
  end

  defp jump_path(%{channel: %{slug: channel, server: %{slug: server}}, id: id})
       when is_binary(channel) and is_binary(server) and is_binary(id) do
    ~p"/servers/#{server}/#{channel}?highlight=#{id}"
  end

  defp jump_path(_), do: ~p"/saved"
end
