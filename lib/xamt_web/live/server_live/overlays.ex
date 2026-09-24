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
end
