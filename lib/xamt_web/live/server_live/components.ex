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
    <Layouts.home
      flash={@flash}
      current_scope={@current_scope}
      show_search={@show_search}
      global_search_query={@global_search_query}
      global_search_results={@global_search_results}
    >
      <main id="server-preview" class="xamt-home-canvas" phx-hook="MongolianScroll">
        <aside class="xamt-home-section">
          <div class="flex flex-row items-center justify-between h-full py-1">
            <div class="flex flex-row items-center gap-3">
              <.link navigate={~p"/"} id="preview-back" class="xamt-icon-btn" title={gettext("Back")}>
                <.icon name="hero-arrow-left" class="w-5 h-5" />
              </.link>
              <span class="xamt-ornament !h-10" aria-hidden="true"></span>
              <p class="xamt-kicker mongol-text">{gettext("Public server")}</p>
            </div>
          </div>
        </aside>

        <section class="xamt-home-section">
          <div class="xamt-home-card items-center">
            <div class="flex flex-row items-center gap-3 h-full">
              <div class="w-12 h-12 rounded-2xl bg-[var(--xamt-accent)]/15 text-[var(--xamt-accent)] flex items-center justify-center font-bold text-lg shrink-0">
                {String.first(@server.name) || "?"}
              </div>
              <h1 class="text-xl font-bold mongol-text">
                {upright_text(@server.name)}
              </h1>
              <span class="text-xs text-[var(--xamt-muted)] font-mono">
                /{@server.slug}
              </span>
            </div>

            <p
              :if={@server.description}
              class="xamt-profile__bio text-sm text-[var(--xamt-muted)] mongol-text h-full px-1"
            >
              {upright_text(@server.description)}
            </p>

            <button
              type="button"
              id="join-server"
              class="xamt-btn xamt-btn--primary h-full px-4 font-bold mongol-text"
              phx-click="join_server"
            >
              <.icon name="hero-arrow-right-end-on-rectangle" class="w-5 h-5 mb-2" />
              <span>{gettext("Join server")}</span>
            </button>
          </div>
        </section>
      </main>
    </Layouts.home>
    """
  end

  def chat(assigns) do
    ~H"""
    <Layouts.chat
      flash={@flash}
      current_scope={@current_scope}
      show_search={@show_search}
      global_search_query={@global_search_query}
      global_search_results={@global_search_results}
    >
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

        <.bot_management_sheet
          show={@show_bot_manager}
          installations={@bot_installations}
          selected_installation={@selected_bot_installation}
          channels={@channels}
          newly_issued_token={@newly_issued_bot_token}
          show_create_form={@show_bot_create_form}
        />

        <.lightbox :if={@lightbox_images} {assigns} />
      </div>
    </Layouts.chat>
    """
  end
end
