defmodule XamtWeb.SettingsLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.Accounts.User
  alias Xamt.SiteSettings
  alias XamtWeb.Uploads

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Email changed successfully."))

        {:error, _} ->
          put_flash(socket, :error, gettext("Email change link is invalid or it has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:current_email, user.email)
     |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
     |> assign(
       :email_form,
       to_form(Accounts.change_user_email(user, %{}, validate_unique: false), as: "email")
     )
     |> assign(
       :password_form,
       to_form(Accounts.change_user_password(user, %{}, hash_password: false), as: "user")
     )
     |> assign(:trigger_submit, false)
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
  def handle_event("validate_avatar", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_avatar", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("save_avatar", _params, socket) do
    user = socket.assigns.current_scope.user

    case Uploads.consume_image(socket, :avatar) do
      avatar_url when is_binary(avatar_url) ->
        case Accounts.update_user_profile(user, %{avatar: avatar_url}) do
          {:ok, updated_user} ->
            Uploads.delete_stored(user.avatar)
            scope = %{socket.assigns.current_scope | user: updated_user}

            {:noreply,
             socket
             |> assign(:current_scope, scope)
             |> put_flash(:info, gettext("Avatar updated."))}

          {:error, _changeset} ->
            Uploads.delete_stored(avatar_url)
            {:noreply, put_flash(socket, :error, gettext("Could not update avatar."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_avatar", _params, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_user_profile(user, %{avatar: nil}) do
      {:ok, updated_user} ->
        Uploads.delete_stored(user.avatar)
        scope = %{socket.assigns.current_scope | user: updated_user}

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> put_flash(:info, gettext("Avatar removed."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove avatar."))}
    end
  end

  def handle_event("validate_profile", params, socket) do
    user_params = Map.get(params, "user", %{})

    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :profile_form, to_form(changeset))}
  end

  def handle_event("save_profile", params, socket) do
    user = socket.assigns.current_scope.user
    user_params = Map.get(params, "user", %{})

    status_attrs = %{
      status_emoji: Map.get(params, "status_emoji"),
      status_text: Map.get(params, "status_text")
    }

    with {:ok, updated_user} <- Accounts.update_user_profile(user, user_params),
         {:ok, updated_user} <- Accounts.update_user_custom_status(updated_user, status_attrs) do
      scope = %{socket.assigns.current_scope | user: updated_user}

      {:noreply,
       socket
       |> assign(:current_scope, scope)
       |> assign(:profile_form, to_form(Accounts.change_user_profile(updated_user)))
       |> put_flash(:info, gettext("Profile updated successfully."))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("validate_email", %{"email" => email_params}, socket) do
    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(email_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form(as: "email")

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"email" => email_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.change_user_email(user, email_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/settings/confirm-email/#{&1}")
        )

        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("A link to confirm your email change has been sent to the new address.")
         )}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert, as: "email"))}
    end
  end

  def handle_event("validate_password", %{"user" => password_params}, socket) do
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(password_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => password_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.change_user_password(user, password_params) do
      %{valid?: true} = changeset ->
        {:noreply,
         socket
         |> assign(:trigger_submit, true)
         |> assign(:password_form, to_form(changeset, as: "user"))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert, as: "user"))}
    end
  end

  def handle_event("revoke_all_sessions", _params, socket) do
    user = socket.assigns.current_scope.user
    Accounts.revoke_all_user_sessions(user)

    {:noreply,
     socket
     |> put_flash(:info, gettext("All sessions have been logged out. Please log in again."))
     |> redirect(to: ~p"/users/log-in")}
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

  defp assign_site_toggles(socket, setting) do
    socket
    |> assign(:registration_enabled?, setting.registration_enabled)
    |> assign(:magic_link_enabled?, setting.magic_link_enabled)
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files")
  defp upload_error_to_string(:not_accepted), do: gettext("Invalid file type")
  defp upload_error_to_string(_), do: gettext("Upload failed")

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
      <main id="settings-canvas" class="xamt-home-canvas" phx-hook="MongolianScroll">
        <!-- ==================== 第 1 区：账号概览与头像管理 ==================== -->
        <aside class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h1 class="font-bold text-base tracking-widest mongol-text">
                {gettext("Account & Security")}
              </h1>
            </div>

            <.link
              navigate={~p"/profile/#{@current_scope.user.username}"}
              class="xamt-btn py-2.5 px-2 text-xs font-bold mongol-text"
              title={gettext("View Public Profile")}
            >
              <.icon name="hero-user" class="w-4 h-4 mb-1" />
              <span>{gettext("Profile")}</span>
            </.link>
          </header>
          
    <!-- 头像上传与预览竖条卡片 -->
          <div class="xamt-home-card items-center">
            <div class="flex flex-row items-center gap-3 h-full">
              <div class="w-14 h-14 rounded-2xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-xl overflow-hidden border border-[var(--xamt-line)] shrink-0">
                <img
                  :if={@current_scope.user.avatar}
                  src={@current_scope.user.avatar}
                  alt={User.display_name(@current_scope.user)}
                  class="w-full h-full object-cover"
                />
                <span :if={!@current_scope.user.avatar}>
                  {String.first(User.display_name(@current_scope.user)) |> String.upcase()}
                </span>
              </div>

              <span class="font-bold text-base">
                {User.display_name(@current_scope.user)}
              </span>

              <span class="text-xs text-[var(--xamt-muted)] font-mono">
                {@current_email}
              </span>
            </div>
            
    <!-- 头像操作列 -->
            <form
              id="avatar-form"
              phx-change="validate_avatar"
              phx-submit="save_avatar"
              class="flex flex-col gap-2.5 h-full"
            >
              <label class="xamt-btn py-3 px-2 text-xs font-bold cursor-pointer h-full justify-center">
                <.icon name="hero-camera" class="w-4 h-4 mb-1.5" />
                <span>{gettext("Choose Avatar")}</span>
                <.live_file_input upload={@uploads.avatar} class="sr-only" />
              </label>

              <div :for={entry <- @uploads.avatar.entries} class="flex flex-row items-center gap-2">
                <.live_img_preview entry={entry} class="w-10 h-10 rounded-xl object-cover shrink-0" />
                <button
                  type="button"
                  id={"cancel-avatar-#{entry.ref}"}
                  phx-click="cancel_avatar"
                  phx-value-ref={entry.ref}
                  class="xamt-icon-btn"
                  aria-label={gettext("Cancel upload")}
                >
                  <.icon name="hero-x-mark" class="w-3 h-3" />
                </button>
                <p :for={err <- upload_errors(@uploads.avatar, entry)} class="text-xs text-red-500">
                  {upload_error_to_string(err)}
                </p>
              </div>

              <button
                :if={@uploads.avatar.entries != []}
                type="submit"
                class="xamt-btn xamt-btn--primary py-3 px-2.5 text-xs font-bold h-full"
              >
                <.icon name="hero-arrow-up-tray" class="w-4 h-4 mb-1" />
                <span>{gettext("Upload")}</span>
              </button>

              <button
                :if={@current_scope.user.avatar}
                type="button"
                phx-click="remove_avatar"
                class="xamt-btn py-3 px-2 text-xs text-red-500 border-red-500/30 hover:bg-red-500/10 h-full"
              >
                {gettext("Remove")}
              </button>
            </form>
          </div>
        </aside>
        
    <!-- ==================== 第 2 区：基本资料与自定义状态 ==================== -->
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-identification" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm">{gettext("Profile Info")}</h2>
            </div>
          </header>

          <.form
            for={@profile_form}
            id="profile-form"
            phx-change="validate_profile"
            phx-submit="save_profile"
            class="xamt-home-card"
          >
            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Username")}</span>
              <input
                type="text"
                value={@current_scope.user.username}
                readonly
                class="xamt-bot-input opacity-70"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Display Name")}</span>
              <input
                id="settings-display-name"
                type="text"
                name={@profile_form[:display_name].name}
                value={@profile_form[:display_name].value}
                placeholder={gettext("Mongolian display name...")}
                class="xamt-bot-input"
                phx-hook="MongolianIME"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Status Emoji")}</span>
              <input
                id="settings-status-emoji"
                type="text"
                name="status_emoji"
                value={@current_scope.user.status_emoji}
                placeholder="😊"
                maxlength="10"
                class="xamt-bot-input text-center"
                phx-hook="StatusEmoji"
                autocomplete="off"
                readonly
                inputmode="none"
                aria-haspopup="dialog"
                aria-label={gettext("Pick emoji")}
                title={gettext("Pick emoji")}
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Custom Status")}</span>
              <input
                id="settings-status-text"
                type="text"
                name="status_text"
                value={@current_scope.user.status_text}
                placeholder={gettext("What's on your mind?")}
                maxlength="50"
                class="xamt-bot-input"
                phx-hook="MongolianIME"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Bio")}</span>
              <textarea
                id="settings-bio"
                name={@profile_form[:bio].name}
                placeholder={gettext("Tell us about yourself...")}
                class="xamt-bot-input !w-16"
                phx-hook="MongolianIME"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              >{Phoenix.HTML.Form.normalize_value("textarea", @profile_form[:bio].value)}</textarea>
            </label>

            <button
              type="submit"
              phx-disable-with={gettext("Saving...")}
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs"
            >
              <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Save Profile")}</span>
            </button>
          </.form>
        </section>
        
    <!-- ==================== 第 3 区：修改账号邮箱 (Account Email) ==================== -->
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-envelope" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm">{gettext("Account Email")}</h2>
            </div>
          </header>

          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
            class="xamt-home-card"
          >
            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("New Email")}</span>
              <input
                type="email"
                name={@email_form[:email].name}
                value={@email_form[:email].value}
                autocomplete="username"
                required
                class="xamt-bot-input font-mono text-xs"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <p
              :for={{msg, opts} <- @email_form[:email].errors}
              class="text-xs text-red-500 px-1"
            >
              {translate_error({msg, opts})}
            </p>

            <button
              type="submit"
              phx-disable-with={gettext("Changing...")}
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs"
            >
              <.icon name="hero-paper-airplane" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Change Email")}</span>
            </button>
          </.form>
        </section>
        
    <!-- ==================== 第 4 区：修改登录密码 (Password) ==================== -->
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-key" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm">{gettext("Change Password")}</h2>
            </div>
          </header>

          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
            class="xamt-home-card"
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              autocomplete="username"
              value={@current_email}
            />

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("New Password")}</span>
              <input
                type="password"
                name={@password_form[:password].name}
                value={@password_form[:password].value}
                autocomplete="new-password"
                required
                placeholder="••••••••••••"
                class="xamt-bot-input"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <p
              :for={{msg, opts} <- @password_form[:password].errors}
              class="text-xs text-red-500 px-1"
            >
              {translate_error({msg, opts})}
            </p>

            <label class="xamt-bot-field">
              <span class="xamt-label">{gettext("Confirm New Password")}</span>
              <input
                type="password"
                name={@password_form[:password_confirmation].name}
                value={@password_form[:password_confirmation].value}
                autocomplete="new-password"
                required
                placeholder="••••••••••••"
                class="xamt-bot-input"
                onfocus="setTimeout(() => this.scrollIntoView({behavior: 'smooth', inline: 'center'}), 150)"
              />
            </label>

            <p
              :for={{msg, opts} <- @password_form[:password_confirmation].errors}
              class="text-xs text-red-500 px-1"
            >
              {translate_error({msg, opts})}
            </p>

            <button
              type="submit"
              phx-disable-with={gettext("Saving...")}
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs"
            >
              <.icon name="hero-lock-closed" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Save Password")}</span>
            </button>
          </.form>
        </section>
        
    <!-- ==================== 第 5 区：通知推送与安全退出 ==================== -->
        <section class="xamt-home-section">
          <header class="xamt-home-section__header">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-shield-check" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="font-bold text-sm">{gettext("Notifications & Security")}</h2>
            </div>
          </header>
          
    <!-- 通知开关卡片 -->
          <div
            id="web-push-settings"
            phx-hook="WebPush"
            phx-update="ignore"
            data-vapid-public-key={Layouts.vapid_public_key()}
            class="xamt-home-card"
          >
            <div class="flex flex-row items-center justify-between h-full gap-3">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-bell-alert" class="w-4 h-4 text-[var(--xamt-accent)] shrink-0" />
                <span class="font-bold text-sm">{gettext("Desktop Notifications")}</span>
              </div>

              <button
                type="button"
                data-push-toggle
                class="xamt-btn py-3 px-2 text-xs font-bold"
              >
                {gettext("Enable")}
              </button>
            </div>

            <div class="flex flex-row items-center justify-between h-full gap-3">
              <div class="flex flex-row items-center gap-2">
                <.icon name="hero-speaker-wave" class="w-4 h-4 text-[var(--xamt-accent)] shrink-0" />
                <span class="font-bold text-sm">{gettext("Sound Alerts")}</span>
              </div>

              <button
                type="button"
                data-sound-toggle
                class="xamt-btn py-3 px-2 text-xs font-bold"
              >
                {gettext("Mute")}
              </button>
            </div>
          </div>
          
    <!-- 强制下线所有设备卡片 -->
          <div class="xamt-home-card border-red-500/30">
            <div class="flex flex-row items-center justify-between h-full gap-3">
              <span class="font-bold text-sm text-red-500">
                {gettext("Active Sessions")}
              </span>
              <span class="text-xs text-[var(--xamt-muted)]">
                {gettext("Log out all other browsers and devices.")}
              </span>
            </div>

            <button
              type="button"
              phx-click="revoke_all_sessions"
              data-confirm={gettext("Are you sure you want to log out from all devices?")}
              class="xamt-btn h-full px-3 text-xs font-bold text-red-500 border-red-500/40 hover:bg-red-500/10"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Log out all devices")}</span>
            </button>
          </div>

          <section :if={@site_admin?} id="site-settings" class="xamt-home-card">
            <h2 class="font-bold text-xs text-[var(--xamt-accent)]">
              {gettext("Site")}
            </h2>
            <p class="text-xs text-[var(--xamt-muted)]">
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
                <span class="text-xs font-bold">{gettext("Allow registration")}</span>
                <span class="text-xs text-[var(--xamt-muted)]">
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
                <span class="text-xs font-bold">
                  {gettext("Allow magic link login")}
                </span>
                <span class="text-xs text-[var(--xamt-muted)]">
                  {if @magic_link_enabled?, do: gettext("Open"), else: gettext("Closed")}
                </span>
              </div>
            </div>

            <.link
              navigate={~p"/admin/users"}
              id="manage-users-link"
              class="xamt-btn xamt-btn--soft py-3 px-2 text-xs font-bold"
            >
              {gettext("Users")}
            </.link>
          </section>
        </section>
      </main>
    </Layouts.home>
    """
  end
end
