defmodule XamtWeb.ServerLive.Composer do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Helpers
  alias Xamt.Messages

  def composer(assigns) do
    ~H"""
    <div id="channel-typing" class="xamt-typing mongol-text">
      {typing_label(@typing_users)}
    </div>

    <div
      id="message-composer-wrap"
      class={[
        "xamt-composer-wrap",
        @composer_mode == :poll && "xamt-composer-wrap--poll"
      ]}
      phx-drop-target={@uploads.media.ref}
      data-has-uploads={to_string(@uploads.media.entries != [])}
      data-composer-mode={@composer_mode}
      data-submit-event={if @editing_message_id, do: "update_message", else: "send_message"}
      data-editing-id={@editing_message_id}
      data-channel-id={@active_channel && @active_channel.id}
      data-reply-to-id={@replying_to && @replying_to.id}
    >
      <button
        type="button"
        id="composer-peek"
        class="xamt-composer__peek"
        aria-label={gettext("Write a message")}
      >
        <.icon name="hero-pencil" class="size-5" />
      </button>
      <div :if={@replying_to} id="reply-preview" class="xamt-reply-bar">
        <span class="xamt-quote__mark" aria-hidden="true">↳</span>
        <span class="xamt-quote__author mongol-text">
          {display_name(@replying_to.user)}
        </span>
        <span class="xamt-quote__text mongol-text">{Messages.excerpt(@replying_to, 40)}</span>
        <button
          type="button"
          id="cancel-reply"
          class="xamt-icon-btn"
          phx-click="cancel_reply"
          aria-label={gettext("Cancel reply")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <section
        :if={@uploads.media.entries != []}
        id="media-upload-preview"
        class="xamt-upload-preview"
      >
        <div :for={entry <- @uploads.media.entries} class="xamt-upload-preview__item">
          <.live_img_preview entry={entry} class="xamt-upload-preview__img" />
          <div
            :if={entry.progress < 100}
            class="xamt-upload-preview__progress"
            style={"width: #{entry.progress}%"}
          >
          </div>
          <button
            type="button"
            id={"cancel-upload-#{entry.ref}"}
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            class="xamt-upload-preview__cancel"
            aria-label={gettext("Cancel upload")}
          >
            <.icon name="hero-x-mark" class="size-3" />
          </button>
        </div>
      </section>

      <%!-- live_file_input must stay outside phx-update="ignore" so LiveView can patch upload state --%>
      <form id="media-upload-form" phx-change="validate_upload" class="hidden">
        <.live_file_input upload={@uploads.media} />
      </form>

      <%= if not @can_send_messages? do %>
        <p id="composer-muted" class="xamt-composer-muted mongol-text">
          {gettext("You cannot send messages in this channel.")}
        </p>
      <% else %>
        <%= if @composer_mode == :poll do %>
          <.form
            for={@poll_form}
            id="poll-composer-form"
            class="xamt-form xamt-form--vertical xamt-poll-composer"
            phx-change="validate_poll"
            phx-submit="send_poll"
          >
            <div class="xamt-poll-composer__head">
              <.icon name="hero-chart-bar" class="size-5 xamt-poll-composer__icon" />
              <span class="xamt-poll-composer__title mongol-text">{gettext("Create a poll")}</span>
            </div>

            <.input
              field={@poll_form[:question]}
              id="poll-question"
              type="text"
              label={gettext("Question")}
              required
              maxlength="280"
              placeholder={gettext("Ask a question…")}
              phx-hook="MongolianIME"
              class="xamt-input mongol-input"
              autocomplete="off"
            />

            <div class="xamt-poll-composer__options">
              <p class="xamt-poll-composer__label mongol-text">{gettext("Options")}</p>
              <div
                :for={{opt, i} <- Enum.with_index(List.wrap(@poll_form[:options].value))}
                class="xamt-poll-composer__option-row"
              >
                <.input
                  id={"poll-option-#{i}"}
                  name="poll[options][]"
                  type="text"
                  value={opt}
                  required={i < 2}
                  maxlength="120"
                  placeholder={gettext("Option %{n}", n: i + 1)}
                  phx-hook="MongolianIME"
                  class="xamt-input mongol-input"
                  autocomplete="off"
                />
                <button
                  :if={i >= 2}
                  type="button"
                  id={"remove-poll-option-#{i}"}
                  class="xamt-icon-btn"
                  phx-click="remove_poll_option"
                  phx-value-index={i}
                  aria-label={gettext("Remove option")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
              <button
                :if={length(List.wrap(@poll_form[:options].value)) < 10}
                type="button"
                id="add-poll-option"
                class="xamt-btn xamt-btn--soft xamt-poll-composer__add mongol-text"
                phx-click="add_poll_option"
              >
                <.icon name="hero-plus" class="size-4" />
                {gettext("Add option")}
              </button>
            </div>

            <.input
              field={@poll_form[:allow_multiple]}
              id="poll-allow-multiple"
              type="checkbox"
              label={gettext("Allow multiple answers")}
            />

            <.input
              field={@poll_form[:results_open]}
              id="poll-results-open"
              type="checkbox"
              label={gettext("Open results (anyone can see who voted)")}
            />

            <div class="xamt-poll-composer__actions">
              <button
                type="button"
                id="cancel-poll-composer"
                class="xamt-btn xamt-btn--soft mongol-text"
                phx-click="cancel_poll_composer"
              >
                {gettext("Cancel")}
              </button>
              <button type="submit" id="send-poll" class="xamt-btn xamt-btn--primary mongol-text">
                <.icon name="hero-paper-airplane" class="size-4" />
                {gettext("Send poll")}
              </button>
            </div>
          </.form>
        <% else %>
          <div class="xamt-composer__field">
            <div id="message-composer" phx-hook="MessageComposer" phx-update="ignore">
              <div class="xamt-composer__editor" id="composer-editor-host"></div>
            </div>

            <div id="composer-toolbar" class="xamt-composer__toolbar">
              <button
                type="button"
                id="composer-poll"
                class="xamt-btn xamt-btn--soft"
                phx-click="open_poll_composer"
                title={gettext("Create a poll")}
                aria-label={gettext("Create a poll")}
                disabled={not is_nil(@editing_message_id)}
              >
                <.icon name="hero-chart-bar" class="size-4" />
              </button>
              <label
                for={@uploads.media.ref}
                class="xamt-btn xamt-btn--soft"
                title={gettext("Upload Media")}
                aria-label={gettext("Upload Media")}
              >
                <.icon name="hero-photo" class="size-4" />
              </label>
              <button
                type="button"
                id="composer-emoji"
                class="xamt-btn xamt-btn--soft xamt-composer__emoji"
                title={gettext("Insert emoji")}
                aria-label={gettext("Insert emoji")}
                aria-haspopup="dialog"
              >
                <span class="xamt-composer__emoji-glyph" aria-hidden="true">😊</span>
              </button>
              <form
                id="audio-form"
                phx-change="validate_audio"
                phx-submit="send_audio"
                phx-hook="AudioRecorder"
                data-max-seconds="60"
                data-mic-error={gettext("Microphone access is required to record")}
                data-mic-unsupported={gettext("Voice recording is not supported in this browser")}
                data-mic-insecure={
                  gettext(
                    "Voice recording needs HTTPS. Open https://dev1:4001 on this phone and allow the microphone."
                  )
                }
                data-mic-empty={gettext("Recording was empty")}
                data-mic-upload-error={gettext("Could not upload voice message")}
                data-record-label={gettext("Record voice message")}
                data-stop-label={gettext("Stop recording")}
              >
                <.live_file_input upload={@uploads.audio} class="hidden" />
                <div id="voice-chrome" phx-update="ignore">
                  <button
                    type="button"
                    id="btn-record"
                    class="xamt-btn xamt-btn--soft xamt-record-btn"
                    title={gettext("Record voice message")}
                    aria-label={gettext("Record voice message")}
                    aria-pressed="false"
                  >
                    <.icon name="hero-microphone" class="size-4 xamt-record-btn__mic" />
                    <.icon name="hero-stop" class="size-4 xamt-record-btn__stop" />
                  </button>
                  <div id="voice-panel" class="xamt-voice__panel" data-state="idle">
                    <div id="voice-countdown" class="xamt-voice__countdown">
                      <span class="xamt-voice__dot" aria-hidden="true"></span>
                      <span
                        id="voice-countdown-value"
                        class="xamt-voice__time"
                        aria-live="polite"
                      >
                        1:00
                      </span>
                    </div>
                    <div id="voice-review" class="xamt-voice__review">
                      <audio
                        id="voice-preview"
                        class="xamt-voice__preview"
                        controls
                        preload="metadata"
                      >
                        {gettext("Preview recording")}
                      </audio>
                      <div class="xamt-voice__actions">
                        <button
                          type="button"
                          id="btn-voice-discard"
                          class="xamt-btn xamt-btn--soft"
                          title={gettext("Discard")}
                          aria-label={gettext("Discard")}
                        >
                          <.icon name="hero-x-mark" class="size-4" />
                          <span>{gettext("Discard")}</span>
                        </button>
                        <button
                          type="button"
                          id="btn-voice-send"
                          class="xamt-btn xamt-btn--primary"
                          title={gettext("Send")}
                          aria-label={gettext("Send")}
                        >
                          <.icon name="hero-paper-airplane" class="size-4" />
                          <span>{gettext("Send")}</span>
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </form>
              <button
                :if={@editing_message_id}
                type="button"
                id="composer-cancel-edit"
                class="xamt-btn xamt-btn--soft"
                phx-click="cancel_edit"
                title={gettext("Cancel")}
                aria-label={gettext("Cancel")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
              <button
                type="button"
                id="composer-send"
                class="xamt-btn xamt-btn--primary"
                data-composer-send
                title={if @editing_message_id, do: gettext("Save"), else: gettext("Send")}
                aria-label={if @editing_message_id, do: gettext("Save"), else: gettext("Send")}
              >
                <.icon
                  name={if @editing_message_id, do: "hero-check", else: "hero-paper-airplane"}
                  class="size-4"
                />
              </button>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
