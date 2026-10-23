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
    <.drawer
      id="bot-manager-drawer"
      class="xamt-sheet--bot"
      show={@show}
      on_cancel={JS.push("close_bot_manager")}
    >
      <div class="xamt-sheet-form xamt-bot-manager" id="bot-manager-modal">
        <aside class="xamt-bot-manager__rail">
          <h2 id="bot-manager-title" class="xamt-section-title mongol-text">
            {gettext("Bot integrations and permissions")}
          </h2>

          <button
            type="button"
            id="bot-register-toggle"
            phx-click="toggle_bot_create_form"
            class="xamt-btn xamt-btn--primary mongol-text"
          >
            <span class="xamt-upright" aria-hidden="true">
              <.icon name="hero-plus-circle" class="size-5" />
            </span>
            {gettext("Register new bot")}
          </button>

          <div class="xamt-bot-manager__installations" role="list" aria-labelledby="bot-manager-title">
            <button
              :for={inst <- @installations}
              type="button"
              role="listitem"
              phx-click="select_bot_installation"
              phx-value-id={inst.id}
              class={[
                "xamt-bot-manager__inst-card",
                @selected_installation && @selected_installation.id == inst.id &&
                  "is-selected",
                (!@selected_installation || @selected_installation.id != inst.id) && "is-idle"
              ]}
            >
              <span
                class={[
                  "xamt-bot-manager__inst-dot",
                  inst.status == "enabled" && "is-enabled",
                  inst.status != "enabled" && "is-disabled"
                ]}
                aria-hidden="true"
              />
              <span class="xamt-bot-manager__inst-name mongol-text">
                {upright_text(inst.bot.name)}
              </span>
              <span class="xamt-bot-manager__inst-status mongol-text">
                {if inst.status == "enabled", do: gettext("Enabled"), else: gettext("Disabled")}
              </span>
            </button>
          </div>
        </aside>

        <div :if={@newly_issued_token} class="xamt-bot-manager__token-banner" role="alert">
          <div class="xamt-bot-manager__token-head">
            <span class="xamt-upright" aria-hidden="true">
              <.icon name="hero-key" class="size-5" />
            </span>
            <span class="mongol-text">{gettext("Copy the bot token now (shown once)")}</span>
          </div>
          <div class="xamt-bot-manager__tech xamt-bot-manager__token-value">
            <code>{@newly_issued_token}</code>
          </div>
          <button
            type="button"
            id="dismiss-bot-token"
            phx-click="dismiss_bot_token"
            class="xamt-btn xamt-btn--soft mongol-text"
          >
            {gettext("I saved it — dismiss")}
          </button>
        </div>

        <form
          :if={@show_create_form}
          id="bot-create-form"
          phx-submit="create_and_install_bot"
          class="xamt-form xamt-form--vertical xamt-bot-manager__create"
        >
          <h3 class="xamt-section-title mongol-text">{gettext("Create new bot")}</h3>

          <label class="xamt-field">
            <span class="xamt-field__label mongol-text">{gettext("Bot name")}</span>
            <input
              type="text"
              name="bot[name]"
              id="bot-create-name"
              required
              placeholder={gettext("e.g. Idiom collector")}
              class="xamt-input mongol-input"
              phx-hook="MongolianIME"
              autocomplete="off"
            />
          </label>

          <label class="xamt-field">
            <span class="xamt-field__label mongol-text">{gettext("Description")}</span>
            <input
              type="text"
              name="bot[description]"
              id="bot-create-description"
              placeholder={gettext("Collects popular idioms automatically…")}
              class="xamt-input mongol-input"
              phx-hook="MongolianIME"
              autocomplete="off"
            />
          </label>

          <div class="xamt-bot-manager__tech xamt-field">
            <span class="xamt-field__label">Webhook Callback URL (HTTPS)</span>
            <input
              type="url"
              name="bot[webhook_url]"
              id="bot-create-webhook"
              required
              placeholder="https://bot.example.com/xamt/events"
              class="xamt-input xamt-input--latin"
              autocomplete="off"
            />
          </div>

          <button type="submit" id="bot-create-submit" class="xamt-btn xamt-btn--primary mongol-text">
            {gettext("Create and install on this server")}
          </button>
        </form>

        <form
          :if={@selected_installation && !@show_create_form}
          id="bot-config-form"
          phx-submit="save_bot_installation_config"
          class="xamt-bot-manager__config"
        >
          <input type="hidden" name="installation_id" value={@selected_installation.id} />

          <div class="xamt-bot-manager__sections">
            <section class="xamt-bot-manager__section" aria-labelledby="bot-config-overview">
              <div class="xamt-bot-manager__section-head">
                <h3 id="bot-config-overview" class="xamt-bot-manager__section-title mongol-text">
                  {upright_text(@selected_installation.bot.name)}
                </h3>
                <p
                  :if={@selected_installation.bot.description}
                  class="xamt-bot-manager__desc mongol-text"
                >
                  {upright_text(@selected_installation.bot.description)}
                </p>

                <label class="xamt-field xamt-bot-manager__status">
                  <span class="xamt-field__label mongol-text">{gettext("Status")}</span>
                  <select name="status" id="bot-config-status" class="xamt-input mn-select-native">
                    <option value="enabled" selected={@selected_installation.status == "enabled"}>
                      {gettext("Enabled")}
                    </option>
                    <option value="disabled" selected={@selected_installation.status == "disabled"}>
                      {gettext("Disabled")}
                    </option>
                  </select>
                </label>
              </div>

              <div class="xamt-bot-manager__tech xamt-bot-manager__credentials">
                <p>
                  <strong>Webhook URL:</strong>
                  <span class="xamt-bot-manager__mono">{@selected_installation.bot.webhook_url}</span>
                </p>
                <p>
                  <strong>Signing Secret (HMAC):</strong>
                  <code class="xamt-bot-manager__mono">
                    {@selected_installation.bot.signing_secret}
                  </code>
                </p>
                <p class="xamt-bot-manager__token-row">
                  <span>
                    Token:
                    <code class="xamt-bot-manager__mono">
                      {if token = List.first(@selected_installation.tokens),
                        do: token.token_prefix <> "...",
                        else: gettext("None")}
                    </code>
                  </span>
                  <button
                    type="button"
                    id="bot-rotate-token"
                    phx-click="rotate_bot_token"
                    phx-value-id={@selected_installation.id}
                    data-confirm={
                      gettext("The current token will stop working immediately. Continue?")
                    }
                    class="xamt-link-hint mongol-text"
                  >
                    {gettext("Rotate token")}
                  </button>
                </p>
              </div>
            </section>

            <% current_events = Enum.map(@selected_installation.subscriptions, & &1.event_type) %>
            <section class="xamt-bot-manager__section" aria-labelledby="bot-config-events">
              <h4 id="bot-config-events" class="xamt-bot-manager__section-title mongol-text">
                {gettext("1. Event subscriptions (what to deliver)")}
              </h4>

              <div class="xamt-bot-manager__options">
                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="subscribed_events[]"
                    value="member.joined"
                    checked={"member.joined" in current_events}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Member joined (member.joined)")}
                  </span>
                  <span class="xamt-bot-manager__option-hint mongol-text">
                    [{gettext("requires server.members.events")}]
                  </span>
                </label>

                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="subscribed_events[]"
                    value="message.created"
                    checked={"message.created" in current_events}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("New channel message (message.created)")}
                  </span>
                  <span class="xamt-bot-manager__option-hint mongol-text">
                    [{gettext("requires channel.messages.read")}]
                  </span>
                </label>

                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="subscribed_events[]"
                    value="reaction.added"
                    checked={"reaction.added" in current_events}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Reaction added (reaction.added)")}
                  </span>
                  <span class="xamt-bot-manager__option-hint mongol-text">
                    [{gettext("requires channel.messages.read")}]
                  </span>
                </label>
              </div>
            </section>

            <% granted = @selected_installation.granted_scopes %>
            <section class="xamt-bot-manager__section" aria-labelledby="bot-config-scopes">
              <h4 id="bot-config-scopes" class="xamt-bot-manager__section-title mongol-text">
                {gettext("2. Granted scopes (what actions are allowed)")}
              </h4>

              <div class="xamt-bot-manager__options">
                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="granted_scopes[]"
                    value="server.members.events"
                    checked={"server.members.events" in granted}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Receive member events (server.members.events)")}
                  </span>
                </label>

                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="granted_scopes[]"
                    value="server.members.read"
                    checked={"server.members.read" in granted}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Read member list (server.members.read)")}
                  </span>
                </label>

                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="granted_scopes[]"
                    value="channel.messages.read"
                    checked={"channel.messages.read" in granted}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Read messages and reactions (channel.messages.read)")}
                  </span>
                </label>

                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="granted_scopes[]"
                    value="channel.messages.send"
                    checked={"channel.messages.send" in granted}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Send messages in allowed channels (channel.messages.send)")}
                  </span>
                </label>

                <label class="xamt-bot-manager__option">
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="granted_scopes[]"
                    value="channel.messages.manage"
                    checked={"channel.messages.manage" in granted}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text">
                    {gettext("Manage others' messages (channel.messages.manage)")}
                  </span>
                </label>
              </div>
            </section>

            <% allowed_cids = @selected_installation.allowed_channel_ids %>
            <section class="xamt-bot-manager__section" aria-labelledby="bot-config-channels">
              <h4 id="bot-config-channels" class="xamt-bot-manager__section-title mongol-text">
                {gettext("3. Allowed channels (empty means all channels)")}
              </h4>

              <div class="xamt-bot-manager__options xamt-bot-manager__channels">
                <label
                  :for={ch <- @channels}
                  class="xamt-bot-manager__option xamt-bot-manager__channel"
                >
                  <input
                    type="checkbox"
                    class="xamt-checkbox"
                    name="allowed_channel_ids[]"
                    value={ch.id}
                    checked={ch.id in allowed_cids}
                  />
                  <span class="xamt-bot-manager__option-text mongol-text"># {ch.name}</span>
                </label>
              </div>

              <button
                type="submit"
                id="bot-config-save"
                class="xamt-btn xamt-btn--primary mongol-text xamt-bot-manager__save"
              >
                {gettext("Save permissions and subscriptions")}
              </button>
            </section>
          </div>
        </form>
      </div>
    </.drawer>
    """
  end
end
