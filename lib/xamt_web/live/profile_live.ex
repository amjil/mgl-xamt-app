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
       |> assign(:profile_user, user)
       |> assign(:role_ui, RoleHelper.get_role_ui_config(user))}
    else
      {:ok,
       socket
       |> assign(:profile_user, nil)
       |> assign(:role_ui, nil)
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

        <article class={["xamt-profile xamt-surface", @role_ui.accent_class]}>
          <.status_avatar user={@profile_user} class="xamt-avatar xamt-avatar--lg" />

          <div class="xamt-profile__identity">
            <div class="xamt-profile__names">
              <h1 class={["xamt-profile__display-name mongol-text", @role_ui.color_class]}>
                {display_name(@profile_user)}
              </h1>
              <p class="xamt-profile__username">@{@profile_user.username}</p>
            </div>
            <div
              :if={@role_ui.label}
              id="profile-role-badge"
              class={["xamt-role-badge", @role_ui.bg_class]}
            >
              <.icon name={@role_ui.icon} class="w-3 h-3 shrink-0" />
              <span>{@role_ui.label}</span>
            </div>
            <p :if={status_line?(@profile_user)} class="xamt-profile__status">
              <span :if={@profile_user.status_emoji} class="xamt-emoji">
                {@profile_user.status_emoji}
              </span>
              <span :if={@profile_user.status_text} class="mongol-text">
                {@profile_user.status_text}
              </span>
            </p>
          </div>

          <div class="xamt-profile__about">
            <span class="xamt-field__label mongol-text">{gettext("Bio")}</span>
            <p :if={@profile_user.bio} class="xamt-profile__bio mongol-text">{@profile_user.bio}</p>
            <p :if={!@profile_user.bio} class="xamt-profile__bio xamt-empty mongol-text">
              {gettext("No bio yet.")}
            </p>
          </div>

          <nav class="xamt-profile__actions">
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
          </nav>
        </article>
      </section>
    </Layouts.app>
    """
  end

  defp own_profile?(%{user: %{id: id}}, %{id: id}) when not is_nil(id), do: true
  defp own_profile?(_, _), do: false

  defp status_line?(%{status_emoji: emoji}) when is_binary(emoji) and emoji != "", do: true
  defp status_line?(%{status_text: text}) when is_binary(text) and text != "", do: true
  defp status_line?(_), do: false

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}), do: name
end
