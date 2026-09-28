defmodule XamtWeb.SearchPalette do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Helpers, only: [display_name: 1, safe_html: 2]

  attr :show, :boolean, default: false
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :current_scope, :map, required: true

  def search_palette(assigns) do
    ~H"""
    <div
      id="search-palette-root"
      phx-hook="SearchPalette"
      phx-window-keydown="close_search"
      phx-key="Escape"
    >
      <div
        :if={@show}
        id="search-palette"
        class="xamt-search-palette"
        data-search-open
        role="presentation"
      >
        <button
          type="button"
          id="search-palette-dismiss"
          class="xamt-search-palette__backdrop"
          phx-click="close_search"
          aria-label={gettext("Close search")}
        >
        </button>

        <div
          id="search-palette-panel"
          class="xamt-search-palette__panel"
          role="dialog"
          aria-modal="true"
          aria-labelledby="global-search-title"
        >
          <h2 id="global-search-title" class="sr-only">{gettext("Search messages")}</h2>

          <form
            id="global-search-form"
            phx-change="perform_search"
            phx-submit="perform_search"
            class="xamt-search-palette__form"
          >
            <.icon name="hero-magnifying-glass" class="xamt-search-palette__icon" />
            <label class="xamt-search-palette__field">
              <span class="sr-only">{gettext("Search messages")}</span>
              <textarea
                name="q"
                id="global-search-q"
                rows="1"
                placeholder={gettext("Search")}
                class="xamt-input mongol-input xamt-search-palette__input"
                phx-hook="MongolianIME"
                phx-debounce="300"
                inputmode="none"
                virtualkeyboardpolicy="manual"
                autocomplete="off"
                spellcheck="false"
                wrap="off"
              >{@search_query}</textarea>
            </label>
            <kbd class="xamt-search-palette__kbd">ESC</kbd>
          </form>

          <div id="global-search-results" class="xamt-search-palette__results">
            <p
              :if={@search_results == [] and @search_query != ""}
              id="global-search-empty"
              class="xamt-search-palette__empty"
            >
              {gettext("No results for \"%{query}\"", query: @search_query)}
            </p>

            <button
              :for={result <- @search_results}
              type="button"
              id={"global-search-hit-#{result.id}"}
              class="xamt-search-result"
              phx-click="open_global_search_result"
              phx-value-id={result.id}
              phx-value-server-slug={server_slug(result)}
              phx-value-channel-slug={channel_slug(result)}
            >
              <.message_result_body message={result} current_user_id={@current_scope.user.id} />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :current_user_id, :string, required: true

  def message_result_body(assigns) do
    ~H"""
    <div class="xamt-search-result__meta">
      <span class="xamt-search-result__author mongol-text">{display_name(@message.user)}</span>
      <div class="xamt-search-result__source">
        <span :if={@message.channel} class="xamt-search-result__channel mongol-text">
          #{@message.channel.name}
        </span>
        <time
          :if={@message.inserted_at}
          class="xamt-search-result__date"
          datetime={DateTime.to_iso8601(@message.inserted_at)}
        >
          {Calendar.strftime(@message.inserted_at, "%Y-%m-%d")}
        </time>
      </div>
    </div>
    <div class="xamt-search-result__content mongol-text">
      {raw(safe_html(@message, @current_user_id))}
    </div>
    """
  end

  defp server_slug(%{channel: %{server: %{slug: slug}}}), do: slug
  defp server_slug(_), do: nil

  defp channel_slug(%{channel: %{slug: slug}}), do: slug
  defp channel_slug(_), do: nil
end
