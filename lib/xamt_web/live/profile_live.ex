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
    <div :if={@profile_user} class="xamt-page-inner">
      <Layouts.flash_group flash={@flash} />
      <div class="xamt-profile">
        <header class="xamt-profile__header">
          <div class="xamt-avatar xamt-avatar--lg">{user_initial(@profile_user)}</div>
          <div>
            <h1 class="mongol-text">{display_name(@profile_user)}</h1>
            <p class="xamt-profile__username">@{@profile_user.username}</p>
          </div>
        </header>
        <p :if={@profile_user.bio} class="xamt-profile__bio mongol-text">{@profile_user.bio}</p>
        <p :if={!@profile_user.bio} class="xamt-empty mongol-text">{gettext("No bio yet.")}</p>
        <.link navigate={~p"/"} class="xamt-btn mongol-text">{gettext("Back")}</.link>
      </div>
    </div>
    """
  end

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: name}), do: name

  defp user_initial(user) do
    display_name(user) |> String.trim() |> String.first() || "?"
  end
end
