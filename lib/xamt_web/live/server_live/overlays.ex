defmodule XamtWeb.ServerLive.Overlays do
  @moduledoc false

  use XamtWeb, :html

  alias Xamt.Messages
  import XamtWeb.ServerLive.Helpers, only: [display_name: 1, safe_html: 2]

  attr :id, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  def action_menu(assigns) do
    ~H"""
    <details id={@id} class="xamt-menu">
      <summary class="xamt-icon-btn" aria-label={@label}>
        <.icon name="hero-ellipsis-vertical" class="size-4" />
      </summary>
      <div class="xamt-menu__list">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :message, :map, required: true
  attr :form, :map, required: true

  def delete_reason_overlay(assigns) do
    ~H"""
    <div
      id="delete-reason-drawer"
      class="xamt-modal"
      phx-window-keydown="cancel_delete_message"
      phx-key="Escape"
    >
      <div class="xamt-modal-backdrop" phx-click="cancel_delete_message"></div>

      <div
        id="delete-reason-card"
        class="xamt-bot-modal-card xamt-bot-modal-card--compact relative z-10"
        phx-hook="MongolianScroll"
      >
        <%!-- Column 1: Title & Close --%>
        <div class="xamt-bot-pane !flex-row justify-between items-center">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-trash" class="w-5 h-5 text-[var(--xamt-error)] shrink-0" />
            <h2 id="delete-reason-title" class="text-lg font-bold tracking-wider mongol-text">
              {gettext("Delete message")}
            </h2>
          </div>

          <button
            type="button"
            phx-click="cancel_delete_message"
            class="xamt-icon-btn"
            title={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Column 2: Message Excerpt & Delete Reason Form --%>
        <.form
          for={@form}
          id="delete-reason-form"
          phx-submit="confirm_delete_message"
          novalidate
        >
          <div class="xamt-bot-pane">
            <p id="delete-reason-preview" class="xamt-delete-reason__preview mongol-text">
              {Messages.excerpt(@message, 80)}
            </p>

            <.input field={@form[:id]} type="hidden" />

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Reason (optional)")}</span>
              <input
                type="text"
                id="delete-reason"
                name={@form[:reason].name}
                value={@form[:reason].value}
                phx-hook="MongolianIME"
                class="xamt-bot-input mongol-input"
                autocomplete="off"
              />
            </label>

            <div class="flex flex-row items-center gap-3 h-full">
              <button
                type="submit"
                id="delete-reason-submit"
                class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
              >
                <.icon name="hero-trash" class="w-4 h-4 mb-1.5" />
                <span>{gettext("Delete")}</span>
              </button>
              <button
                type="button"
                id="delete-reason-cancel"
                class="xamt-btn h-full px-2.5 text-xs mongol-text"
                phx-click="cancel_delete_message"
              >
                {gettext("Cancel")}
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :current_user, :map, required: true

  def status_picker_overlay(assigns) do
    ~H"""
    <div
      id="status-picker-drawer"
      class="xamt-modal"
      phx-window-keydown="close_status_picker"
      phx-key="Escape"
    >
      <div class="xamt-modal-backdrop" phx-click="close_status_picker"></div>

      <div
        id="status-picker-card"
        class="xamt-bot-modal-card xamt-bot-modal-card--compact relative z-10 xamt-status-picker"
        phx-hook="MongolianScroll"
      >
        <%!-- Column 1: Title & Close --%>
        <div class="xamt-bot-pane !flex-row justify-between items-center">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-face-smile" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 id="status-picker-title" class="text-lg font-bold tracking-wider mongol-text">
              {gettext("Set custom status")}
            </h2>
          </div>

          <button
            type="button"
            phx-click="close_status_picker"
            class="xamt-icon-btn"
            title={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Column 2: Presets --%>
        <div class="xamt-bot-pane" role="list">
          <button
            :for={{preset, idx} <- Enum.with_index(Xamt.Accounts.custom_status_presets())}
            type="button"
            id={"status-preset-#{idx}"}
            class="xamt-bot-strip justify-start gap-2.5"
            phx-click="set_status"
            phx-value-emoji={preset["emoji"]}
            phx-value-text={preset["text"]}
          >
            <span class="xamt-status-btn__emoji xamt-upright" aria-hidden="true">
              {preset["emoji"]}
            </span>
            <span class="xamt-status-btn__text mongol-text font-bold text-sm">
              {preset["text"]}
            </span>
          </button>

          <button
            type="button"
            id="status-clear"
            class="xamt-bot-strip justify-center text-[var(--xamt-error)] font-bold text-xs mongol-text"
            phx-click="clear_status"
          >
            {gettext("Clear status")}
          </button>
        </div>

        <%!-- Column 3: Custom Emoji + Status Text Form --%>
        <form
          id="status-custom-form"
          phx-submit="save_custom_status"
        >
          <div class="xamt-bot-pane">
            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Choose emoji")}</span>
              <input
                type="text"
                name="emoji"
                id="status-custom-emoji"
                value={@current_user.status_emoji}
                placeholder="😀"
                maxlength="10"
                class="xamt-input xamt-status-picker__emoji"
                phx-hook="StatusEmoji"
                autocomplete="off"
                readonly
                inputmode="none"
                aria-haspopup="dialog"
                aria-label={gettext("Choose emoji")}
                title={gettext("Choose emoji")}
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Custom Status")}</span>
              <input
                type="text"
                name="text"
                id="status-custom-text"
                value={@current_user.status_text}
                placeholder={gettext("Say something...")}
                maxlength="50"
                class="xamt-bot-input mongol-input xamt-status-picker__text"
                phx-hook="MongolianIME"
                autocomplete="off"
              />
            </label>

            <button
              type="submit"
              id="status-custom-save"
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
            >
              <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Save")}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :server, :map, required: true
  attr :active_channel, :map, required: true
  attr :can_manage_channels?, :boolean, default: false

  def server_menu_overlay(assigns) do
    ~H"""
    <div
      id="server-menu-drawer"
      class="xamt-modal"
      phx-window-keydown="close_server_menu"
      phx-key="Escape"
    >
      <div class="xamt-modal-backdrop" phx-click="close_server_menu"></div>

      <div
        id="server-menu-card"
        class="xamt-bot-modal-card xamt-bot-modal-card--compact relative z-10 xamt-server-menu-sheet"
        phx-hook="MongolianScroll"
      >
        <%!-- Column 1: Server Title & Close --%>
        <div class="xamt-bot-pane !flex-row justify-between items-center">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-building-library" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 id="server-menu-title" class="text-lg font-bold tracking-wider mongol-text">
              {upright_text(@server.name)}
            </h2>
          </div>

          <button
            type="button"
            phx-click="close_server_menu"
            class="xamt-icon-btn"
            title={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Column 2: Slug, Description & Channel Action --%>
        <div class="xamt-bot-pane">
          <p id="server-menu-slug" class="xamt-server-menu-sheet__slug">/{@server.slug}</p>

          <p
            :if={@server.description}
            id="server-menu-description"
            class="xamt-server-menu-sheet__desc mongol-text"
          >
            {upright_text(@server.description)}
          </p>

          <nav
            :if={@can_manage_channels?}
            class="xamt-server-menu-sheet__nav h-full"
            aria-labelledby="server-menu-title"
          >
            <.link
              id="server-menu-new-channel"
              patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/new"}
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
            >
              <.icon name="hero-plus" class="w-4 h-4 mb-1.5" />
              <span>{gettext("Create channel")}</span>
            </.link>
          </nav>
        </div>
      </div>
    </div>
    """
  end

  attr :live_action, :atom, required: true
  attr :server, :map, required: true
  attr :active_channel, :map, required: true
  attr :channel_form, :map, required: true
  attr :editing_channel, :map

  def server_overlay(assigns) do
    ~H"""
    <div
      :if={@live_action in [:new_channel, :edit_channel]}
      id="server-drawer"
      class="xamt-modal"
      phx-window-keydown={JS.patch(~p"/servers/#{@server.slug}/#{@active_channel.slug}")}
      phx-key="Escape"
    >
      <.link
        patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}"}
        class="xamt-modal-backdrop"
        aria-label={gettext("Close")}
      >
      </.link>

      <.channel_sheet
        :if={@live_action == :new_channel}
        id="create-channel-form"
        form={@channel_form}
        title={gettext("Create channel")}
        submit_label={gettext("Create")}
        return_to={~p"/servers/#{@server.slug}/#{@active_channel.slug}"}
      />
      <.channel_sheet
        :if={@live_action == :edit_channel and @editing_channel}
        id="edit-channel-form"
        form={@channel_form}
        title={gettext("Rename channel")}
        submit_label={gettext("Save")}
        name_id="edit-channel-name"
        return_to={~p"/servers/#{@server.slug}/#{@active_channel.slug}"}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :form, :map, required: true
  attr :title, :string, required: true
  attr :submit_label, :string, required: true
  attr :return_to, :string, required: true
  attr :name_id, :string, default: "channel_name"

  def channel_sheet(assigns) do
    ~H"""
    <div
      id={"#{@id}-card"}
      class="xamt-bot-modal-card xamt-bot-modal-card--compact relative z-10"
      phx-hook="MongolianScroll"
    >
      <%!-- Column 1: Title & Close --%>
      <div class="xamt-bot-pane !flex-row justify-between items-center">
        <div class="flex flex-row items-center gap-2">
          <.icon name="hero-hashtag" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
          <h2 id={"#{@id}-title"} class="text-lg font-bold tracking-wider mongol-text">
            {@title}
          </h2>
        </div>

        <.link patch={@return_to} class="xamt-icon-btn" title={gettext("Close")}>
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </.link>
      </div>

      <%!-- Column 2: Channel Form --%>
      <.form
        for={@form}
        id={@id}
        phx-submit="save_channel"
        novalidate
      >
        <div class="xamt-bot-pane">
          <label class="xamt-bot-field">
            <span class="xamt-label mongol-text">{gettext("Channel name")}</span>
            <input
              type="text"
              id={@name_id}
              name={@form[:name].name}
              value={@form[:name].value}
              phx-hook="MongolianIME"
              class="xamt-bot-input mongol-input"
              autocomplete="off"
              required
            />
            <p
              :for={msg <- Enum.map(@form[:name].errors, &translate_error(&1))}
              class="text-xs text-red-500 mongol-text"
            >
              {msg}
            </p>
          </label>

          <div class="flex flex-row items-center gap-3 h-full">
            <button
              type="submit"
              id={"#{@id}-submit"}
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold text-xs mongol-text"
            >
              <.icon name="hero-check" class="w-4 h-4 mb-1.5" />
              <span>{@submit_label}</span>
            </button>
            <.link
              patch={@return_to}
              id={"#{@id}-cancel"}
              class="xamt-btn h-full px-2.5 text-xs mongol-text"
            >
              {gettext("Cancel")}
            </.link>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  attr :poll, :map, required: true

  def poll_details_overlay(assigns) do
    ~H"""
    <div
      id="poll-details-drawer"
      class="xamt-modal"
      phx-window-keydown="close_poll_details"
      phx-key="Escape"
    >
      <div class="xamt-modal-backdrop" phx-click="close_poll_details"></div>

      <div
        id="poll-details-card"
        class="xamt-bot-modal-card xamt-bot-modal-card--compact relative z-10 xamt-poll-details"
        phx-hook="MongolianScroll"
      >
        <%!-- Column 1: Title & Close --%>
        <div class="xamt-bot-pane !flex-row justify-between items-center">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-chart-bar" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 id="poll-details-title" class="text-lg font-bold tracking-wider mongol-text">
              {gettext("Poll details")}
            </h2>
          </div>

          <button
            type="button"
            phx-click="close_poll_details"
            class="xamt-icon-btn"
            title={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Column 2: Question & Meta --%>
        <div class="xamt-bot-pane">
          <p class="xamt-poll-details__question mongol-text font-bold">{@poll.question}</p>
          <p class="xamt-poll-details__meta">
            <span class="mongol-text">
              {if @poll.allow_multiple,
                do: gettext("Multiple answers"),
                else: gettext("Single answer")}
            </span>
            <span class="xamt-poll-details__total">
              <span class="mongol-text">{gettext("Total")}</span>
              <span class="xamt-poll-details__count">{@poll.total_votes}</span>
            </span>
          </p>
        </div>

        <%!-- Column 3: Options & Voters --%>
        <div id="poll-details-body" class="xamt-bot-pane">
          <section
            :for={option <- @poll.options}
            id={"poll-details-option-#{option.id}"}
            class="xamt-poll-details__option h-full"
          >
            <header class="xamt-poll-details__option-head">
              <h3 class="xamt-poll-details__option-text mongol-text">{option.text}</h3>
              <span class="xamt-poll-details__option-count">{option.votes_count}</span>
            </header>

            <p
              :if={option.voters == []}
              class="xamt-poll-details__empty mongol-text"
            >
              {gettext("No votes yet")}
            </p>

            <ul :if={option.voters != []} class="xamt-poll-details__voters">
              <li
                :for={voter <- option.voters}
                id={"poll-voter-#{option.id}-#{voter.id}"}
                class="xamt-poll-details__voter"
              >
                <.status_avatar user={voter} class="xamt-poll-details__avatar" />
                <span class="xamt-poll-details__name mongol-text">
                  {voter.display_name || voter.username}
                </span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :can_manage_messages?, :boolean, default: false
  attr :current_scope, :map, required: true

  def pinned_drawer(assigns) do
    ~H"""
    <div
      id="pinned-messages-drawer"
      class="xamt-modal"
      phx-window-keydown="close_pinned_drawer"
      phx-key="Escape"
    >
      <div class="xamt-modal-backdrop" phx-click="close_pinned_drawer"></div>

      <div
        id="pinned-messages-card"
        class="xamt-bot-modal-card xamt-bot-modal-card--compact relative z-10 xamt-pinned-drawer"
        phx-hook="MongolianScroll"
      >
        <%!-- Column 1: Title & Close --%>
        <div class="xamt-bot-pane !flex-row justify-between items-center">
          <h2 id="pinned-messages-title" class="xamt-pinned-drawer__title">
            <.icon name="hero-bookmark-square" class="size-5 text-[var(--xamt-accent)]" />
            <span class="text-lg font-bold tracking-wider mongol-text">
              {gettext("Pinned messages")}
            </span>
          </h2>

          <button
            type="button"
            phx-click="close_pinned_drawer"
            class="xamt-icon-btn"
            title={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Column 2: Pinned Messages List --%>
        <div class="xamt-bot-pane">
          <p
            :if={@messages == []}
            id="pinned-messages-empty"
            class="xamt-pinned-drawer__empty mongol-text"
          >
            {gettext("No pinned messages yet")}
          </p>

          <div :if={@messages != []} id="pinned-messages-list" class="xamt-pinned-drawer__list">
            <article
              :for={msg <- @messages}
              id={"pinned-msg-#{msg.id}"}
              class="xamt-pinned-card h-full"
            >
              <button
                :if={@can_manage_messages?}
                type="button"
                id={"unpin-message-#{msg.id}"}
                class="xamt-pinned-card__unpin"
                phx-click="toggle_pin"
                phx-value-id={msg.id}
                title={gettext("Unpin")}
                aria-label={gettext("Unpin")}
              >
                <.icon name="hero-minus" class="size-4" />
              </button>

              <div class="xamt-pinned-card__header">
                <.status_avatar user={msg.user} class="xamt-message__avatar" />
              </div>

              <div class="xamt-pinned-card__body">
                <% pin_role = RoleHelper.get_role_ui_config(msg.user) %>
                <header class="xamt-pinned-card__meta">
                  <strong class={["xamt-pinned-card__name mongol-text", pin_role.color_class]}>
                    {display_name(msg.user)}
                  </strong>
                  <div
                    :if={pin_role.label}
                    class={["xamt-role-badge", pin_role.bg_class]}
                  >
                    <.icon name={pin_role.icon} class="w-3 h-3 shrink-0" />
                    <span>{pin_role.label}</span>
                  </div>
                  <time
                    class="xamt-pinned-card__time"
                    datetime={DateTime.to_iso8601(msg.inserted_at)}
                  >
                    {Calendar.strftime(msg.inserted_at, "%m/%d")}
                  </time>
                </header>

                <div class="xamt-pinned-card__content mongol-text">
                  {raw(safe_html(msg, @current_scope.user.id))}
                </div>
              </div>
            </article>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :show, :boolean, default: false
  attr :installations, :list, default: []
  attr :selected_installation, :any, default: nil
  attr :delivery_events, :list, default: []
  attr :channels, :list, default: []
  attr :newly_issued_token, :string, default: nil
  attr :show_create_form, :boolean, default: false

  def bot_management_sheet(assigns) do
    ~H"""
    <div
      :if={@show}
      id="bot-manager-modal"
      class="xamt-modal"
      phx-window-keydown="close_bot_manager"
      phx-key="Escape"
    >
      <div class="xamt-modal-backdrop" phx-click="close_bot_manager"></div>

      <div
        id="bot-manager-card"
        class="xamt-bot-modal-card relative z-10"
        phx-hook="MongolianScroll"
      >
        <%!-- Column 1: title and close --%>
        <div class="xamt-bot-pane !flex-row justify-between items-center">
          <div class="flex flex-row items-center gap-2">
            <.icon name="hero-cpu-chip" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
            <h2 class="text-lg font-bold tracking-wider mongol-text">
              {gettext("Bot Manager")}
            </h2>
          </div>

          <button
            type="button"
            phx-click="close_bot_manager"
            class="xamt-icon-btn"
            title={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>

        <%!-- Column 2: installed bots and create entry --%>
        <div class="xamt-bot-pane">
          <button
            type="button"
            phx-click="toggle_bot_create_form"
            class={[
              "xamt-bot-strip font-bold justify-center gap-2",
              @show_create_form && "is-active text-[var(--xamt-accent)]"
            ]}
          >
            <.icon name="hero-plus-circle" class="w-5 h-5 shrink-0" />
            <span class="mongol-text">
              {if @show_create_form,
                do: gettext("Back to list"),
                else: gettext("Register & Install Bot")}
            </span>
          </button>

          <div class={["xamt-bot-installs", @show_create_form && "xamt-bot-pane--hide-mobile"]}>
            <div
              :for={inst <- @installations}
              phx-click="select_bot_installation"
              phx-value-id={inst.id}
              class={[
                "xamt-bot-strip",
                @selected_installation && @selected_installation.id == inst.id && !@show_create_form &&
                  "is-active"
              ]}
            >
              <div class="flex flex-row items-center gap-2">
                <span class={[
                  "w-2.5 h-2.5 rounded-full shrink-0",
                  inst.status == "enabled" && "bg-emerald-500",
                  inst.status != "enabled" && "bg-zinc-400"
                ]} />
                <span class="font-bold text-base mongol-text">{inst.bot.name}</span>
              </div>

              <span class="text-xs text-[var(--xamt-muted)] mongol-text">
                {if inst.status == "enabled", do: gettext("Enabled"), else: gettext("Disabled")}
              </span>
            </div>

            <div
              :if={@installations == []}
              class="flex flex-row items-center justify-center h-full text-xs text-[var(--xamt-muted)] px-2 mongol-text"
            >
              {gettext("No bots installed yet")}
            </div>
          </div>
        </div>

        <%!-- One-time token notice --%>
        <div
          :if={@newly_issued_token}
          class="xamt-bot-pane bg-amber-500/10 border border-amber-500/40 rounded-xl px-3 py-3"
        >
          <div class="flex flex-row items-center gap-2 text-amber-500 font-bold">
            <.icon name="hero-key" class="w-5 h-5 shrink-0" />
            <span class="mongol-text">{gettext("Copy this token now (shown once)")}</span>
          </div>

          <div class="xamt-bot-code-strip text-amber-500 border-amber-500/30">
            {@newly_issued_token}
          </div>

          <button
            type="button"
            phx-click="dismiss_bot_token"
            class="xamt-btn py-3 px-2 text-xs font-bold self-end mongol-text"
          >
            {gettext("Saved — dismiss")}
          </button>
        </div>

        <%!-- View A: create bot form --%>
        <form
          :if={@show_create_form}
          id="bot-create-form"
          phx-submit="create_and_install_bot"
        >
          <div class="xamt-bot-pane">
            <div class="font-bold text-sm text-[var(--xamt-accent)] mongol-text">
              {gettext("New Bot Details")}
            </div>

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Bot Name")}</span>
              <input
                id="new-bot-name-input"
                type="text"
                name="bot[name]"
                required
                placeholder={gettext("Mongolian or general name...")}
                class="xamt-bot-input mongol-input"
                phx-hook="MongolianIME"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Description")}</span>
              <input
                id="new-bot-desc-input"
                type="text"
                name="bot[description]"
                placeholder={gettext("What this bot does...")}
                class="xamt-bot-input mongol-input"
                phx-hook="MongolianIME"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Webhook URL")}</span>
              <input
                type="url"
                name="bot[webhook_url]"
                required
                placeholder="https://example.com/webhook"
                class="xamt-bot-input font-mono text-xs"
              />
            </label>

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Avatar URL (optional)")}</span>
              <input
                type="url"
                name="bot[avatar_url]"
                placeholder="https://example.com/bot-avatar.png"
                class="xamt-bot-input font-mono text-xs"
              />
            </label>

            <button type="submit" class="xamt-btn xamt-btn--primary h-full px-3 font-bold mongol-text">
              <.icon name="hero-check" class="w-5 h-5 mb-2" />
              <span>{gettext("Create & Install")}</span>
            </button>
          </div>
        </form>

        <%!-- View B: installed bot config --%>
        <form
          :if={@selected_installation && !@show_create_form}
          id={"bot-config-form-#{@selected_installation.id}"}
          phx-submit="save_bot_installation_config"
        >
          <input type="hidden" name="installation_id" value={@selected_installation.id} />

          <%!-- Sub-column 1: status and credentials --%>
          <div class="xamt-bot-pane">
            <div class="flex flex-row items-center justify-between h-full">
              <span class="font-bold text-base text-[var(--xamt-accent)] mongol-text">
                {@selected_installation.bot.name}
              </span>
              <span class="text-xs text-[var(--xamt-muted)] mongol-text">
                {@selected_installation.bot.description}
              </span>
            </div>

            <label class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Status")}</span>
              <select
                id={"bot-status-select-#{@selected_installation.id}"}
                name="status"
                class="xamt-bot-input"
                phx-hook="MnSelect"
              >
                <option value="enabled" selected={@selected_installation.status == "enabled"}>
                  {gettext("Enabled")}
                </option>
                <option value="disabled" selected={@selected_installation.status == "disabled"}>
                  {gettext("Disabled")}
                </option>
              </select>
            </label>

            <div class="xamt-bot-field">
              <span class="xamt-label">Webhook URL</span>
              <div class="xamt-bot-code-strip text-[var(--xamt-muted)]">
                {@selected_installation.bot.webhook_url}
              </div>
            </div>

            <div class="xamt-bot-field">
              <span class="xamt-label mongol-text">{gettext("Signing Secret")}</span>
              <div class="xamt-bot-code-strip">
                {@selected_installation.bot.signing_secret}
              </div>
            </div>

            <div class="xamt-bot-field justify-between">
              <span class="xamt-label">
                Token: {if t = List.first(@selected_installation.tokens),
                  do: t.token_prefix <> "...",
                  else: "-"}
              </span>
              <div class="flex flex-row items-center gap-2">
                <button
                  type="button"
                  phx-click="rotate_bot_token"
                  phx-value-id={@selected_installation.id}
                  data-confirm={gettext("The old token will stop working immediately. Continue?")}
                  class="xamt-btn text-amber-500 border-amber-500/40 py-2.5 px-2 text-xs font-bold mongol-text"
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4 mb-1" />
                  <span>{gettext("Rotate Token")}</span>
                </button>

                <button
                  type="button"
                  id={"uninstall-bot-#{@selected_installation.id}"}
                  phx-click="uninstall_bot"
                  phx-value-id={@selected_installation.id}
                  data-confirm={gettext("Uninstall this bot and revoke its tokens?")}
                  class="xamt-btn text-[var(--xamt-error)] border-[var(--xamt-error)]/40 py-2.5 px-2 text-xs font-bold mongol-text"
                >
                  <.icon name="hero-trash" class="w-4 h-4 mb-1" />
                  <span>{gettext("Uninstall")}</span>
                </button>
              </div>
            </div>
          </div>

          <%!-- Sub-column 2: event subscriptions (all 8 supported events) --%>
          <% current_events = Enum.map(@selected_installation.subscriptions, & &1.event_type) %>
          <div class="xamt-bot-pane">
            <div class="font-bold text-sm text-[var(--xamt-accent)] mongol-text">
              {gettext("Event Subscriptions")}
            </div>

            <label
              :for={
                {ev_code, ev_label, req_scope} <- [
                  {"message.created", gettext("New channel message (message.created)"),
                   "channel.messages.read"},
                  {"bot.mentioned", gettext("Bot mentioned (@bot -> bot.mentioned)"),
                   "channel.messages.read"},
                  {"interaction.responded", gettext("Action button clicked (interaction.responded)"),
                   "channel.messages.read"},
                  {"reaction.added", gettext("Reaction / like added (reaction.added)"),
                   "channel.messages.read"},
                  {"message.updated", gettext("Message edited (message.updated)"),
                   "channel.messages.read"},
                  {"message.deleted", gettext("Message deleted (message.deleted)"),
                   "channel.messages.read"},
                  {"member.joined", gettext("Member joined (member.joined)"),
                   "server.members.events"},
                  {"member.left", gettext("Member left (member.left)"), "server.members.events"},
                  {"channel.created", gettext("Channel created (channel.created)"),
                   "channel.messages.read"}
                ]
              }
              class="xamt-bot-vcheck"
            >
              <input
                type="checkbox"
                name="subscribed_events[]"
                value={ev_code}
                checked={ev_code in current_events}
              />
              <span class="font-bold text-sm mongol-text">{ev_label}</span>
              <span class="text-xs text-[var(--xamt-muted)] mt-auto">
                ({gettext("requires")} {req_scope})
              </span>
            </label>
          </div>

          <%!-- Sub-column 3: granted scopes --%>
          <% granted = @selected_installation.granted_scopes %>
          <div class="xamt-bot-pane">
            <div class="font-bold text-sm text-[var(--xamt-accent)] mongol-text">
              {gettext("Granted Scopes")}
            </div>

            <label
              :for={
                {scope_code, scope_label} <- [
                  {"channel.messages.read",
                   gettext("Read messages & reactions (channel.messages.read)")},
                  {"channel.messages.send",
                   gettext("Send & reply to messages (channel.messages.send)")},
                  {"channel.messages.manage",
                   gettext("Manage or delete others' messages (channel.messages.manage)")},
                  {"server.members.events",
                   gettext("Receive member join/leave events (server.members.events)")},
                  {"server.members.read", gettext("Read server member list (server.members.read)")}
                ]
              }
              class="xamt-bot-vcheck"
            >
              <input
                type="checkbox"
                name="granted_scopes[]"
                value={scope_code}
                checked={scope_code in granted}
              />
              <span class="font-bold text-sm mongol-text">{scope_label}</span>
            </label>
          </div>

          <%!-- Sub-column 4: allowed channels and save --%>
          <% allowed_cids = @selected_installation.allowed_channel_ids || [] %>
          <div class="xamt-bot-pane">
            <div class="font-bold text-sm text-[var(--xamt-accent)] mongol-text">
              {gettext("Allowed Channels (none = all)")}
            </div>

            <label :for={ch <- @channels} class="xamt-bot-vcheck">
              <input
                type="checkbox"
                name="allowed_channel_ids[]"
                value={ch.id}
                checked={ch.id in allowed_cids}
              />
              <span class="font-bold text-sm mongol-text">#{ch.name}</span>
            </label>

            <button
              type="submit"
              class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold ml-2 mongol-text"
            >
              <.icon name="hero-check" class="w-5 h-5 mb-2" />
              <span>{gettext("Save Config")}</span>
            </button>
          </div>

          <%!-- Sub-column 5: Recent Webhook Deliveries & Manual Retry --%>
          <div class="xamt-bot-pane">
            <div class="flex flex-row items-center justify-between h-full">
              <span class="font-bold text-sm text-[var(--xamt-accent)] mongol-text">
                {gettext("Recent Deliveries")}
              </span>
              <button
                type="button"
                id="refresh-bot-deliveries"
                phx-click="refresh_bot_deliveries"
                class="xamt-icon-btn"
                title={gettext("Refresh")}
              >
                <.icon name="hero-arrow-path" class="w-4 h-4" />
              </button>
            </div>

            <div
              :if={@delivery_events == []}
              class="flex flex-row items-center justify-center h-full text-xs text-[var(--xamt-muted)] px-2 mongol-text"
            >
              {gettext("No webhook deliveries yet")}
            </div>

            <div
              :for={ev <- Enum.take(@delivery_events, 15)}
              id={"bot-delivery-#{ev.id}"}
              class="xamt-bot-strip justify-between gap-2"
            >
              <div class="flex flex-row items-center gap-2">
                <span class={[
                  "w-2 h-2 rounded-full shrink-0",
                  ev.status == "delivered" && "bg-emerald-500",
                  ev.status in ["pending", "processing"] && "bg-amber-500",
                  ev.status in ["failed", "dead"] && "bg-red-500"
                ]} />
                <span class="font-mono text-xs font-bold">{ev.event_type}</span>
                <span
                  :if={ev.execution_result["http_status"]}
                  class="font-mono text-[11px] text-[var(--xamt-muted)]"
                >
                  HTTP {ev.execution_result["http_status"]}
                </span>
              </div>

              <div class="flex flex-row items-center gap-2">
                <span class="font-mono text-[11px] text-[var(--xamt-muted)]">
                  {Calendar.strftime(ev.inserted_at, "%H:%M:%S")}
                </span>
                <button
                  :if={ev.status in ["failed", "dead"]}
                  type="button"
                  id={"retry-delivery-#{ev.id}"}
                  phx-click="retry_bot_delivery"
                  phx-value-id={ev.id}
                  class="xamt-btn py-2 px-1.5 text-xs font-bold text-amber-500 border-amber-500/40 mongol-text"
                >
                  <.icon name="hero-arrow-path" class="w-3.5 h-3.5 mb-1" />
                  <span>{gettext("Retry")}</span>
                </button>
              </div>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
