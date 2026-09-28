defmodule XamtWeb.ServerLive.MessageList do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Helpers
  import XamtWeb.ServerLive.MessageItem

  def messages_region(assigns) do
    ~H"""
    <div class="xamt-messages-region">
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
        data-viewing-latest={to_string(@viewing_latest?)}
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
            <div
              id={dom_id}
              class="xamt-date-divider"
              data-date={message.date}
              role="separator"
            >
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
              polls={@polls}
              my_poll_votes={@my_poll_votes}
              timezone_offset={@timezone_offset}
            />
          <% end %>
        <% end %>

        <%!-- Optimistic offline bubbles. Lives inside the stream container so
             pending columns sit at the latest (right) edge, but is ignored by
             LiveView patches so stream resets do not wipe the queue. --%>
        <div
          id="offline-pending"
          class="xamt-offline-pending"
          phx-update="ignore"
          data-channel-id={@active_channel && @active_channel.id}
          data-waiting-label={gettext("Waiting for network…")}
        >
        </div>
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
