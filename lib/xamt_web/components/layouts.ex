defmodule XamtWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use XamtWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Remote candidate backend for mgl-web-ime, or `""` when the IME should stay
  on its bundled local dictionary.
  """
  def ime_base_url do
    case Application.get_env(:xamt, :ime_base_url) do
      url when is_binary(url) -> normalize_ime_base_url(url)
      _ -> ""
    end
  end

  defp normalize_ime_base_url(url) do
    trimmed = url |> String.trim() |> String.trim_trailing("/")

    cond do
      trimmed in ["", "local"] -> ""
      String.starts_with?(trimmed, ["http://", "https://"]) -> trimmed
      true -> "http://" <> trimmed
    end
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main class="xamt-page-inner">
      <div class="xamt-auth-shell">
        <div class="xamt-auth-shell__inner">
          {render_slot(@inner_block)}
        </div>
      </div>
    </main>

    <.flash_group flash={@flash} current_scope={@current_scope} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <%!-- Client-side offline/sync toasts (MessageComposer → xamt:toast) --%>
      <div
        id="toast-container"
        phx-update="ignore"
        phx-hook="ToastHandler"
        class="xamt-toast"
        aria-live="polite"
      >
      </div>
    </div>

    <.web_push_manager current_scope={@current_scope} />
    """
  end

  @doc """
  Invisible LiveView hook that asks for notification permission and saves
  the Web Push subscription after login.
  """
  attr :current_scope, :map, default: nil

  def web_push_manager(assigns) do
    ~H"""
    <div
      :if={web_push_enabled?(@current_scope)}
      id="web-push-manager"
      phx-hook="WebPush"
      phx-update="ignore"
      data-vapid-public-key={vapid_public_key()}
      class="hidden"
    >
    </div>
    """
  end

  def vapid_public_key do
    case Application.get_env(:web_push_ex, :vapid) do
      details when is_list(details) -> details[:public_key]
      _ -> nil
    end
  end

  defp web_push_enabled?(%{user: %{id: _id}}) do
    key = vapid_public_key()
    is_binary(key) and key != ""
  end

  defp web_push_enabled?(_), do: false

  defp site_admin?(%{user: user}) when not is_nil(user), do: Xamt.Accounts.User.admin?(user)
  defp site_admin?(_), do: false

  @doc """
  Provides dark vs light theme toggle based on the `.dark` class variant.

  Theme changes are handled in `assets/js/app.js` via the `phx:set-theme` event.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="xamt-theme-toggle">
      <div class="xamt-theme-toggle__indicator" />

      <button type="button" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system">
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button type="button" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="light">
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button type="button" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="dark">
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
