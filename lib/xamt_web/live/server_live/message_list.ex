defmodule XamtWeb.ServerLive.MessageList do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Helpers
  import XamtWeb.ServerLive.MessageItem
  alias Xamt.Messages

  def messages_region(assigns) do
    ~H"""
    <div class="xamt-messages-region">
      <div :if={@search_results} id="search-results" class="xamt-search-results">
        <p class="xamt-search-results__head mongol-text">
          {gettext("Search results")}
        </p>
        <p :if={@search_results == []} class="xamt-empty mongol-text">
          {gettext("No matches.")}
        </p>
        <button
          :for={message <- @search_results}
          type="button"
          id={"search-hit-#{message.id}"}
          class="xamt-search-hit"
          phx-click="open_search_result"
          phx-value-id={message.id}
          phx-value-channel-id={message.channel_id}
        >
          <span class="xamt-quote__author mongol-text">{display_name(message.user)}</span>
          <span :if={message.channel} class="xamt-search-hit__channel mongol-text">
            <span class="xamt-channel-hash">#</span>
            {message.channel.name}
          </span>
          <span class="xamt-quote__text mongol-text">{Messages.excerpt(message)}</span>
        </button>
      </div>
      <div
        :if={@messages_empty?}
        id="messages-empty"
        class="xamt-empty xamt-empty--messages"
      >
        <span class="xamt-ornament" aria-hidden="true"></span>
        <p class="mongol-text">{gettext("No messages yet. Write the first one.")}</p>
      </div>

      <div
        id="message-list"
        class="xamt-messages"
        phx-update="stream"
        phx-hook="MessageList"
        data-highlight={@highlight_id}
        data-channel-id={@active_channel && @active_channel.id}
      >
        <div
          :if={@has_more_messages}
          id="messages-infinite-scroll"
          phx-hook="InfiniteScroll"
          data-event="load_older"
          class="xamt-scroll-sentinel"
        >
        </div>

        <%= for {dom_id, message} <- @streams.messages do %>
          <%= if date_divider?(message) do %>
            <div id={dom_id} class="xamt-date-divider" role="separator">
              <span class="xamt-date-divider__text">-- {message.date} --</span>
            </div>
          <% else %>
            <.message_item
              message={message}
              dom_id={dom_id}
              current_scope={@current_scope}
              editing_message_id={@editing_message_id}
              can_manage_messages?={@can_manage_messages?}
              reactions={@reactions}
              timezone_offset={@timezone_offset}
            />
          <% end %>
        <% end %>
      </div>

      <%!-- Edge indicator: MessageList toggles .is-visible + unread count --%>
      <button
        type="button"
        id="jump-latest"
        class="xamt-jump-latest mongol-text"
        phx-update="ignore"
        aria-hidden="true"
        aria-label={gettext("New messages")}
      >
        <span id="jump-latest-count" class="xamt-jump-latest__count">0</span>
        <span class="xamt-jump-latest__label">{gettext("New messages")}</span>
        <.icon name="hero-arrow-right" class="size-4 xamt-jump-latest__icon" />
      </button>
    </div>
    """
  end
end
