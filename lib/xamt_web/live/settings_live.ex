defmodule XamtWeb.SettingsLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    changeset = Accounts.change_user_profile(user)

    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:form, to_form(changeset, as: :user))
     |> assign(:status_form, to_form(Accounts.change_user_custom_status(user), as: :status))
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

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_avatar", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    params =
      case XamtWeb.Uploads.consume_image(socket, :avatar) do
        url when is_binary(url) -> Map.put(params, "avatar", url)
        _ -> params
      end

    case Accounts.update_user_profile(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
         |> assign(:form, to_form(Accounts.change_user_profile(user), as: :user))
         |> assign(:status_form, to_form(Accounts.change_user_custom_status(user), as: :status))
         |> put_flash(:info, gettext("Profile updated"))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  def handle_event("set_status", %{"emoji" => emoji, "text" => text}, socket) do
    apply_settings_status(socket, %{status_emoji: emoji, status_text: text})
  end

  def handle_event("clear_status", _params, socket) do
    apply_settings_status(socket, %{status_emoji: nil, status_text: nil})
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="xamt-page-inner">
      <Layouts.flash_group flash={@flash} current_scope={@current_scope} />

      <section class="xamt-stack" id="settings-panel">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Profile")}</p>
        </div>
        <.header>
          <span class="mongol-text">{gettext("Settings")}</span>
          <:subtitle>
            {gettext("Update how you appear in the community.")}
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="settings-form"
          phx-change="validate"
          phx-submit="save"
          class="xamt-form xamt-form--vertical"
        >
          <div class="xamt-field">
            <span class="xamt-field__label mongol-text">{gettext("Avatar")}</span>
            <.status_avatar user={@current_scope.user} class="xamt-avatar xamt-avatar--lg" />
            <label for={@uploads.avatar.ref} class="xamt-btn xamt-btn--soft mongol-text">
              {gettext("Upload photo")}
            </label>
            <.live_file_input upload={@uploads.avatar} class="hidden" />
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
          </div>

          <label class="xamt-field">
            <span class="xamt-field__label mongol-text">{gettext("Display name")}</span>
            <input
              type="text"
              name={@form[:display_name].name}
              id={@form[:display_name].id}
              value={@form[:display_name].value}
              class="xamt-input mongol-input"
              phx-hook="MongolianIME"
              autocomplete="nickname"
            />
          </label>

          <label class="xamt-field">
            <span class="xamt-field__label mongol-text">{gettext("Bio")}</span>
            <textarea
              name={@form[:bio].name}
              id={@form[:bio].id}
              rows="4"
              class="xamt-textarea mongol-input"
              phx-hook="MongolianIME"
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:bio].value)}</textarea>
          </label>

          <button type="submit" id="settings-save" class="xamt-btn xamt-btn--primary mongol-text">
            {gettext("Save")}
          </button>
        </.form>

        <section id="settings-status" class="xamt-status-picker xamt-surface">
          <h2 class="xamt-section-title mongol-text">{gettext("Custom status")}</h2>

          <div class="xamt-status-picker__presets" role="list">
            <button
              :for={{preset, idx} <- Enum.with_index(Accounts.custom_status_presets())}
              type="button"
              id={"settings-status-preset-#{idx}"}
              class="xamt-status-btn"
              phx-click="set_status"
              phx-value-emoji={preset["emoji"]}
              phx-value-text={preset["text"]}
            >
              <span class="xamt-status-btn__emoji xamt-upright" aria-hidden="true">
                {preset["emoji"]}
              </span>
              <span class="xamt-status-btn__text mongol-text">{preset["text"]}</span>
            </button>

            <button
              type="button"
              id="settings-status-clear"
              class="xamt-status-btn xamt-status-btn--clear mongol-text"
              phx-click="clear_status"
            >
              {gettext("Clear status")}
            </button>
          </div>

          <form
            id="settings-status-form"
            phx-submit="save_custom_status"
            class="xamt-form xamt-form--vertical xamt-status-picker__form"
          >
            <input
              type="text"
              name="emoji"
              id="settings-status-emoji"
              value={@current_scope.user.status_emoji}
              placeholder="😀"
              maxlength="10"
              class="xamt-input xamt-status-picker__emoji"
              autocomplete="off"
            />
            <input
              type="text"
              name="text"
              id="settings-status-text"
              value={@current_scope.user.status_text}
              placeholder={gettext("Say something...")}
              maxlength="50"
              class="xamt-input mongol-input xamt-status-picker__text"
              phx-hook="MongolianIME"
              autocomplete="off"
            />
            <button
              type="submit"
              id="settings-status-save"
              class="xamt-btn xamt-btn--primary mongol-text"
            >
              {gettext("Save")}
            </button>
          </form>
        </section>

        <nav class="xamt-settings__links">
          <.link href={~p"/users/settings"} class="xamt-btn mongol-text">
            {gettext("Account / password")}
          </.link>
          <.link href={~p"/users/log-out"} method="delete" class="xamt-btn mongol-text">
            {gettext("Log out")}
          </.link>
        </nav>
      </section>
    </div>
    """
  end
end
