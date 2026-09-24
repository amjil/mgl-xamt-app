defmodule XamtWeb.AdminUserLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket
      |> change_user(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    save_user(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("Create user"))
    |> assign(:user, %User{})
    |> assign(:form, to_form(Accounts.change_user_admin_registration(%User{}), as: :user))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = Accounts.get_user!(id)

    socket
    |> assign(:page_title, gettext("Edit user"))
    |> assign(:user, user)
    |> assign(:form, to_form(Accounts.change_user_admin_update(user), as: :user))
  end

  defp change_user(%{assigns: %{live_action: :new}}, params) do
    Accounts.change_user_admin_registration(%User{}, params)
  end

  defp change_user(%{assigns: %{live_action: :edit, user: user}}, params) do
    Accounts.change_user_admin_update(user, params)
  end

  defp save_user(socket, :new, params) do
    case Accounts.create_user_as_admin(socket.assigns.current_scope, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Created @%{username}", username: user.username))
         |> assign(:form, to_form(Accounts.change_user_admin_registration(%User{}), as: :user))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to create users."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  defp save_user(socket, :edit, params) do
    case Accounts.update_user_as_admin(socket.assigns.current_scope, socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> maybe_refresh_scope(user)
         |> put_flash(:info, gettext("Updated @%{username}", username: user.username))
         |> push_navigate(to: ~p"/admin/users")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to update users."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  defp maybe_refresh_scope(socket, user) do
    current = socket.assigns.current_scope.user

    if current && current.id == user.id do
      assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})
    else
      socket
    end
  end

  defp role_options do
    [
      {gettext("User"), "user"},
      {gettext("Creator"), "creator"},
      {gettext("Admin"), "admin"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section
        class="xamt-stack"
        id={if(@live_action == :edit, do: "admin-edit-user", else: "admin-create-user")}
      >
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Site")}</p>
        </div>
        <.header>
          <span class="mongol-text">
            {if @live_action == :edit, do: gettext("Edit user"), else: gettext("Create user")}
          </span>
          <:subtitle>
            <%= if @live_action == :edit do %>
              {gettext("Change this account's profile, role, or password.")}
            <% else %>
              {gettext("Add an account even when public registration is closed.")}
            <% end %>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id={if(@live_action == :edit, do: "admin-edit-user-form", else: "admin-create-user-form")}
          phx-change="validate"
          phx-submit="save"
          class="xamt-form xamt-form--vertical"
        >
          <.input
            field={@form[:display_name]}
            type="text"
            label={gettext("Display name")}
            class="xamt-input mongol-input"
            phx-hook="MongolianIME"
            autocomplete="nickname"
          />
          <.input
            field={@form[:username]}
            type="text"
            label={gettext("Username")}
            class="xamt-input xamt-input--latin"
            autocomplete="off"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            class="xamt-input xamt-input--latin"
            autocomplete="off"
            spellcheck="false"
            required
          />
          <.input
            :if={@live_action == :edit}
            field={@form[:bio]}
            type="textarea"
            label={gettext("Bio")}
            class="xamt-textarea mongol-input"
            phx-hook="MongolianIME"
          />
          <.input
            field={@form[:password]}
            type="password"
            label={if(@live_action == :edit, do: gettext("New password"), else: gettext("Password"))}
            class="xamt-input xamt-input--latin"
            autocomplete="new-password"
            required={@live_action == :new}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm password")}
            class="xamt-input xamt-input--latin"
            autocomplete="new-password"
            required={@live_action == :new}
          />
          <p :if={@live_action == :edit} class="xamt-muted mongol-text">
            {gettext("Leave blank to keep the current password.")}
          </p>
          <.input
            field={@form[:global_role]}
            type="select"
            label={gettext("Role")}
            options={role_options()}
          />

          <button
            type="submit"
            id={if(@live_action == :edit, do: "edit-user-submit", else: "create-user-submit")}
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            {if @live_action == :edit, do: gettext("Save user"), else: gettext("Create user")}
          </button>
        </.form>

        <.link navigate={~p"/admin/users"} id="admin-user-back" class="xamt-btn mongol-text">
          {gettext("Back")}
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
