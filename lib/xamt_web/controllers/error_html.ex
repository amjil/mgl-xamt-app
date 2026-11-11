defmodule XamtWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use XamtWeb, :html

  def render("404.html", assigns) do
    assigns =
      assigns
      |> Map.put(:code, "404")
      |> Map.put(:status_text, "Not Found")
      |> Map.put(:title, gettext("Page not found"))
      |> Map.put(
        :lead,
        gettext("The scroll or channel you are looking for does not exist or has been moved.")
      )

    error_canvas(assigns)
  end

  def render("500.html", assigns) do
    assigns =
      assigns
      |> Map.put(:code, "500")
      |> Map.put(:status_text, "Internal Server Error")
      |> Map.put(:title, gettext("Something went wrong!"))
      |> Map.put(
        :lead,
        gettext(
          "An unexpected error occurred on the server. Please return to the hall and try again."
        )
      )

    error_canvas(assigns)
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  defp error_canvas(assigns) do
    ~H"""
    <main id={"error-#{@code}-canvas"} class="xamt-home-canvas" phx-hook="MongolianScroll">
      <section class="xamt-home-section">
        <header class="xamt-home-section__header">
          <div class="flex flex-row items-center gap-2">
            <.icon
              name="hero-exclamation-triangle"
              class="w-5 h-5 text-[var(--xamt-accent-2)] shrink-0"
            />
            <span class="font-bold text-sm font-mono text-[var(--xamt-accent-2)]">
              {@code}
            </span>
          </div>
          <span class="text-xs text-[var(--xamt-muted)] mongol-text">
            {@status_text}
          </span>
        </header>

        <div class="xamt-home-card items-center justify-between">
          <div class="flex flex-row items-center gap-3 h-full">
            <span class="xamt-ornament !h-12" aria-hidden="true"></span>
            <h1 class="text-xl font-bold tracking-widest text-[var(--xamt-text)] mongol-text">
              {@title}
            </h1>
          </div>

          <p class="text-sm text-[var(--xamt-muted)] mongol-text leading-relaxed h-full px-1">
            {@lead}
          </p>

          <.link
            navigate={~p"/"}
            class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
          >
            <.icon name="hero-home" class="w-4 h-4 mb-1.5" />
            <span>{gettext("Back to community hall")}</span>
          </.link>
        </div>
      </section>
    </main>
    """
  end
end
