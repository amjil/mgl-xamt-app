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
      class="xamt-composer-wrap"
      phx-drop-target={@uploads.media.ref}
      data-has-uploads={to_string(@uploads.media.entries != [])}
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

      <div class="xamt-composer__field">
        <div id="message-composer" phx-hook="MessageComposer" phx-update="ignore">
          <div class="xamt-composer__editor" id="composer-editor-host"></div>
        </div>

        <div id="composer-toolbar" class="xamt-composer__toolbar">
          <label
            for={@uploads.media.ref}
            class="xamt-btn xamt-btn--soft"
            title={gettext("Upload Media")}
            aria-label={gettext("Upload Media")}
          >
            <.icon name="hero-photo" class="size-4" />
          </label>
          <form
            id="audio-form"
            phx-change="validate_audio"
            phx-submit="send_audio"
            phx-hook="AudioRecorder"
            data-mic-error={gettext("Microphone access is required to record")}
            data-mic-unsupported={gettext("Voice recording is not supported in this browser")}
            data-mic-insecure={
              gettext(
                "Voice recording needs HTTPS. Open https://dev1:4001 on this phone and allow the microphone."
              )
            }
            data-mic-empty={gettext("Recording was empty")}
            data-mic-upload-error={gettext("Could not upload voice message")}
          >
            <.live_file_input upload={@uploads.audio} class="hidden" />
            <button
              type="button"
              id="btn-record"
              class="xamt-btn xamt-btn--soft xamt-record-btn"
              title={gettext("Record voice message")}
              aria-label={gettext("Record voice message")}
              aria-pressed="false"
            >
              <.icon name="hero-microphone" class="size-4" />
            </button>
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
    </div>
    """
  end
end
