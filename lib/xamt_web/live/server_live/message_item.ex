defmodule XamtWeb.ServerLive.MessageItem do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Helpers
  alias Xamt.Messages
  alias Xamt.Messages.LinkPreview

  attr :message, :map, required: true
  attr :dom_id, :string, required: true
  attr :current_scope, :map, required: true
  attr :editing_message_id, :any, default: nil
  attr :can_manage_messages?, :boolean, default: false
  attr :reactions, :map, default: %{}
  attr :polls, :map, default: %{}
  attr :my_poll_votes, :map, default: %{}
  attr :timezone_offset, :integer, default: 0

  def message_item(assigns) do
    preview = link_preview(assigns.message)

    assigns =
      assign(assigns,
        preview: preview,
        embed_src: preview && LinkPreview.iframe_src(preview),
        embed_audio: preview && LinkPreview.audio_sample_url(preview),
        embed_image: preview && LinkPreview.preview_image(preview),
        embed_href: preview && LinkPreview.page_url(preview)
      )

    ~H"""
    <article
      id={@dom_id}
      class={[
        "xamt-message group",
        mentioned?(@message, @current_scope.user) && "xamt-message--mentioned",
        @editing_message_id == @message.id && "xamt-message--editing",
        deleted?(@message) && "xamt-message--deleted",
        not header_visible?(@message) && "xamt-message--grouped"
      ]}
      data-message-id={@message.id}
      data-inserted-at={DateTime.to_iso8601(@message.inserted_at)}
    >
      <div
        id={"msg-header-#{@message.id}"}
        class={[
          "xamt-message__header",
          not header_visible?(@message) && "xamt-message__header--spacer"
        ]}
        aria-hidden={not header_visible?(@message)}
      >
        <.status_avatar
          :if={header_visible?(@message)}
          user={@message.user}
          class="xamt-message__avatar"
        />
      </div>
      <time
        class="xamt-message__time"
        datetime={DateTime.to_iso8601(@message.inserted_at)}
      >
        {format_time(@message.inserted_at, @timezone_offset)}
      </time>
      <%= if deleted?(@message) do %>
        <div class="xamt-message__body">
          <header :if={header_visible?(@message)} class="xamt-message__meta">
            <strong class="xamt-message__username mongol-text">
              {display_name(@message.user)}
            </strong>
          </header>
          <div
            id={"msg-tombstone-#{@message.id}"}
            class="xamt-message__tombstone mongol-text"
          >
            <.icon name="hero-trash" class="size-4" />
            {gettext("This message was deleted")}
          </div>
        </div>
      <% else %>
        <div class="xamt-message__body">
          <button
            :if={@message.reply_to}
            type="button"
            class="xamt-quote"
            phx-click={
              JS.dispatch("xamt:highlight",
                detail: %{target_id: "messages-#{@message.reply_to_id}"}
              )
            }
            title={gettext("Jump to the quoted message")}
          >
            <span class="xamt-quote__mark" aria-hidden="true">↳</span>
            <span class="xamt-quote__author mongol-text">
              {display_name(@message.reply_to.user)}
            </span>
            <span class="xamt-quote__text mongol-text">
              <%= if deleted?(@message.reply_to) do %>
                {gettext("This message was deleted")}
              <% else %>
                {Messages.excerpt(@message.reply_to)}
              <% end %>
            </span>
          </button>
          <header
            :if={header_visible?(@message) or edited?(@message)}
            class="xamt-message__meta"
          >
            <strong
              :if={header_visible?(@message)}
              class="xamt-message__username mongol-text"
            >
              {display_name(@message.user)}
            </strong>
            <span :if={edited?(@message)} class="xamt-message__edited">
              {gettext("edited")}
            </span>
          </header>
          <div
            id={"msg-content-#{@message.id}"}
            class={[
              "xamt-message__content mongol-text",
              collapsible_text?(@message) && "relative"
            ]}
          >
            <%= if url = audio_src(@message) do %>
              <div class="xamt-message__audio">
                <audio
                  id={"msg-audio-#{@message.id}"}
                  class="xamt-audio-player"
                  controls
                  preload="metadata"
                  src={url}
                >
                  {gettext("Voice message")}
                </audio>
              </div>
            <% else %>
              <%= if images = gallery_images(@message) do %>
                <%= if caption_html?(@message) do %>
                  {raw(safe_html(@message, @current_scope.user.id))}
                <% end %>
                <% total = length(images) %>
                <% visible = Enum.take(images, 8) %>
                <% overflow? = total > 8 %>
                <div
                  id={"gallery-#{@message.id}"}
                  class="xamt-media-grid"
                  data-count={gallery_count_attr(total)}
                >
                  <button
                    :for={{img, index} <- Enum.with_index(visible)}
                    type="button"
                    id={"gallery-#{@message.id}-#{index}"}
                    class="xamt-media-grid__cell"
                    phx-click="open_lightbox"
                    phx-value-msg-id={@message.id}
                    phx-value-index={index}
                  >
                    <img
                      src={img["thumb"]}
                      alt={gettext("User uploaded media")}
                      loading="lazy"
                    />
                    <span
                      :if={overflow? and index == 7}
                      class="xamt-media-grid__more"
                    >
                      +{total - 8}
                    </span>
                  </button>
                </div>
              <% else %>
                <%= if poll = Map.get(@polls, @message.id) do %>
                  <% selected = Map.get(@my_poll_votes, poll.id, MapSet.new()) %>
                  <% total_votes =
                    max(Enum.sum(Enum.map(poll.options, & &1.votes_count)), 1) %>
                  <div
                    id={"poll-card-#{poll.id}"}
                    class="xamt-poll"
                    data-poll-id={poll.id}
                  >
                    <div class="xamt-poll__head">
                      <.icon name="hero-chart-bar" class="size-5 xamt-poll__icon" />
                      <h4 class="xamt-poll__question mongol-text">{poll.question}</h4>
                      <button
                        :if={
                          Map.get(poll, :results_open, true) or
                            @message.user_id == @current_scope.user.id
                        }
                        type="button"
                        id={"poll-details-#{poll.id}"}
                        class="xamt-poll__details"
                        phx-click="open_poll_details"
                        phx-value-poll-id={poll.id}
                        title={gettext("Details")}
                        aria-label={gettext("Poll details")}
                      >
                        <.icon name="hero-users" class="size-5" />
                      </button>
                    </div>

                    <div id={"poll-#{poll.id}"} class="xamt-poll__options">
                      <div
                        :for={option <- poll.options}
                        class={[
                          "xamt-poll__option",
                          MapSet.member?(selected, option.id) && "is-selected"
                        ]}
                      >
                        <% percent = round(option.votes_count / total_votes * 100) %>
                        <button
                          type="button"
                          id={"poll-vote-#{option.id}"}
                          phx-click="cast_vote"
                          phx-value-poll-id={poll.id}
                          phx-value-option-id={option.id}
                          class="xamt-poll__btn"
                        >
                          <div
                            class="xamt-poll__bar poll-bar"
                            data-option-id={option.id}
                            style={"--poll-pct: #{percent}%;"}
                          >
                          </div>
                          <span class="xamt-poll__option-text mongol-text">{option.text}</span>
                        </button>
                        <span
                          class="xamt-poll__percent poll-percent"
                          data-option-id={option.id}
                        >
                          {percent}%
                        </span>
                      </div>
                    </div>

                    <div class="xamt-poll__footer">
                      <%= if poll.allow_multiple do %>
                        <span class="xamt-poll__meta mongol-text">{gettext("Multiple answers")}</span>
                      <% else %>
                        <span class="xamt-poll__meta mongol-text">{gettext("Single answer")}</span>
                      <% end %>
                      <span class="xamt-poll__total">
                        <span class="mongol-text">{gettext("Total")}</span>
                        <span class="poll-total-count">
                          {Enum.sum(Enum.map(poll.options, & &1.votes_count))}
                        </span>
                        <span class="mongol-text">{gettext("votes")}</span>
                      </span>
                    </div>
                  </div>
                <% else %>
                  <div
                    id={"msg-body-#{@message.id}"}
                    class={[
                      "xamt-text-body",
                      long_text?(@message) && "xamt-text-collapsed"
                    ]}
                  >
                    {raw(safe_html(@message, @current_scope.user.id))}
                  </div>
                  <%= if long_text?(@message) do %>
                    <div
                      id={"msg-toggle-#{@message.id}"}
                      class="xamt-read-more-mask"
                    >
                      <button
                        type="button"
                        id={"msg-read-more-#{@message.id}"}
                        class="xamt-btn-read-more hover:bg-[color-mix(in_srgb,var(--xamt-accent)_85%,black)] transition-colors"
                        phx-click={
                          JS.remove_class("xamt-text-collapsed",
                            to: "#msg-body-#{@message.id}"
                          )
                          |> JS.add_class("is-expanded",
                            to: "#msg-toggle-#{@message.id}"
                          )
                          |> JS.set_attribute({"hidden", ""},
                            to: "#msg-read-more-#{@message.id}"
                          )
                          |> JS.remove_attribute("hidden",
                            to: "#msg-read-less-#{@message.id}"
                          )
                        }
                      >
                        {gettext("Read more")}
                        <.icon name="hero-chevron-right" class="w-4 h-4 mt-1" />
                      </button>
                      <button
                        type="button"
                        id={"msg-read-less-#{@message.id}"}
                        class="xamt-btn-read-more hover:bg-[color-mix(in_srgb,var(--xamt-accent)_85%,black)] transition-colors"
                        hidden
                        phx-click={
                          JS.add_class("xamt-text-collapsed",
                            to: "#msg-body-#{@message.id}"
                          )
                          |> JS.remove_class("is-expanded",
                            to: "#msg-toggle-#{@message.id}"
                          )
                          |> JS.remove_attribute("hidden",
                            to: "#msg-read-more-#{@message.id}"
                          )
                          |> JS.set_attribute({"hidden", ""},
                            to: "#msg-read-less-#{@message.id}"
                          )
                        }
                      >
                        {gettext("Show less")}
                        <.icon name="hero-chevron-left" class="w-4 h-4 mt-1" />
                      </button>
                    </div>
                  <% end %>
                <% end %>
              <% end %>
            <% end %>
            <%= if @preview do %>
              <div id={"msg-embed-#{@message.id}"} class="xamt-embed-island">
                <%= if @embed_src do %>
                  <div class="xamt-embed-video">
                    <iframe
                      id={"msg-embed-frame-#{@message.id}"}
                      src={@embed_src}
                      title={@preview["title"] || gettext("Embedded video")}
                      sandbox={LinkPreview.iframe_sandbox()}
                      allow={LinkPreview.iframe_allow()}
                      allowfullscreen
                      referrerpolicy="no-referrer"
                      loading="lazy"
                    >
                    </iframe>
                  </div>
                <% else %>
                  <%= if @preview["type"] == "audio_book" do %>
                    <div id={"msg-embed-audio-#{@message.id}"} class="xamt-embed-audio">
                      <img
                        :if={@embed_image}
                        src={@embed_image}
                        alt=""
                        class="xamt-embed-audio__cover"
                        loading="lazy"
                        referrerpolicy="no-referrer"
                      />
                      <div class="xamt-embed-audio__body">
                        <a
                          :if={@preview["title"] && @embed_href}
                          href={@embed_href}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="xamt-embed-audio__title"
                        >
                          {@preview["title"]}
                        </a>
                        <p class="xamt-embed-audio__meta">
                          {gettext("From the audiobook library")}
                        </p>
                        <audio
                          :if={@embed_audio}
                          id={"msg-embed-sample-#{@message.id}"}
                          controls
                          preload="none"
                          src={@embed_audio}
                        >
                          {gettext("Audio sample")}
                        </audio>
                      </div>
                    </div>
                  <% else %>
                    <a
                      :if={@embed_href}
                      id={"msg-preview-#{@message.id}"}
                      href={@embed_href}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="xamt-link-preview"
                    >
                      <img
                        :if={@embed_image}
                        src={@embed_image}
                        alt={@preview["title"] || ""}
                        class="xamt-link-preview__img"
                        loading="lazy"
                        referrerpolicy="no-referrer"
                      />
                      <div class="xamt-link-preview__body">
                        <strong :if={@preview["title"]} class="xamt-link-preview__title">
                          {@preview["title"]}
                        </strong>
                        <p :if={@preview["description"]} class="xamt-link-preview__desc">
                          {@preview["description"]}
                        </p>
                      </div>
                    </a>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>
          <div class="xamt-reactions">
            <details
              id={"msg-menu-#{@message.id}"}
              class="xamt-message__menu"
              phx-click-away={JS.remove_attribute("open")}
            >
              <summary
                class="xamt-message__menu-toggle"
                title={gettext("Message actions")}
                aria-label={gettext("Message actions")}
              >
                <.icon name="hero-ellipsis-vertical" class="size-4" />
              </summary>
              <div
                class="xamt-message__actions"
                role="toolbar"
                aria-label={gettext("Message actions")}
              >
                <button
                  type="button"
                  id={"reply-message-#{@message.id}"}
                  class="xamt-message__action"
                  phx-click="reply_message"
                  phx-value-id={@message.id}
                  title={gettext("Reply")}
                  aria-label={gettext("Reply")}
                >
                  <.icon name="hero-arrow-uturn-left" class="size-4" />
                </button>
                <button
                  :if={
                    @message.user_id == @current_scope.user.id and
                      is_nil(audio_src(@message)) and
                      @message.content_type != "poll"
                  }
                  type="button"
                  id={"edit-message-#{@message.id}"}
                  class="xamt-message__action"
                  phx-click="edit_message"
                  phx-value-id={@message.id}
                  title={gettext("Edit")}
                  aria-label={gettext("Edit")}
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  :if={@message.user_id == @current_scope.user.id or @can_manage_messages?}
                  type="button"
                  id={"delete-message-#{@message.id}"}
                  class="xamt-message__action xamt-message__action--danger"
                  phx-click="delete_message"
                  phx-value-id={@message.id}
                  title={gettext("Delete")}
                  aria-label={gettext("Delete")}
                  data-confirm={
                    @message.user_id == @current_scope.user.id &&
                      gettext("Delete this message?")
                  }
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </details>

            <button
              :for={{emoji, user_ids} <- reactions_for(@reactions, @message.id)}
              type="button"
              class={[
                "xamt-reaction",
                @current_scope.user.id in user_ids && "is-mine"
              ]}
              data-digits={reaction_digits(user_ids)}
              phx-click="toggle_reaction"
              phx-value-id={@message.id}
              phx-value-emoji={emoji}
            >
              <span class="xamt-reaction__emoji">{emoji}</span>
              <span class="xamt-reaction__count">{length(user_ids)}</span>
            </button>

            <div
              :if={picker_emojis(@reactions, @message.id) != []}
              class="xamt-reaction-picker"
            >
              <button
                :for={emoji <- picker_emojis(@reactions, @message.id)}
                type="button"
                class="xamt-reaction xamt-reaction--add"
                phx-click="toggle_reaction"
                phx-value-id={@message.id}
                phx-value-emoji={emoji}
                aria-label={emoji}
              >
                <span class="xamt-reaction__emoji">{emoji}</span>
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </article>
    """
  end
end
