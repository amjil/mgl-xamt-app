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
      <main id="saved-page" class="xamt-home-canvas xamt-saved" phx-hook="MongolianScroll">
        <%!-- 第 1 区：返回导航、书签总数与全局搜索入口 --%>
        <aside class="xamt-home-section">
          <div class="flex flex-row items-center justify-between h-full py-1">
            <div class="flex flex-row items-center gap-3">
              <.link navigate={~p"/"} class="xamt-icon-btn" title={gettext("Back to home")}>
                <.icon name="hero-arrow-left" class="w-5 h-5" />
              </.link>

              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-bookmark-square" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
                <h1 class="text-xl font-bold tracking-widest mongol-text">
                  {gettext("Saved")}
                </h1>
              </div>
            </div>

            <div class="flex flex-row items-center gap-3">
              <button
                type="button"
                id="saved-open-search"
                class="xamt-btn xamt-btn--soft py-3 px-2 text-xs font-bold"
                phx-click="open_search"
              >
                <.icon name="hero-magnifying-glass" class="size-4 mb-1" />
                <span class="mongol-text">{gettext("Search")}</span>
                <kbd class="xamt-search-palette__kbd xamt-search-palette__kbd--inline">⌘K</kbd>
              </button>
            </div>
          </div>

          <div class="xamt-home-card justify-between">
            <div class="flex flex-row items-center gap-2">
              <span class="xamt-kicker mongol-text">{gettext("Library")}</span>
              <p class="text-xs text-[var(--xamt-muted)] mongol-text leading-relaxed">
                {gettext("Messages you starred, across every server you can still read.")}
              </p>
            </div>

            <div class="flex flex-row items-center gap-1.5 mt-auto text-xs font-bold text-[var(--xamt-accent)]">
              <.icon name="hero-star-solid" class="w-4 h-4 shrink-0" />
              <span>{length(@bookmarks)}</span>
            </div>
          </div>
        </aside>

        <%!-- 第 2 区：收藏消息画卷列表 --%>
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-star" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm mongol-text">{gettext("Bookmarks")}</h2>
            </div>
            <span class="text-xs font-bold text-[var(--xamt-muted)]">
              {length(@bookmarks)}
            </span>
          </header>

          <div
            :if={@bookmarks == []}
            id="saved-empty"
            class="xamt-home-card justify-center items-center text-xs text-[var(--xamt-muted)]"
          >
            <span class="xamt-ornament" aria-hidden="true"></span>
            <p class="mongol-text">{gettext("No saved messages yet.")}</p>
          </div>

          <div :if={@bookmarks != []} id="saved-list" class="flex flex-col gap-3 h-full">
            <article
              :for={message <- @bookmarks}
              id={"saved-msg-#{message.id}"}
              class="xamt-home-card relative pr-3"
            >
              <.link
                id={"saved-jump-#{message.id}"}
                navigate={jump_path(message)}
                class="xamt-search-result xamt-saved__jump h-full !max-w-none !p-0"
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
      </main>
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
