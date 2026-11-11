defmodule XamtWeb.SettingsLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.SiteSettings

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    changeset = Accounts.change_user_profile(user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:form, to_form(changeset, as: :user))
     |> assign(:profile_form, to_form(changeset, as: :user))
     |> assign(:status_form, to_form(Accounts.change_user_custom_status(user), as: :status))
     |> assign(:site_admin?, User.admin?(user))
     |> assign(:registration_enabled?, SiteSettings.registration_enabled?())
     |> assign(:magic_link_enabled?, SiteSettings.magic_link_enabled?())
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       max_file_size: 2_000_000,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    form = to_form(changeset, as: :user)

    {:noreply, socket |> assign(:form, form) |> assign(:profile_form, form)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("validate_profile", params, socket),
    do: handle_event("validate", params, socket)

  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_avatar", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save_profile(socket, params)
  end

  def handle_event("save_profile", %{"user" => params}, socket) do
    save_profile(socket, params)
  end

  def handle_event("save_avatar", _params, socket) do
    save_profile(socket, %{})
  end

  def handle_event("set_status", %{"emoji" => emoji, "text" => text}, socket) do
    apply_settings_status(socket, %{status_emoji: emoji, status_text: text})
  end

  def handle_event("clear_status", _params, socket) do
    apply_settings_status(socket, %{status_emoji: nil, status_text: nil})
  end

  def handle_event("save_status", %{"status" => params}, socket) do
    apply_settings_status(socket, %{
      status_emoji: Map.get(params, "status_emoji") || Map.get(params, "emoji"),
      status_text: Map.get(params, "status_text") || Map.get(params, "text")
    })
  end

  def handle_event("save_custom_status", %{"status" => params}, socket) do
    apply_settings_status(socket, %{
      status_emoji: Map.get(params, "status_emoji") || Map.get(params, "emoji"),
      status_text: Map.get(params, "status_text") || Map.get(params, "text")
    })
  end

  def handle_event("save_custom_status", params, socket) when is_map(params) do
    apply_settings_status(socket, %{
      status_emoji: Map.get(params, "emoji"),
      status_text: Map.get(params, "text")
    })
  end

  def handle_event("toggle_registration", _params, socket) do
    enabled = !socket.assigns.registration_enabled?

    case SiteSettings.update_registration_enabled(socket.assigns.current_scope.user, enabled) do
      {:ok, setting} ->
        flash =
          if setting.registration_enabled do
            gettext("Registration is now open.")
          else
            gettext("Registration is now closed.")
          end

        {:noreply,
         socket
         |> assign_site_toggles(setting)
         |> put_flash(:info, flash)}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to change this."))}
    end
  end

  def handle_event("toggle_magic_link", _params, socket) do
    enabled = !socket.assigns.magic_link_enabled?

    case SiteSettings.update_magic_link_enabled(socket.assigns.current_scope.user, enabled) do
      {:ok, setting} ->
        flash =
          if setting.magic_link_enabled do
            gettext("Magic link login is now open.")
          else
            gettext("Magic link login is now closed.")
          end

        {:noreply,
         socket
         |> assign_site_toggles(setting)
         |> put_flash(:info, flash)}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to change this."))}
    end
  end

  defp save_profile(socket, params) do
    params =
      params
      |> Map.take(["display_name", "bio"])
      |> then(fn kept ->
        case XamtWeb.Uploads.consume_image(socket, :avatar) do
          url when is_binary(url) -> Map.put(kept, "avatar", url)
          _ -> kept
        end
      end)

    case Accounts.update_user_profile(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        form = to_form(Accounts.change_user_profile(user), as: :user)

        {:noreply,
         socket
         |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
         |> assign(:form, form)
         |> assign(:profile_form, form)
         |> assign(:status_form, to_form(Accounts.change_user_custom_status(user), as: :status))
         |> put_flash(:info, gettext("Profile updated"))}

      {:error, changeset} ->
        if url = params["avatar"] do
          XamtWeb.Uploads.delete_stored(url)
        end

        form = to_form(changeset, as: :user)
        {:noreply, socket |> assign(:form, form) |> assign(:profile_form, form)}
    end
  end

  defp assign_site_toggles(socket, setting) do
    socket
    |> assign(:registration_enabled?, setting.registration_enabled)
    |> assign(:magic_link_enabled?, setting.magic_link_enabled)
  end

  defp apply_settings_status(socket, attrs) do
    case Accounts.update_user_custom_status(socket.assigns.current_scope.user, attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
         |> assign(:status_form, to_form(Accounts.change_user_custom_status(user), as: :status))
         |> put_flash(:info, gettext("Status updated"))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:status_form, to_form(changeset, as: :status))
         |> put_flash(:error, gettext("Could not update status"))}
    end
  end

  defp display_initial(%{display_name: name}) when is_binary(name) and name != "",
    do: String.first(name)

  defp display_initial(%{username: name}) when is_binary(name) and name != "",
    do: String.first(name)

  defp display_initial(_), do: "?"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.home
      flash={@flash}
      current_scope={@current_scope}
      show_search={@show_search}
      global_search_query={@global_search_query}
      global_search_results={@global_search_results}
    >
      <main id="profile-edit-canvas" class="xamt-home-canvas" phx-hook="MongolianScroll">
        <%!-- Zone 1: back + live card preview + avatar --%>
        <aside class="xamt-home-section" id="settings-panel">
          <div class="flex flex-row items-center justify-between h-full py-1">
            <div class="flex flex-row items-center gap-3">
              <.link navigate={~p"/"} class="xamt-icon-btn" title={gettext("Back")}>
                <.icon name="hero-arrow-left" class="w-5 h-5" />
              </.link>

              <h1 class="text-xl font-bold tracking-widest mongol-text">
                {gettext("Settings")}
              </h1>
            </div>
          </div>

          <div class="xamt-home-card items-center">
            <div class="flex flex-row items-center gap-3 h-full">
              <div class="w-14 h-14 rounded-2xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-xl overflow-hidden border border-[var(--xamt-line)] shrink-0">
                <%= if is_binary(@current_scope.user.avatar) and @current_scope.user.avatar != "" do %>
                  <img src={@current_scope.user.avatar} class="w-full h-full object-cover" />
                <% else %>
                  {display_initial(@current_scope.user)}
                <% end %>
              </div>

              <span class="font-bold text-lg mongol-text">
                {@current_scope.user.display_name || @current_scope.user.username}
              </span>

              <span class="text-xs text-[var(--xamt-muted)]">
                @{@current_scope.user.username}
              </span>
            </div>

            <form
              id="avatar-upload-form"
              phx-submit="save_avatar"
              phx-change="validate_avatar"
              class="flex flex-col gap-2 h-full"
            >
              <label class="xamt-btn py-3 px-2 text-xs font-bold cursor-pointer h-full justify-center mongol-text">
                <.icon name="hero-camera" class="w-4 h-4 mb-1.5" />
                <span>{gettext("Upload photo")}</span>
                <.live_file_input upload={@uploads.avatar} class="sr-only" />
              </label>

              <div :for={entry <- @uploads.avatar.entries} class="xamt-upload-preview__item">
                <.live_img_preview entry={entry} class="xamt-upload-preview__img" />
                <button
                  type="button"
                  id={"cancel-avatar-#{entry.ref}"}
                  phx-click="cancel_avatar"
                  phx-value-ref={entry.ref}
                  class="xamt-upload-preview__cancel"
                  aria-label={gettext("Cancel upload")}
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>

              <button
                :if={@uploads.avatar.entries != []}
                type="submit"
                class="xamt-btn xamt-btn--primary py-3 px-2 text-xs font-bold h-full mongol-text"
              >
                {gettext("Save")}
              </button>
            </form>
          </div>

          <section id="settings-theme" class="xamt-home-card">
            <h2 class="font-bold text-xs text-[var(--xamt-accent)] mongol-text">
              {gettext("Theme")}
            </h2>
            <p class="text-xs text-[var(--xamt-muted)] mongol-text">
              {gettext("Choose a Mongolian aesthetic palette.")}
            </p>
            <Layouts.theme_palette id="xamt-theme-palette-settings" />
          </section>
        </aside>

        <%!-- Zone 2: nickname + bio --%>
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-identification" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm mongol-text">{gettext("Profile")}</h2>
            </div>
          </header>

          <.form
            for={@profile_form}
            id="settings-form"
            phx-change="validate_profile"
            phx-submit="save_profile"
            class="xamt-home-card"
          >
            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Display name")}</span>
              <input
                id="profile-display-name"
                type="text"
                name={@profile_form[:display_name].name}
                value={@profile_form[:display_name].value}
                placeholder={gettext("Display name")}
                class="xamt-bot-input mongol-input"
                phx-hook="MongolianIME"
                autocomplete="nickname"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Bio")}</span>
              <textarea
                id="profile-bio"
                name={@profile_form[:bio].name}
                placeholder={gettext("Bio")}
                class="xamt-bot-input mongol-input !w-20"
                phx-hook="MongolianIME"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              >{Phoenix.HTML.Form.normalize_value("textarea", @profile_form[:bio].value)}</textarea>
            </label>

            <button
              type="submit"
              id="settings-save"
              phx-disable-with={gettext("Save")}
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
            >
              <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Save")}</span>
            </button>
          </.form>
        </section>

        <%!-- Zone 3: custom status --%>
        <section id="settings-status" class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-face-smile" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm mongol-text">{gettext("Custom status")}</h2>
            </div>
          </header>

          <div class="flex flex-col gap-3 h-full">
            <div class="xamt-home-card">
              <div class="flex flex-col gap-2 h-full">
                <button
                  :for={{preset, idx} <- Enum.with_index(Accounts.custom_status_presets())}
                  type="button"
                  id={"settings-status-preset-#{idx}"}
                  class="xamt-btn py-3 px-2 text-xs font-bold h-full mongol-text"
                  phx-click="set_status"
                  phx-value-emoji={preset["emoji"]}
                  phx-value-text={preset["text"]}
                >
                  <span class="xamt-upright mb-1" aria-hidden="true">{preset["emoji"]}</span>
                  <span>{preset["text"]}</span>
                </button>
              </div>
            </div>

            <.form
              for={@status_form}
              id="settings-status-form"
              phx-submit="save_custom_status"
              class="xamt-home-card"
            >
              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Custom status")}</span>
                <input
                  id="settings-status-emoji"
                  type="text"
                  name="emoji"
                  value={@current_scope.user.status_emoji}
                  placeholder="😀"
                  maxlength="10"
                  class="xamt-bot-input text-center"
                  phx-hook="StatusEmoji"
                  autocomplete="off"
                  readonly
                  inputmode="none"
                  aria-haspopup="dialog"
                  aria-label={gettext("Choose emoji")}
                  title={gettext("Choose emoji")}
                />
              </label>

              <label class="xamt-bot-field">
                <span class="xamt-label">{gettext("Custom status")}</span>
                <input
                  id="settings-status-text"
                  type="text"
                  name="text"
                  value={@current_scope.user.status_text}
                  placeholder={gettext("Say something...")}
                  maxlength="50"
                  class="xamt-bot-input mongol-input"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                  onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
                />
              </label>

              <button
                type="submit"
                id="settings-status-save"
                class="xamt-btn xamt-btn--primary h-full px-3 text-xs font-bold mongol-text"
              >
                <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
                <span>{gettext("Save")}</span>
              </button>

              <button
                type="button"
                id="settings-status-clear"
                phx-click="clear_status"
                class="xamt-btn h-full px-2.5 text-xs text-[var(--xamt-muted)] mongol-text"
              >
                {gettext("Clear status")}
              </button>
            </.form>
          </div>
        </section>

        <%!-- Zone 4: site admin + account links --%>
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm mongol-text">{gettext("Account")}</h2>
            </div>
          </header>

          <div class="flex flex-col gap-3 h-full">
            <section :if={@site_admin?} id="site-settings" class="xamt-home-card">
              <h2 class="font-bold text-xs text-[var(--xamt-accent)] mongol-text">
                {gettext("Site")}
              </h2>
              <p class="text-xs text-[var(--xamt-muted)] mongol-text">
                {gettext("Control how people join and sign in.")}
              </p>

              <div class="flex flex-row items-center justify-between gap-3">
                <button
                  type="button"
                  id="registration-toggle"
                  class="xamt-switch"
                  role="switch"
                  aria-checked={to_string(@registration_enabled?)}
                  phx-click="toggle_registration"
                >
                  <span class="xamt-switch__track" aria-hidden="true">
                    <span class="xamt-switch__thumb"></span>
                  </span>
                </button>
                <div class="flex flex-row items-center gap-1">
                  <span class="text-xs font-bold mongol-text">{gettext("Allow registration")}</span>
                  <span class="text-xs text-[var(--xamt-muted)] mongol-text">
                    {if @registration_enabled?, do: gettext("Open"), else: gettext("Closed")}
                  </span>
                </div>
              </div>

              <div class="flex flex-row items-center justify-between gap-3">
                <button
                  type="button"
                  id="magic-link-toggle"
                  class="xamt-switch"
                  role="switch"
                  aria-checked={to_string(@magic_link_enabled?)}
                  phx-click="toggle_magic_link"
                >
                  <span class="xamt-switch__track" aria-hidden="true">
                    <span class="xamt-switch__thumb"></span>
                  </span>
                </button>
                <div class="flex flex-row items-center gap-1">
                  <span class="text-xs font-bold mongol-text">
                    {gettext("Allow magic link login")}
                  </span>
                  <span class="text-xs text-[var(--xamt-muted)] mongol-text">
                    {if @magic_link_enabled?, do: gettext("Open"), else: gettext("Closed")}
                  </span>
                </div>
              </div>

              <.link
                navigate={~p"/admin/users"}
                id="manage-users-link"
                class="xamt-btn xamt-btn--soft py-3 px-2 text-xs font-bold mongol-text"
              >
                {gettext("Users")}
              </.link>
            </section>

            <nav class="xamt-home-card">
              <.link
                href={~p"/users/settings"}
                class="xamt-btn py-3 px-2 text-xs font-bold mongol-text"
              >
                {gettext("Account / password")}
              </.link>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="xamt-btn py-3 px-2 text-xs font-bold mongol-text"
              >
                {gettext("Log out")}
              </.link>
            </nav>
          </div>
        </section>
      </main>
    </Layouts.home>
    """
  end
end
