defmodule XamtWeb.ServerLive.Lightbox do
  @moduledoc false

  use XamtWeb, :html

  def lightbox(assigns) do
    ~H"""
    <%= if @lightbox_images do %>
      <% current_image = Enum.at(@lightbox_images, @lightbox_index) %>
      <div
        id="media-lightbox"
        class="xamt-lightbox"
        phx-window-keydown="lightbox_keydown"
        phx-hook="LightboxSwipe"
        role="dialog"
        aria-modal="true"
        aria-label={gettext("Image gallery")}
      >
        <button
          id="lightbox-close"
          type="button"
          phx-click="close_lightbox"
          class="xamt-lightbox__close"
          aria-label={gettext("Close")}
        >
          <.icon name="hero-x-mark" class="w-10 h-10" />
        </button>

        <img
          id="lightbox-image"
          src={current_image["original"]}
          alt={gettext("Full size image")}
          class="xamt-lightbox__image"
        />

        <button
          :if={@lightbox_index > 0}
          id="lightbox-prev"
          type="button"
          phx-click="lightbox_prev"
          class="xamt-lightbox__nav xamt-lightbox__nav--prev"
          aria-label={gettext("Previous image")}
        >
          <.icon name="hero-chevron-left" class="w-12 h-12" />
        </button>

        <button
          :if={@lightbox_index < length(@lightbox_images) - 1}
          id="lightbox-next"
          type="button"
          phx-click="lightbox_next"
          class="xamt-lightbox__nav xamt-lightbox__nav--next"
          aria-label={gettext("Next image")}
        >
          <.icon name="hero-chevron-right" class="w-12 h-12" />
        </button>

        <div id="lightbox-counter" class="xamt-lightbox__counter">
          {@lightbox_index + 1} / {length(@lightbox_images)}
        </div>
      </div>
    <% end %>
    """
  end
end
