defmodule XamtWeb.ServerLive.Components do
  @moduledoc false

  use XamtWeb, :html

  import XamtWeb.ServerLive.Rails
  import XamtWeb.ServerLive.MessageList
  import XamtWeb.ServerLive.Composer
  import XamtWeb.ServerLive.Lightbox
  import XamtWeb.ServerLive.Overlays

  def preview(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="xamt-stack" id="server-preview">
        <div class="xamt-auth-intro">
          <span class="xamt-ornament" aria-hidden="true"></span>
          <p class="xamt-kicker mongol-text">{gettext("Public server")}</p>
        </div>

        <.header>
          <span class="mongol-text">{upright_text(@server.name)}</span>
          <:subtitle>
            <span>/{@server.slug}</span>
          </:subtitle>
        </.header>

        <p :if={@server.description} class="xamt-profile__bio mongol-text">
          {upright_text(@server.description)}
        </p>

        <button
          type="button"
          id="join-server"
          class="xamt-btn xamt-btn--primary mongol-text"
          phx-click="join_server"
        >
          {gettext("Join server")}
        </button>

        <.link navigate={~p"/"} id="preview-back" class="xamt-btn mongol-text">
          {gettext("Back")}
        </.link>
      </section>
    </Layouts.app>
    """
  end

  def chat(assigns) do
    ~H"""
    <Layouts.chat flash={@flash} current_scope={@current_scope}>
      <div class="xamt-chat" id="xamt-app" phx-hook="MobileDrawer">
        <div class={"xamt-app xamt-app--panel-#{@mobile_panel}"}>
          <button
            :if={@mobile_panel != :messages}
            type="button"
            id="drawer-backdrop"
            class="xamt-drawer-backdrop"
            phx-click="set_mobile_panel"
            phx-value-panel="messages"
            aria-label={gettext("Close panel")}
          >
          </button>
          <.servers_rail {assigns} />
          <.channels_rail {assigns} />
          <section class="xamt-main">
            <.main_header {assigns} />
            <div class="xamt-chat-window">
              <.messages_region {assigns} />
              <.composer {assigns} />
            </div>
          </section>
        </div>

        <.delete_reason_overlay
          :if={@deleting_message}
          message={@deleting_message}
          form={@delete_reason_form}
        />

        <.status_picker_overlay
          :if={@show_status_picker}
          current_user={@current_scope.user}
        />

        <.poll_details_overlay :if={@poll_details} poll={@poll_details} />

        <.pinned_drawer
          :if={@show_pinned_drawer}
          messages={@pinned_messages}
          can_manage_messages?={@can_manage_messages?}
          current_scope={@current_scope}
        />

        <.server_menu_overlay
          :if={@show_server_menu && @active_channel}
          server={@server}
          active_channel={@active_channel}
          can_manage_channels?={@can_manage_channels?}
        />

        <.server_overlay
          :if={@admin? and @active_channel}
          live_action={@live_action}
          server={@server}
          active_channel={@active_channel}
          channel_form={@channel_form}
          editing_channel={@editing_channel}
        />

        <.lightbox :if={@lightbox_images} {assigns} />
      </div>
    </Layouts.chat>
    """
  end
end
