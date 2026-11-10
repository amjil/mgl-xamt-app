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
      id="bot-manager-backdrop"
      class="fixed inset-0 z-50 bg-[var(--xamt-shade)]/60 backdrop-blur-sm flex items-center justify-center p-4"
      phx-window-keydown="close_bot_manager"
      phx-key="Escape"
    >
      <div class="fixed inset-0" phx-click="close_bot_manager" aria-hidden="true"></div>

      <div
        id="bot-manager-modal"
        class="xamt-bot-modal relative z-10"
        phx-hook="MongolianScroll"
        role="dialog"
        aria-modal="true"
        aria-labelledby="bot-manager-title"
      >
        <div class="xamt-bot-col">
          <div class="flex flex-row justify-between items-center pr-2">
            <div class="flex flex-row items-center gap-2">
              <.icon name="hero-cpu-chip" class="w-6 h-6 text-[var(--xamt-accent)] shrink-0" />
              <h2
                id="bot-manager-title"
                class="text-xl font-bold tracking-wider text-[var(--xamt-text)]"
              >
                {gettext("Bot 扩展与授权中心")}
              </h2>
            </div>

            <button
              type="button"
              id="bot-manager-close"
              phx-click="close_bot_manager"
              class="p-2 rounded-full hover:bg-[var(--xamt-bg-3)] text-[var(--xamt-muted)] hover:text-[var(--xamt-text)] transition-colors"
              title={gettext("关闭")}
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>

          <button
            type="button"
            id="bot-register-toggle"
            phx-click="toggle_bot_create_form"
            class={[
              "px-3 py-4 rounded-xl font-bold flex flex-row items-center justify-center gap-2 transition-all shrink-0 border",
              @show_create_form &&
                "bg-[var(--xamt-accent)] text-white border-[var(--xamt-accent)] shadow-md",
              !@show_create_form &&
                "bg-[var(--xamt-bg-2)] text-[var(--xamt-text)] border-[var(--xamt-line)] hover:border-[var(--xamt-accent)]"
            ]}
          >
            <.icon name="hero-plus-circle" class="w-5 h-5 shrink-0" />
            <span>{gettext("注册并安装新 Bot")}</span>
          </button>

          <div class="flex flex-col gap-2.5 overflow-x-auto py-1">
            <div :if={@installations == []} class="text-xs text-[var(--xamt-muted)] py-4 px-2">
              {gettext("当前社区尚未安装任何 Bot")}
            </div>

            <div
              :for={inst <- @installations}
              id={"bot-inst-#{inst.id}"}
              phx-click="select_bot_installation"
              phx-value-id={inst.id}
              class={[
                "xamt-bot-card",
                @selected_installation && @selected_installation.id == inst.id && !@show_create_form &&
                  "is-selected"
              ]}
            >
              <div class="flex flex-row items-center gap-2.5">
                <span class={[
                  "w-2.5 h-2.5 rounded-full shrink-0",
                  inst.status == "enabled" && "bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.6)]",
                  inst.status != "enabled" && "bg-zinc-400"
                ]} />
                <span class="font-bold text-base text-[var(--xamt-text)]">{inst.bot.name}</span>
              </div>

              <div class="flex flex-row items-center gap-2">
                <span class="text-[11px] px-1.5 py-2 rounded bg-[var(--xamt-bg)] text-[var(--xamt-muted)] border border-[var(--xamt-line)]">
                  {length(inst.subscriptions)} {gettext("事件")} / {length(inst.granted_scopes)} {gettext(
                    "权限"
                  )}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@newly_issued_token}
          class="xamt-bot-col bg-amber-500/10 border border-amber-500/40 rounded-xl p-4"
        >
          <div class="flex flex-row items-center gap-2 text-amber-500 font-bold">
            <.icon name="hero-key" class="w-5 h-5 shrink-0" />
            <span>{gettext("请立即复制 Bot API Token（关闭后不再显示明文）")}</span>
          </div>

          <div class="xamt-bot-tech-box my-auto space-y-3">
            <div class="text-xs font-semibold text-[var(--xamt-muted)]">Bearer Token:</div>
            <code class="block p-2.5 rounded-lg bg-[var(--xamt-bg)] border border-[var(--xamt-line)] text-xs font-mono text-amber-500 select-all break-all">
              {@newly_issued_token}
            </code>
            <button
              type="button"
              id="dismiss-bot-token"
              phx-click="dismiss_bot_token"
              class="w-full py-1.5 px-3 rounded-lg bg-[var(--xamt-bg-3)] hover:bg-[var(--xamt-accent)] hover:text-white text-xs font-bold transition-colors"
            >
              {gettext("我已复制保存")}
            </button>
          </div>
        </div>

        <form
          :if={@show_create_form}
          id="bot-create-form"
          phx-submit="create_and_install_bot"
          class="flex flex-col gap-6 h-full shrink-0"
        >
          <div class="xamt-bot-col">
            <div class="xamt-bot-col__header">
              <span class="font-bold text-sm text-[var(--xamt-accent)]">
                {gettext("填写 Bot 基础信息")}
              </span>
            </div>

            <div class="flex flex-col gap-4 px-2">
              <div class="flex flex-row items-center gap-2">
                <label class="text-xs font-bold text-[var(--xamt-muted)] shrink-0">
                  {gettext("Bot 名称")}
                </label>
                <input
                  type="text"
                  name="bot[name]"
                  id="bot-create-name"
                  required
                  placeholder={gettext("例如：成语收集助手")}
                  class="xamt-input py-3 px-2.5 h-64"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                />
              </div>

              <div class="flex flex-row items-center gap-2">
                <label class="text-xs font-bold text-[var(--xamt-muted)] shrink-0">
                  {gettext("功能简介")}
                </label>
                <input
                  type="text"
                  name="bot[description]"
                  id="bot-create-description"
                  placeholder={gettext("监听点赞并自动收录精华语料...")}
                  class="xamt-input py-3 px-2.5 h-64"
                  phx-hook="MongolianIME"
                  autocomplete="off"
                />
              </div>
            </div>

            <div class="xamt-bot-tech-box my-auto space-y-3">
              <div>
                <label class="block text-xs font-bold text-[var(--xamt-text)] mb-1">
                  Webhook Callback URL
                </label>
                <input
                  type="url"
                  name="bot[webhook_url]"
                  id="bot-create-webhook"
                  required
                  placeholder="https://your-bot.example.com/webhook"
                  class="xamt-input w-full px-3 py-2 text-xs font-mono"
                  autocomplete="off"
                />
                <p class="text-[11px] text-[var(--xamt-muted)] mt-1">
                  {gettext("Xamt 将以 HMAC-SHA256 签名向该地址推送订阅事件")}
                </p>
              </div>
            </div>

            <button
              type="submit"
              id="bot-create-submit"
              class="xamt-btn--primary px-3.5 py-6 rounded-xl font-bold flex flex-row items-center justify-center gap-2 self-end"
            >
              <.icon name="hero-check-badge" class="w-5 h-5" />
              <span>{gettext("立即创建并生成 Token")}</span>
            </button>
          </div>
        </form>

        <form
          :if={@selected_installation && !@show_create_form}
          id="bot-config-form"
          phx-submit="save_bot_installation_config"
          class="flex flex-col gap-6 h-full shrink-0"
        >
          <input type="hidden" name="installation_id" value={@selected_installation.id} />

          <div class="xamt-bot-col">
            <div class="xamt-bot-col__header">
              <span class="font-bold text-sm">{@selected_installation.bot.name}</span>
            </div>

            <div class="flex flex-row items-center gap-3 py-2">
              <label class="text-xs font-bold text-[var(--xamt-muted)]">{gettext("启用状态")}</label>
              <select
                name="status"
                id="bot-config-status"
                class="xamt-input py-2 px-1.5 text-sm font-bold"
              >
                <option value="enabled" selected={@selected_installation.status == "enabled"}>
                  {gettext("运行中 (Enabled)")}
                </option>
                <option value="disabled" selected={@selected_installation.status == "disabled"}>
                  {gettext("已暂停 (Disabled)")}
                </option>
              </select>
            </div>

            <div class="xamt-bot-tech-box my-auto space-y-2.5">
              <div>
                <span class="text-[11px] font-bold uppercase tracking-wider text-[var(--xamt-muted)]">
                  Webhook Endpoint
                </span>
                <div
                  class="text-xs font-mono truncate text-[var(--xamt-text)] mt-0.5"
                  title={@selected_installation.bot.webhook_url}
                >
                  {@selected_installation.bot.webhook_url}
                </div>
              </div>

              <div>
                <span class="text-[11px] font-bold uppercase tracking-wider text-[var(--xamt-muted)]">
                  Signing Secret (HMAC)
                </span>
                <code class="block text-[11px] font-mono bg-[var(--xamt-bg)] px-2 py-1 rounded border border-[var(--xamt-line)] select-all truncate mt-0.5">
                  {@selected_installation.bot.signing_secret}
                </code>
              </div>

              <div class="pt-2 border-t border-[var(--xamt-line)] flex items-center justify-between">
                <div class="text-xs">
                  <span class="text-[var(--xamt-muted)]">Token: </span>
                  <code class="font-mono font-semibold">
                    {if t = List.first(@selected_installation.tokens),
                      do: t.token_prefix <> "•••",
                      else: "None"}
                  </code>
                </div>
                <button
                  type="button"
                  id="bot-rotate-token"
                  phx-click="rotate_bot_token"
                  phx-value-id={@selected_installation.id}
                  data-confirm={gettext("重置后旧 Token 将立即失效，确定生成新 Token 吗？")}
                  class="text-xs px-2 py-1 rounded bg-amber-500/15 text-amber-500 hover:bg-amber-500/25 font-bold transition-colors"
                >
                  {gettext("重置密钥")}
                </button>
              </div>
            </div>
          </div>

          <% current_events = Enum.map(@selected_installation.subscriptions, & &1.event_type) %>
          <div class="xamt-bot-col">
            <div class="xamt-bot-col__header">
              <span class="font-bold text-sm">{gettext("1. 事件订阅 (Webhook 推送触发器)")}</span>
            </div>

            <div class="flex flex-col gap-2.5 py-1">
              <label
                :for={
                  {ev_code, ev_label, req_scope} <- [
                    {"message.created", gettext("新消息发布 (message.created)"), "channel.messages.read"},
                    {"message.updated", gettext("消息更新 (message.updated)"), "channel.messages.read"},
                    {"message.deleted", gettext("消息删除 (message.deleted)"), "channel.messages.read"},
                    {"reaction.added", gettext("消息被点赞/贴表情 (reaction.added)"),
                     "channel.messages.read"},
                    {"member.joined", gettext("新成员加入社区 (member.joined)"), "server.members.events"},
                    {"member.left", gettext("成员离开社区 (member.left)"), "server.members.events"},
                    {"channel.created", gettext("新频道创建 (channel.created)"), "server.channels.manage"},
                    {"bot.mentioned", gettext("Bot 被提及 (bot.mentioned)"), "channel.messages.read"}
                  ]
                }
                class="xamt-bot-check-pill"
              >
                <input
                  type="checkbox"
                  name="subscribed_events[]"
                  value={ev_code}
                  checked={ev_code in current_events}
                  class="rounded text-[var(--xamt-accent)]"
                />
                <span class="font-bold text-sm text-[var(--xamt-text)]">{ev_label}</span>
                <span class="text-[11px] text-[var(--xamt-muted)] mt-auto">
                  [{gettext("需")} {req_scope}]
                </span>
              </label>
            </div>
          </div>

          <% granted = @selected_installation.granted_scopes %>
          <div class="xamt-bot-col">
            <div class="xamt-bot-col__header">
              <span class="font-bold text-sm">{gettext("2. 授权范围 (API 与读取约束)")}</span>
            </div>

            <div class="flex flex-col gap-2.5 py-1">
              <label
                :for={
                  {scope_code, scope_label} <- [
                    {"channel.messages.read", gettext("读取消息与点赞反应 (channel.messages.read)")},
                    {"channel.messages.send", gettext("发送与回复频道消息 (channel.messages.send)")},
                    {"channel.messages.manage", gettext("管理或删除消息 (channel.messages.manage)")},
                    {"server.members.events", gettext("接收成员加入/离开事件 (server.members.events)")},
                    {"server.members.read", gettext("查询社区成员列表 (server.members.read)")},
                    {"server.channels.manage", gettext("管理频道相关能力 (server.channels.manage)")}
                  ]
                }
                class="xamt-bot-check-pill"
              >
                <input
                  type="checkbox"
                  name="granted_scopes[]"
                  value={scope_code}
                  checked={scope_code in granted}
                  class="rounded text-[var(--xamt-accent)]"
                />
                <span class="font-bold text-sm text-[var(--xamt-text)]">{scope_label}</span>
              </label>
            </div>
          </div>

          <% allowed_cids = @selected_installation.allowed_channel_ids || [] %>
          <div class="xamt-bot-col">
            <div class="xamt-bot-col__header">
              <span class="font-bold text-sm">{gettext("3. 允许作用的频道 (不选则默认全频道)")}</span>
            </div>

            <div class="flex flex-col gap-2 py-1 max-w-[14rem] overflow-x-auto">
              <label :for={ch <- @channels} class="xamt-bot-check-pill">
                <input
                  type="checkbox"
                  name="allowed_channel_ids[]"
                  value={ch.id}
                  checked={ch.id in allowed_cids}
                  class="rounded text-[var(--xamt-accent)]"
                />
                <span class="text-sm font-medium">#{ch.name}</span>
              </label>
            </div>

            <button
              type="submit"
              id="bot-config-save"
              class="xamt-btn--primary px-4 py-6 rounded-xl font-bold flex flex-row items-center justify-center gap-2 self-end ml-2 shadow-lg"
            >
              <.icon name="hero-check" class="w-5 h-5" />
              <span>{gettext("保存全部配置")}</span>
            </button>

            <button
              type="button"
              id="bot-uninstall"
              phx-click="uninstall_bot"
              phx-value-id={@selected_installation.id}
              data-confirm={gettext("Uninstall this bot and revoke its tokens?")}
              class="px-4 py-4 rounded-xl font-bold flex flex-row items-center justify-center gap-2 self-end ml-2 border border-red-500/40 text-red-500 hover:bg-red-500/10 transition-colors"
            >
              <.icon name="hero-trash" class="w-5 h-5" />
              <span>{gettext("卸载 Bot")}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
