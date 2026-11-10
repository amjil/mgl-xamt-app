defmodule XamtWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use XamtWeb, :html

  import XamtWeb.SearchPalette

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Remote candidate backend for mgl-web-ime.

  `""` is same-origin (`baseUrl: ""`, so `/api/next_word/` stays on the page
  host). `"local"` keeps the bundled dictionary.
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
      trimmed == "" -> ""
      trimmed == "local" -> "local"
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

  attr :show_search, :boolean, default: nil
  attr :global_search_query, :string, default: ""
  attr :global_search_results, :list, default: []

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

    <.global_search_palette {assigns} />
    <.flash_group flash={@flash} current_scope={@current_scope} />
    """
  end

  @doc """
  Home and settings pages: page chrome without the auth shell.
  Flash stays here so templates never call `<.flash_group>`.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :show_search, :boolean, default: nil
  attr :global_search_query, :string, default: ""
  attr :global_search_results, :list, default: []
  slot :inner_block, required: true

  def home(assigns) do
    ~H"""
    <div class="xamt-page-inner">
      <.flash_group flash={@flash} current_scope={@current_scope} />
      {render_slot(@inner_block)}
    </div>
    <.global_search_palette {assigns} />
    """
  end

  @doc """
  Chat shell without auth chrome. Flash is rendered here, not in the LiveView.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :show_search, :boolean, default: nil
  attr :global_search_query, :string, default: ""
  attr :global_search_results, :list, default: []
  slot :inner_block, required: true

  def chat(assigns) do
    ~H"""
    <.flash_group flash={@flash} current_scope={@current_scope} />
    {render_slot(@inner_block)}
    <.global_search_palette {assigns} />
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
        class="xamt-toast mn-overlay"
        aria-live="polite"
      >
      </div>
    </div>

    <.web_push_manager current_scope={@current_scope} />
    """
  end

  defp global_search_palette(assigns) do
    ~H"""
    <.search_palette
      :if={search_palette?(assigns)}
      show={@show_search}
      search_query={@global_search_query}
      search_results={@global_search_results}
      current_scope={@current_scope}
    />
    """
  end

  defp search_palette?(assigns) do
    user? = match?(%{user: %{id: _}}, assigns[:current_scope] || assigns.current_scope)
    user? and is_boolean(assigns.show_search)
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

  @doc """
  Four Mongolian aesthetic palette swatches.

  Theme changes are client-only via the `xamt:set_theme` CustomEvent
  (see `root.html.heex` FOUC script and `assets/js/app.js`).
  """
  attr :id, :string, default: nil

  def theme_palette(assigns) do
    ~H"""
    <div
      id={@id}
      class="xamt-theme-palette"
      style="writing-mode: horizontal-tb;"
      role="group"
      aria-label={gettext("Theme")}
    >
      <button
        type="button"
        data-xamt-theme="steppe-light"
        onclick="window.dispatchEvent(new CustomEvent('xamt:set_theme', {detail: {theme: 'steppe-light'}}))"
        class="xamt-theme-swatch xamt-theme-swatch--steppe"
        title={gettext("Steppe parchment (light)")}
        aria-label={gettext("Steppe parchment (light)")}
      />
      <button
        type="button"
        data-xamt-theme="night-sky"
        onclick="window.dispatchEvent(new CustomEvent('xamt:set_theme', {detail: {theme: 'night-sky'}}))"
        class="xamt-theme-swatch xamt-theme-swatch--night"
        title={gettext("Night sky (dark)")}
        aria-label={gettext("Night sky (dark)")}
      />
      <button
        type="button"
        data-xamt-theme="crimson-felt"
        onclick="window.dispatchEvent(new CustomEvent('xamt:set_theme', {detail: {theme: 'crimson-felt'}}))"
        class="xamt-theme-swatch xamt-theme-swatch--crimson"
        title={gettext("Crimson felt (warm dark)")}
        aria-label={gettext("Crimson felt (warm dark)")}
      />
      <button
        type="button"
        data-xamt-theme="jade-meadow"
        onclick="window.dispatchEvent(new CustomEvent('xamt:set_theme', {detail: {theme: 'jade-meadow'}}))"
        class="xamt-theme-swatch xamt-theme-swatch--jade"
        title={gettext("Jade meadow (fresh green)")}
        aria-label={gettext("Jade meadow (fresh green)")}
      />
    </div>
    """
  end

  @doc """
  Legacy light/dark/system toggle. Prefer `theme_palette/1`.
  """
  def theme_toggle(assigns) do
    ~H"""
    <.theme_palette />
    """
  end
end
