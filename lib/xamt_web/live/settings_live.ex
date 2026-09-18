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
     |> assign(:form, to_form(changeset, as: :user))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_scope.user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_user_profile(socket.assigns.current_scope.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
         |> assign(:form, to_form(Accounts.change_user_profile(user), as: :user))
         |> put_flash(:info, gettext("Profile updated"))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="xamt-settings">
      <Layouts.flash_group flash={@flash} />
      <h1 class="xamt-section-title">{gettext("Settings")}</h1>
      <.form
        for={@form}
        id="settings-form"
        phx-change="validate"
        phx-submit="save"
        class="xamt-form"
      >
        <label class="xamt-label">
          <span>{gettext("Display name")}</span>
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
        <label class="xamt-label">
          <span>{gettext("Bio")}</span>
          <textarea
            name={@form[:bio].name}
            id={@form[:bio].id}
            rows="4"
            class="xamt-input mongol-input"
            phx-hook="MongolianIME"
          >{Phoenix.HTML.Form.normalize_value("textarea", @form[:bio].value)}</textarea>
        </label>
        <label class="xamt-label">
          <span>{gettext("Avatar URL")}</span>
          <input
            type="text"
            name={@form[:avatar].name}
            id={@form[:avatar].id}
            value={@form[:avatar].value}
            class="xamt-input"
          />
        </label>
        <button type="submit" class="xamt-btn xamt-btn--primary">{gettext("Save")}</button>
      </.form>

      <div class="xamt-settings__links">
        <.link href={~p"/users/settings"} class="xamt-btn">{gettext("Account / password")}</.link>
        <.link href={~p"/users/log-out"} method="delete" class="xamt-btn">
          {gettext("Log out")}
        </.link>
      </div>
    </div>
    """
  end
end
