defmodule XamtWeb.ProfileLive do
  use XamtWeb, :live_view

  alias Xamt.Accounts

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    user = Accounts.get_user_by_username(username)

    if user do
      {:ok,
       socket
       |> assign(:page_title, user.display_name || user.username)
       |> assign(:profile_user, user)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("User not found"))
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section :if={@profile_user} class="xamt-stack" id="profile-panel">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Profile")}</p>
        </div>

        <.header>
          {display_name(@profile_user)}
          <:subtitle>
            <span class="xamt-profile__username">@{@profile_user.username}</span>
          </:subtitle>
        </.header>

        <div class="xamt-profile xamt-surface">
          <div class="xamt-avatar xamt-avatar--lg" aria-hidden="true">
            {user_initial(@profile_user)}
          </div>

          <div class="xamt-profile__col">
            <span class="xamt-field__label mongol-text">{gettext("Bio")}</span>
            <p :if={@profile_user.bio} class="xamt-profile__bio mongol-text">{@profile_user.bio}</p>
            <p :if={!@profile_user.bio} class="xamt-profile__bio xamt-empty mongol-text">
              {gettext("No bio yet.")}
            </p>
          </div>

          <.link
            :if={own_profile?(@current_scope, @profile_user)}
            navigate={~p"/settings"}
            id="profile-edit"
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            {gettext("Edit")}
          </.link>
          <.link navigate={~p"/"} id="profile-back" class="xamt-btn mongol-text">
            {gettext("Back")}
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp own_profile?(%{user: %{id: id}}, %{id: id}) when not is_nil(id), do: true
  defp own_profile?(_, _), do: false

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}), do: name

  defp user_initial(user) do
    display_name(user) |> String.trim() |> String.first() || "?"
  end
end
