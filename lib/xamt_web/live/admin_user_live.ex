defmodule XamtWeb.AdminUserLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts
  alias Xamt.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Create user"))
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_admin_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.create_user_as_admin(socket.assigns.current_scope, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Created @%{username}", username: user.username))
         |> assign_form()}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to create users."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(Accounts.change_user_admin_registration(%User{}), as: :user))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="xamt-stack" id="admin-create-user">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Site")}</p>
        </div>
        <.header>
          <span class="mongol-text">{gettext("Create user")}</span>
          <:subtitle>
            {gettext("Add an account even when public registration is closed.")}
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="admin-create-user-form"
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
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            class="xamt-input xamt-input--latin"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm password")}
            class="xamt-input xamt-input--latin"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:global_role]}
            type="select"
            label={gettext("Role")}
            options={[
              {gettext("User"), "user"},
              {gettext("Creator"), "creator"},
              {gettext("Admin"), "admin"}
            ]}
          />

          <button type="submit" id="create-user-submit" class="xamt-btn xamt-btn--primary mongol-text">
            {gettext("Create user")}
          </button>
        </.form>

        <.link navigate={~p"/settings"} id="create-user-back" class="xamt-btn mongol-text">
          {gettext("Back")}
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
