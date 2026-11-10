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
    <.drawer
      id="delete-reason-drawer"
      class="xamt-sheet--menu xamt-sheet--reason"
      show
      on_cancel={JS.push("cancel_delete_message")}
    >
      <div class="xamt-sheet-form">
        <h2 id="delete-reason-title" class="xamt-section-title mongol-text">
          {gettext("Delete message")}
        </h2>
        <p id="delete-reason-preview" class="xamt-delete-reason__preview mongol-text">
          {Messages.excerpt(@message, 80)}
        </p>
        <.form
          for={@form}
          id="delete-reason-form"
          phx-submit="confirm_delete_message"
          novalidate
          class="xamt-form xamt-form--vertical"
        >
          <.input field={@form[:id]} type="hidden" />
          <.input
            field={@form[:reason]}
            id="delete-reason"
            label={gettext("Reason (optional)")}
            phx-hook="MongolianIME"
            class="xamt-input mongol-input"
            autocomplete="off"
          />
          <div class="xamt-form__actions">
            <button
              type="submit"
              id="delete-reason-submit"
              class="xamt-btn xamt-btn--primary mongol-text"
            >
              {gettext("Delete")}
            </button>
            <button
              type="button"
              id="delete-reason-cancel"
              class="xamt-btn mongol-text"
              phx-click="cancel_delete_message"
            >
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </div>
    </.drawer>
    """
  end

  attr :current_user, :map, required: true

  def status_picker_overlay(assigns) do
    ~H"""
    <.drawer
      id="status-picker-drawer"
      class="xamt-sheet--menu xamt-sheet--status"
      show
      on_cancel={JS.push("close_status_picker")}
    >
      <div class="xamt-sheet-form xamt-status-picker">
        <h2 id="status-picker-title" class="xamt-section-title mongol-text">
          {gettext("Set custom status")}
        </h2>

        <div class="xamt-status-picker__presets" role="list">
          <button
            :for={{preset, idx} <- Enum.with_index(Xamt.Accounts.custom_status_presets())}
            type="button"
            id={"status-preset-#{idx}"}
            class="xamt-status-btn"
            phx-click="set_status"
            phx-value-emoji={preset["emoji"]}
            phx-value-text={preset["text"]}
          >
            <span class="xamt-status-btn__emoji xamt-upright" aria-hidden="true">
              {preset["emoji"]}
            </span>
            <span class="xamt-status-btn__text mongol-text">{preset["text"]}</span>
          </button>

          <button
            type="button"
            id="status-clear"
            class="xamt-status-btn xamt-status-btn--clear mongol-text"
            phx-click="clear_status"
          >
            {gettext("Clear status")}
          </button>
        </div>

        <form
          id="status-custom-form"
          phx-submit="save_custom_status"
          class="xamt-form xamt-form--vertical xamt-status-picker__form"
        >
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
          <input
            type="text"
            name="text"
            id="status-custom-text"
            value={@current_user.status_text}
            placeholder={gettext("Say something...")}
            maxlength="50"
            class="xamt-input mongol-input xamt-status-picker__text"
            phx-hook="MongolianIME"
            autocomplete="off"
          />
          <button
            type="submit"
            id="status-custom-save"
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            {gettext("Save")}
          </button>
        </form>
      </div>
    </.drawer>
    """
  end

  attr :server, :map, required: true
  attr :active_channel, :map, required: true
  attr :can_manage_channels?, :boolean, default: false

  def server_menu_overlay(assigns) do
    ~H"""
    <.drawer
      id="server-menu-drawer"
      class="xamt-sheet--menu"
      show
      on_cancel={JS.push("close_server_menu")}
    >
      <div class="xamt-sheet-form xamt-server-menu-sheet">
        <h2 id="server-menu-title" class="xamt-section-title mongol-text">
          {upright_text(@server.name)}
        </h2>
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
          class="xamt-server-menu-sheet__nav"
          aria-labelledby="server-menu-title"
        >
          <.link
            id="server-menu-new-channel"
            patch={~p"/servers/#{@server.slug}/#{@active_channel.slug}/new"}
            class="xamt-btn xamt-btn--soft mongol-text"
          >
            {gettext("Create channel")}
          </.link>
        </nav>
      </div>
    </.drawer>
    """
  end

  attr :live_action, :atom, required: true
  attr :server, :map, required: true
  attr :active_channel, :map, required: true
  attr :channel_form, :map, required: true
  attr :editing_channel, :map

  def server_overlay(assigns) do
    ~H"""
    <.drawer
      :if={@live_action in [:new_channel, :edit_channel]}
      id="server-drawer"
      show
      on_cancel={JS.patch(~p"/servers/#{@server.slug}/#{@active_channel.slug}")}
    >
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
    </.drawer>
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
    <div class="xamt-sheet-form">
      <h2 id={"#{@id}-title"} class="xamt-section-title mongol-text">{@title}</h2>
      <.form
        for={@form}
        id={@id}
        phx-submit="save_channel"
        novalidate
        class="xamt-form xamt-form--vertical"
      >
        <.input
          field={@form[:name]}
          id={@name_id}
          label={gettext("Channel name")}
          phx-hook="MongolianIME"
          class="xamt-input mongol-input"
          autocomplete="off"
        />
        <div class="xamt-form__actions">
          <button
            type="submit"
            id={"#{@id}-submit"}
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            {@submit_label}
          </button>
          <.link patch={@return_to} id={"#{@id}-cancel"} class="xamt-btn mongol-text">
            {gettext("Cancel")}
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  attr :poll, :map, required: true

  def poll_details_overlay(assigns) do
    ~H"""
    <.drawer
      id="poll-details-drawer"
      class="xamt-sheet--poll-details"
      show
      on_cancel={JS.push("close_poll_details")}
    >
      <div class="xamt-sheet-form xamt-poll-details">
        <h2 id="poll-details-title" class="xamt-section-title mongol-text">
          {gettext("Poll details")}
        </h2>
        <p class="xamt-poll-details__question mongol-text">{@poll.question}</p>
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

        <div id="poll-details-body" class="xamt-poll-details__body">
          <section
            :for={option <- @poll.options}
            id={"poll-details-option-#{option.id}"}
            class="xamt-poll-details__option"
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
    </.drawer>
    """
  end

  attr :messages, :list, required: true
  attr :can_manage_messages?, :boolean, default: false
  attr :current_scope, :map, required: true

  def pinned_drawer(assigns) do
    ~H"""
    <.drawer
      id="pinned-messages-drawer"
      class="xamt-sheet--pinned"
      show
      on_cancel={JS.push("close_pinned_drawer")}
    >
      <div class="xamt-sheet-form xamt-pinned-drawer">
        <h2 id="pinned-messages-title" class="xamt-pinned-drawer__title">
          <.icon name="hero-bookmark-square" class="size-5 text-[var(--xamt-accent)]" />
          <span class="xamt-section-title mongol-text">{gettext("Pinned messages")}</span>
        </h2>

        <p
          :if={@messages == []}
          id="pinned-messages-empty"
          class="xamt-pinned-drawer__empty mongol-text"
        >
          {gettext("No pinned messages yet")}
        </p>

        <div id="pinned-messages-list" class="xamt-pinned-drawer__list">
          <article
            :for={msg <- @messages}
            id={"pinned-msg-#{msg.id}"}
            class="xamt-pinned-card"
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
    </.drawer>
    """
  end

  attr :show, :boolean, default: false
  attr :installations, :list, default: []
  attr :selected_installation, :any, default: nil
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
        <div class="xamt-bot-section">
          <div class="flex flex-row items-center justify-between h-full">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-cpu-chip" class="w-5 h-5 text-[var(--xamt-accent)] shrink-0" />
              <h2 class="text-lg font-bold tracking-wider">
                {gettext("Bot Manager")}
              </h2>
            </div>

            <button
              type="button"
              phx-click="close_bot_manager"
              class="xamt-icon-btn mt-auto"
              title={gettext("Close")}
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>
        </div>

        <%!-- Column 2: installed bots and create entry --%>
        <div class="xamt-bot-section">
          <%!-- Create strip --%>
          <button
            type="button"
            phx-click="toggle_bot_create_form"
            class={[
              "xamt-bot-strip font-bold justify-center gap-2",
              @show_create_form && "is-active text-[var(--xamt-accent)]"
            ]}
          >
            <.icon name="hero-plus-circle" class="w-5 h-5 shrink-0" />
            <span>{gettext("Register & Install Bot")}</span>
          </button>

          <%!-- Installation list --%>
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
              <span class="font-bold text-base">{inst.bot.name}</span>
            </div>

            <span class="text-xs text-[var(--xamt-muted)]">
              {if inst.status == "enabled", do: gettext("Enabled"), else: gettext("Disabled")}
            </span>
          </div>

          <div
            :if={@installations == []}
            class="flex flex-row items-center justify-center h-full text-xs text-[var(--xamt-muted)] px-2"
          >
            {gettext("No bots installed yet")}
          </div>
        </div>

        <%!-- One-time token notice --%>
        <div
          :if={@newly_issued_token}
          class="xamt-bot-section bg-amber-500/10 border border-amber-500/40 rounded-xl px-3 py-3"
        >
          <div class="flex flex-row items-center gap-2 text-amber-500 font-bold">
            <.icon name="hero-key" class="w-5 h-5 shrink-0" />
            <span>{gettext("Copy this token now (shown once)")}</span>
          </div>

          <div class="xamt-bot-code-strip text-amber-500 border-amber-500/30">
            {@newly_issued_token}
          </div>

          <button
            type="button"
            phx-click="dismiss_bot_token"
            class="xamt-btn py-3 px-2 text-xs font-bold self-end"
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
          <div class="xamt-bot-section">
            <div class="font-bold text-sm text-[var(--xamt-accent)]">
              {gettext("New Bot Details")}
            </div>

            <label class="xamt-field h-full">
              <span class="xamt-label">{gettext("Bot Name")}</span>
              <input
                id="new-bot-name-input"
                type="text"
                name="bot[name]"
                required
                placeholder={gettext("Mongolian or general name...")}
                class="xamt-input h-full"
                phx-hook="MongolianIME"
              />
            </label>

            <label class="xamt-field h-full">
              <span class="xamt-label">{gettext("Description")}</span>
              <input
                id="new-bot-desc-input"
                type="text"
                name="bot[description]"
                placeholder={gettext("What this bot does...")}
                class="xamt-input h-full"
                phx-hook="MongolianIME"
              />
            </label>

            <label class="xamt-field h-full">
              <span class="xamt-label">{gettext("Webhook URL")}</span>
              <input
                type="url"
                name="bot[webhook_url]"
                required
                placeholder="https://example.com/webhook"
                class="xamt-input h-full font-mono text-xs"
              />
            </label>

            <button type="submit" class="xamt-btn xamt-btn--primary h-full px-3 font-bold">
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
          <div class="xamt-bot-section">
            <div class="flex flex-row items-center justify-between h-full">
              <span class="font-bold text-base text-[var(--xamt-accent)]">
                {@selected_installation.bot.name}
              </span>
              <span class="text-xs text-[var(--xamt-muted)]">
                {@selected_installation.bot.description}
              </span>
            </div>

            <label class="xamt-field h-full">
              <span class="xamt-label">{gettext("Status")}</span>
              <select
                id={"bot-status-select-#{@selected_installation.id}"}
                name="status"
                class="xamt-input"
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

            <div class="xamt-field h-full">
              <span class="xamt-label">Webhook URL</span>
              <div class="xamt-bot-code-strip text-[var(--xamt-muted)]">
                {@selected_installation.bot.webhook_url}
              </div>
            </div>

            <div class="xamt-field h-full">
              <span class="xamt-label">{gettext("Signing Secret")}</span>
              <div class="xamt-bot-code-strip">
                {@selected_installation.bot.signing_secret}
              </div>
            </div>

            <div class="xamt-field h-full justify-between">
              <span class="xamt-label">
                Token: {if t = List.first(@selected_installation.tokens),
                  do: t.token_prefix <> "...",
                  else: "-"}
              </span>
              <button
                type="button"
                phx-click="rotate_bot_token"
                phx-value-id={@selected_installation.id}
                data-confirm={gettext("The old token will stop working immediately. Continue?")}
                class="xamt-btn text-amber-500 border-amber-500/40 py-3 px-2 text-xs font-bold"
              >
                <.icon name="hero-arrow-path" class="w-4 h-4 mb-1" />
                <span>{gettext("Rotate Token")}</span>
              </button>
            </div>
          </div>

          <%!-- Sub-column 2: event subscriptions --%>
          <% current_events = Enum.map(@selected_installation.subscriptions, & &1.event_type) %>
          <div class="xamt-bot-section">
            <div class="font-bold text-sm text-[var(--xamt-accent)]">
              {gettext("Event Subscriptions")}
            </div>

            <label
              :for={
                {ev_code, ev_label, req_scope} <- [
                  {"message.created", gettext("New channel message (message.created)"),
                   "channel.messages.read"},
                  {"reaction.added", gettext("Reaction / like added (reaction.added)"),
                   "channel.messages.read"},
                  {"member.joined", gettext("Member joined (member.joined)"), "server.members.events"},
                  {"member.left", gettext("Member left (member.left)"), "server.members.events"},
                  {"channel.created", gettext("Channel created (channel.created)"),
                   "server.channels.manage"}
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
              <span class="font-bold text-sm">{ev_label}</span>
              <span class="text-xs text-[var(--xamt-muted)] mt-auto">
                ({gettext("requires")} {req_scope})
              </span>
            </label>
          </div>

          <%!-- Sub-column 3: granted scopes --%>
          <% granted = @selected_installation.granted_scopes %>
          <div class="xamt-bot-section">
            <div class="font-bold text-sm text-[var(--xamt-accent)]">
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
              <span class="font-bold text-sm">{scope_label}</span>
            </label>
          </div>

          <%!-- Sub-column 4: allowed channels and save --%>
          <% allowed_cids = @selected_installation.allowed_channel_ids || [] %>
          <div class="xamt-bot-section">
            <div class="font-bold text-sm text-[var(--xamt-accent)]">
              {gettext("Allowed Channels (none = all)")}
            </div>

            <label :for={ch <- @channels} class="xamt-bot-vcheck">
              <input
                type="checkbox"
                name="allowed_channel_ids[]"
                value={ch.id}
                checked={ch.id in allowed_cids}
              />
              <span class="font-bold text-sm">#{ch.name}</span>
            </label>

            <button type="submit" class="xamt-btn xamt-btn--primary h-full px-3.5 font-bold ml-2">
              <.icon name="hero-check" class="w-5 h-5 mb-2" />
              <span>{gettext("Save Config")}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
