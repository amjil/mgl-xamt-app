/**
 * Message composer: richtext-editor.js + mgl-web-ime.js
 * Editor DOM is owned by this hook (phx-update="ignore").
 */
import { createMongolianEditor } from "../../vendor/mongolian-editor.js"
import { MglIME, createCustomAdapter, measureCaretRect } from "../../vendor/mgl-web-ime/mgl-web-ime.js"
import { imeProvider } from "../utils/ime.js"
import { attachVirtualKeyboard, suppressSystemKeyboard } from "../utils/ime-keyboard.js"
import { isImeUiTarget, syncDesktopImeClass } from "../utils/ime-emoji.js"
import {
  OfflineStore,
  flushPendingMessages,
  registerBackgroundSync,
  toast,
} from "../utils/offline-store.js"
import { attachMentionAutocomplete, hydrateMentions } from "./mention-autocomplete.js"
import { containsEmoji, deleteAtomicIsland, insertUprightText, islandJustDeleted, isEmojiText, wrapEmojis } from "../utils/emoji.js"

function editorRoot(editorEl) {
  return editorEl?.querySelector?.(".editor-content") || editorEl
}

const OUTSIDE_CLOSE_GRACE_MS = 500
const GHOST_MOUSE_MS = 800

function isGhostMouseEvent(event, lastTouchAt) {
  return (
    event.pointerType === "mouse" &&
    lastTouchAt > 0 &&
    performance.now() - lastTouchAt < GHOST_MOUSE_MS
  )
}

function isTransientBlurTarget(target) {
  return (
    !target ||
    target === document.body ||
    target === document.documentElement
  )
}

/** Collect image File objects from a paste/drop DataTransfer. */
function imageFilesFromDataTransfer(data) {
  if (!data) return []

  const fromFiles = Array.from(data.files || []).filter((f) =>
    f.type?.startsWith("image/")
  )
  if (fromFiles.length > 0) return fromFiles

  // Some browsers expose clipboard images only via items
  const fromItems = []
  for (const item of Array.from(data.items || [])) {
    if (item.kind === "file" && item.type?.startsWith("image/")) {
      const file = item.getAsFile()
      if (file) fromItems.push(file)
    }
  }
  return fromItems
}

function activeEditable(root) {
  const sel = window.getSelection()
  if (sel && sel.rangeCount > 0) {
    const node = sel.anchorNode
    const el = node?.nodeType === 1 ? node : node?.parentElement
    const block = el?.closest?.(".block-content")
    if (block && root.contains(block)) return block
  }
  return root.querySelector(".block-content") || root
}

function serializedLength(node) {
  if (!node) return 0
  if (node.nodeType === Node.TEXT_NODE) return node.data.length
  if (node.nodeName === "BR") return 1
  let length = 0
  for (const child of node.childNodes) length += serializedLength(child)
  return length
}

function serializeText(root) {
  if (!root) return ""
  if (root.nodeType === Node.TEXT_NODE) return root.data
  if (root.nodeName === "BR") return "\n"
  let text = ""
  for (const child of root.childNodes) text += serializeText(child)
  return text
}

function caretIndex(root, container, offset) {
  const range = document.createRange()
  try {
    range.setStart(root, 0)
    range.setEnd(container, offset)
  } catch {
    return serializedLength(root)
  }
  return serializedLength(range.cloneContents())
}

function pointFromIndex(root, index) {
  let left = Math.max(0, index)

  function visit(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      if (left <= node.data.length) return {node, offset: left}
      left -= node.data.length
      return null
    }
    if (node.nodeName === "BR") {
      if (left <= 0) return beforeNode(node)
      left -= 1
      return null
    }
    if (node.nodeType === Node.ELEMENT_NODE) {
      for (const child of node.childNodes) {
        const hit = visit(child)
        if (hit) return hit
      }
    }
    return null
  }

  return visit(root) || endPoint(root)
}

function beforeNode(node) {
  const parent = node.parentNode
  return {node: parent, offset: Array.prototype.indexOf.call(parent.childNodes, node)}
}

function endPoint(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  let last = null
  while (walker.nextNode()) last = walker.currentNode
  if (last) return {node: last, offset: last.data.length}
  return {node: root, offset: root.childNodes.length}
}

function placeRange(el, start, end) {
  const from = pointFromIndex(el, start)
  const to = pointFromIndex(el, end)
  const range = document.createRange()
  range.setStart(from.node, from.offset)
  range.setEnd(to.node, to.offset)
  const sel = window.getSelection()
  sel.removeAllRanges()
  sel.addRange(range)
}

function buildEditorAdapter(getRoot, {insertBreak, deleteAtBoundary} = {}) {
  return createCustomAdapter({
    getElement: () => activeEditable(getRoot()),
    focus: () => activeEditable(getRoot())?.focus?.(),
    blur: () => activeEditable(getRoot())?.blur?.(),
    getText: () => serializeText(activeEditable(getRoot())),
    getSelection: () => {
      const el = activeEditable(getRoot())
      const sel = window.getSelection()
      if (!el || !sel || sel.rangeCount === 0) {
        const len = serializedLength(el)
        return { start: len, end: len }
      }
      const range = sel.getRangeAt(0)
      if (!el.contains(range.commonAncestorContainer) && el !== range.commonAncestorContainer) {
        const len = serializedLength(el)
        return { start: len, end: len }
      }
      const start = caretIndex(el, range.startContainer, range.startOffset)
      const end = range.collapsed ? start : caretIndex(el, range.endContainer, range.endOffset)
      return { start, end }
    },
    setSelection: ({ start, end }) => {
      const el = activeEditable(getRoot())
      if (!el) return
      placeRange(el, start, end ?? start)
    },
    insertText: (text) => {
      const el = activeEditable(getRoot())
      el?.focus?.()
      if (text === "\n" || text === "\r\n") {
        if (insertBreak?.()) return
        document.execCommand("insertLineBreak")
        return
      }
      insertUprightText(text)
    },
    deleteBackward: () => {
      activeEditable(getRoot())?.focus?.()
      if (deleteAtomicIsland("backward")) return
      if (deleteAtBoundary?.()) return
      document.execCommand("delete")
    },
    deleteForward: () => {
      activeEditable(getRoot())?.focus?.()
      if (deleteAtomicIsland("forward")) return
      document.execCommand("forwardDelete")
    },
    replaceSelection: (text) => {
      activeEditable(getRoot())?.focus?.()
      insertUprightText(text)
    },
    getCaretRect: () => {
      const el = activeEditable(getRoot())
      const sel = window.getSelection()
      const range = sel?.rangeCount ? sel.getRangeAt(0) : null
      const inside = range && el && (el === range.commonAncestorContainer || el.contains(range.commonAncestorContainer))
      if (!inside) return measureCaretRect(null, el)
      if (range.collapsed) return measureCaretRect(range, el)
      const caret = range.cloneRange()
      caret.collapse(true)
      return measureCaretRect(caret, el)
    },
  })
}

export const MessageComposer = {
  mounted() {
    this.wrap = this.el.closest(".xamt-composer-wrap") || this.el
    this._channelId = this.wrap?.dataset?.channelId
    this.host = this.el.querySelector(".xamt-composer__editor") || this.el
    this.editor = createMongolianEditor(this.host)
    this._root = () => editorRoot(this.host)
    const starter = this._root()?.innerText?.trim() || ""
    if (starter === "Type traditional Mongolian here...") {
      this.editor.setHtml(
        '<div class="block-wrapper" data-block-type="paragraph"><p class="block-content" contenteditable="true"></p></div>'
      )
    }

    this.adapter = buildEditorAdapter(this._root, {
      insertBreak: () => this.editor?.insertBreak?.() === true,
      deleteAtBoundary: () => this.editor?.deleteAtBoundary?.() === true,
    })
    this.ime = new MglIME({
      adapter: this.adapter,
      // Without a target, desktop IME handles every window keydown and the
      // adapter's insertText() focuses this editor — stealing caret from
      // search / other inputs that also have an IME instance.
      target: this.host,
      profile: "auto",
      keyboard: "auto",
      provider: imeProvider(),
      mount: document.body,
    })
    if (this.ime.keyboardMode === "virtual") {
      suppressSystemKeyboard(this.host)
      this._onEditableFocus = (e) => suppressSystemKeyboard(e.target)
      this.host.addEventListener("focusin", this._onEditableFocus)
    }
    this._openedAt = 0
    this._lastTouchAt = 0
    this._onHostPointer = () => {
      if (this.host.contains(document.activeElement)) return
      const sel = window.getSelection()
      if (sel && !sel.isCollapsed && this.host.contains(sel.anchorNode)) return
      this.editor.focus()
    }
    this.host.addEventListener("pointerdown", this._onHostPointer)
    this._onComposerFocus = () => this.setOpen(true)
    this._onComposerBlur = (e) => {
      if (this.el.contains(e.relatedTarget) || this.wrap?.contains(e.relatedTarget)) return
      // iOS/Android fire focusout with no relatedTarget (or body) while the
      // keyboard / IME / layout settle. Outside taps close via pointerdown.
      if (isTransientBlurTarget(e.relatedTarget)) return
      requestAnimationFrame(() => {
        if (this.withinOpenGrace()) return
        const active = document.activeElement
        if (this.wrap?.contains(active)) return
        if (isImeUiTarget(active) || active?.closest?.(".xamt-mention-picker")) return
        if (!this.hasDraft()) this.setOpen(false)
      })
    }
    this.host.addEventListener("focusin", this._onComposerFocus)
    this.host.addEventListener("focusout", this._onComposerBlur)
    this._onDocPointer = (e) => {
      if (e.pointerType === "touch" || e.pointerType === "pen") {
        this._lastTouchAt = performance.now()
      } else if (isGhostMouseEvent(e, this._lastTouchAt)) {
        return
      }
      if (!this.el.classList.contains("is-open")) return
      if (this.withinOpenGrace()) return
      if (this.wrap?.contains(e.target)) return
      if (e.target.closest?.("#composer-peek")) return
      if (isImeUiTarget(e.target) || e.target.closest?.(".xamt-mention-picker")) return
      if (this.hasDraft()) return
      this._root()?.querySelector("[contenteditable]")?.blur?.()
      this.setOpen(false)
    }
    document.addEventListener("pointerdown", this._onDocPointer, true)
    this._detachKeyboard = attachVirtualKeyboard(this.ime)
    this._syncComposerEmojiExpanded = () => {
      const btn = document.getElementById("composer-emoji")
      if (!btn) return
      btn.setAttribute("aria-expanded", String(Boolean(this.ime?.emojiPickerEl?.open)))
    }
    this.ime?.emojiPickerEl?.addEventListener("mgl-emoji-open", this._syncComposerEmojiExpanded)
    this.ime?.emojiPickerEl?.addEventListener("mgl-emoji-close", this._syncComposerEmojiExpanded)
    this.syncEmojiButton()

    // Send lives in the toolbar, outside this hook's phx-update="ignore"
    // node. Reply/edit patches replace that button, and updated() does not
    // run (ignored subtree, no attr change) — so bind by delegation on
    // document, not on a specific node.
    this._onSend = (e) => {
      const btn = e.target.closest?.("[data-composer-send]")
      if (!btn) return
      const wrap = this.el.closest(".xamt-composer-wrap")
      if (!wrap?.contains(btn)) return
      this.wrap = wrap
      this.submit()
    }
    this._onPeek = (e) => {
      if (e.type === "pointerdown" && e.isPrimary === false) return
      if (e.pointerType === "mouse" && e.button != null && e.button !== 0) return
      const btn = e.target.closest?.("#composer-peek")
      if (!btn) return
      const wrap = this.el.closest(".xamt-composer-wrap")
      if (!wrap?.contains(btn)) return
      // Open on pointerdown so iOS treats focus as a user gesture, and swallow
      // the event so the compatibility mouse click cannot hit whatever is now
      // under the FAB after the composer expands.
      e.preventDefault()
      this.wrap = wrap
      this.setOpen(true)
      this.editor.focus()
    }
    this._onEmojiPointer = (e) => {
      const btn = e.target.closest?.("#composer-emoji")
      if (!btn) return
      if (!this.el.closest(".xamt-composer-wrap")?.contains(btn)) return
      e.preventDefault()
    }
    this._onEmojiClick = (e) => {
      const btn = e.target.closest?.("#composer-emoji")
      if (!btn) return
      const wrap = this.el.closest(".xamt-composer-wrap")
      if (!wrap?.contains(btn)) return
      e.preventDefault()
      this.wrap = wrap
      this.setOpen(true)
      this.editor.focus()
      this.ime?.toggleEmojiPicker(btn)
    }
    document.addEventListener("click", this._onSend)
    document.addEventListener("pointerdown", this._onPeek, {passive: false})
    document.addEventListener("click", this._onPeek)
    document.addEventListener("pointerdown", this._onEmojiPointer, {passive: false})
    document.addEventListener("click", this._onEmojiClick)

    this._flushing = false
    this._onOnline = () => this.flushOfflineQueue()
    window.addEventListener("online", this._onOnline)

    this._onSwMessage = (event) => {
      if (event.data?.type === "xamt:flush-offline") this.flushOfflineQueue()
    }
    navigator.serviceWorker?.addEventListener("message", this._onSwMessage)

    // Capture-phase paste: beat mongolian-editor's text-only paste handler.
    // Image files go through LiveView allow_upload(:media) via this.upload.
    this._onPaste = (e) => {
      const imageFiles = imageFilesFromDataTransfer(e.clipboardData)
      if (imageFiles.length === 0) return

      e.preventDefault()
      e.stopImmediatePropagation()
      this.upload("media", imageFiles)
    }
    this.host.addEventListener("paste", this._onPaste, true)

    this._onBeforeInput = (e) => {
      if (e.inputType === "deleteContentBackward") {
        if (islandJustDeleted() || deleteAtomicIsland("backward")) e.preventDefault()
        return
      }
      if (e.inputType === "deleteContentForward") {
        if (islandJustDeleted() || deleteAtomicIsland("forward")) e.preventDefault()
      }
    }
    this.host.addEventListener("beforeinput", this._onBeforeInput, true)

    // Throttle typing events: one typing_started until idle timeout
    this._typingTimer = null
    this._isTyping = false

    this.host.addEventListener("input", () => {
      this.ejectLeakedEmojiText()
      if (!this._canPush()) return

      if (!this._isTyping) {
        this.pushEvent("typing_started", {})
        this._isTyping = true
      }

      clearTimeout(this._typingTimer)
      this._typingTimer = setTimeout(() => {
        if (this._canPush()) this.pushEvent("typing_stopped", {})
        this._isTyping = false
      }, 2000)
    })

    this.handleEvent("composer:clear", () => this.clear())
    this.handleEvent("composer:focus", () => {
      this.setOpen(true)
      this.editor.focus()
    })
    this.handleEvent("composer:load", (payload) => this.populate(payload))
    this.handleEvent("populate_composer", (payload) => this.populate(payload))

    this._detachMentions = attachMentionAutocomplete(this)

    // Flush leftovers from a previous session; register Background Sync as well
    // so the Service Worker can HTTP-replay if this tab is gone when we reconnect.
    this.flushOfflineQueue()
    registerBackgroundSync()
  },

  updated() {
    const wrap = this.el.closest(".xamt-composer-wrap") || this.wrap
    const channelId = wrap?.dataset?.channelId
    if (this._channelId && channelId && this._channelId !== channelId) {
      // Server already untracked the previous channel; reset so the next
      // keystroke in the new channel emits typing_started.
      this._isTyping = false
      clearTimeout(this._typingTimer)
    }
    this._channelId = channelId
    this.wrap = wrap
    this.syncEmojiButton()
  },

  // LiveView WebSocket restored — retry queued pushEvents
  reconnected() {
    this.flushOfflineQueue()
  },

  destroyed() {
    clearTimeout(this._typingTimer)
    document.removeEventListener("click", this._onSend)
    document.removeEventListener("pointerdown", this._onPeek)
    document.removeEventListener("click", this._onPeek)
    document.removeEventListener("pointerdown", this._onEmojiPointer)
    document.removeEventListener("click", this._onEmojiClick)
    window.removeEventListener("online", this._onOnline)
    navigator.serviceWorker?.removeEventListener("message", this._onSwMessage)
    this.host?.removeEventListener("paste", this._onPaste, true)
    this.host?.removeEventListener("beforeinput", this._onBeforeInput, true)
    this.host?.removeEventListener("focusin", this._onEditableFocus)
    this.host?.removeEventListener("focusin", this._onComposerFocus)
    this.host?.removeEventListener("focusout", this._onComposerBlur)
    this.host?.removeEventListener("pointerdown", this._onHostPointer)
    document.removeEventListener("pointerdown", this._onDocPointer, true)
    this._detachMentions?.()
    this._detachKeyboard?.()
    this.ime?.emojiPickerEl?.removeEventListener("mgl-emoji-open", this._syncComposerEmojiExpanded)
    this.ime?.emojiPickerEl?.removeEventListener("mgl-emoji-close", this._syncComposerEmojiExpanded)
    if (this.ime && typeof this.ime.destroy === "function") this.ime.destroy()
    if (this.editor && typeof this.editor.destroy === "function") this.editor.destroy()
  },

  clear() {
    if (this.editor?.setHtml) {
      this.editor.setHtml(
        "<div class=\"block-wrapper\" data-block-type=\"paragraph\"><p class=\"block-content\" contenteditable=\"true\"><br></p></div>"
      )
    }
    this.syncIme()
    this.setOpen(false)
    this._root()?.querySelector("[contenteditable]")?.blur?.()
    // Stop typing indicator immediately after send/clear
    if (this._isTyping) {
      if (this._canPush()) this.pushEvent("typing_stopped", {})
      this._isTyping = false
      clearTimeout(this._typingTimer)
    }
  },

  populate({ html } = {}) {
    if (html != null) this.editor.setHtml(html)
    hydrateMentions(this._root())
    wrapEmojis(this._root())
    this.syncIme()
    this.setOpen(true)
    this.editor.focus()
  },

  setOpen(open) {
    const next = Boolean(open)
    if (next) this._openedAt = performance.now()
    this.el.classList.toggle("is-open", next)
    if (!next) this.ime?.hideEmojiPicker?.()
  },

  withinOpenGrace() {
    return performance.now() - this._openedAt < OUTSIDE_CLOSE_GRACE_MS
  },

  hasDraft() {
    const text = (this._root()?.innerText || "").replace(/[\s\u200B-\u200D\uFEFF]/g, "")
    return text.length > 0
  },

  ejectLeakedEmojiText() {
    const root = this._root()
    if (!root) return
    let needsWrap = false
    for (const span of root.querySelectorAll(".xamt-emoji")) {
      const value = span.textContent || ""
      if (value && !isEmojiText(value)) {
        needsWrap = true
        break
      }
    }
    if (!needsWrap) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
      let node
      while ((node = walker.nextNode())) {
        if (node.parentElement?.closest(".xamt-emoji, .xamt-mention, .xamt-upright, code, pre")) {
          continue
        }
        if (containsEmoji(node.data)) {
          needsWrap = true
          break
        }
      }
    }
    if (!needsWrap) return
    const sel = this.adapter?.getSelection?.()
    wrapEmojis(root)
    if (sel) this.adapter.setSelection(sel)
  },

  syncIme() {
    // mgl-web-ime keeps composition in ImeCore; reset it after we rewrite the DOM.
    this.ime?.core?.cancelComposition?.()
  },

  syncEmojiButton() {
    syncDesktopImeClass(this.ime)
  },

  _canPush() {
    if (navigator.onLine === false) return false
    const ls = window.liveSocket
    if (ls && typeof ls.isConnected === "function") return ls.isConnected()
    return true
  },

  async flushOfflineQueue() {
    // HTTP flush does not need the LiveView socket — only a network path.
    if (this._flushing || navigator.onLine === false) return

    this._flushing = true
    try {
      const sent = await flushPendingMessages()
      if (sent > 0) {
        toast(
          "success",
          sent === 1 ? "Synced 1 offline message" : `Synced ${sent} offline messages`
        )
      }
    } catch (_err) {
      registerBackgroundSync()
    } finally {
      this._flushing = false
    }
  },

  submit() {
    this.wrap = this.el.closest(".xamt-composer-wrap") || this.wrap
    const html = this.editor.getHtml()
    const json = this.editor.getJson()

    // Strip whitespace and zero-width chars so blank messages are rejected
    const text = (this._root()?.innerText || "").replace(/[\s\u200B-\u200D\uFEFF]/g, "")
    const hasUploads = this.wrap?.dataset?.hasUploads === "true"
    if (!text && (!json || json.length === 0) && !hasUploads) return

    const event =
      this.wrap.dataset.submitEvent ||
      (this.wrap.dataset.editingId ? "update_message" : null) ||
      this.el.dataset.submitEvent ||
      "send_message"
    const payload = {
      content_html: html,
      content_json: JSON.stringify({ type: "rich_text", blocks: json }),
      content_type: "rich_text",
      reply_to_id: this.wrap?.dataset?.replyToId || null,
    }

    // Intercept when the browser is offline or the LiveView socket is down.
    // The Service Worker cannot reuse this socket, so we queue for HTTP replay.
    if (!this._canPush()) {
      if (hasUploads) {
        toast("error", "Can't send uploads while offline")
        return
      }

      if (event !== "send_message") {
        toast("error", "Reconnect to save this edit")
        return
      }

      const channelId = this.wrap?.dataset?.channelId
      if (!channelId) {
        toast("error", "Can't queue this message — missing channel")
        return
      }

      OfflineStore.save({channel_id: channelId, event, payload})
        .then(() => registerBackgroundSync())
        .then(() => {
          toast("warning", "You're offline — message will send when you're back online")
          this.clear()
        })
        .catch(() => {
          toast("error", "Failed to save offline — please try again later")
        })
      return
    }

    this.ime?.hideEmojiPicker?.()
    this.pushEvent(event, payload)
    // Online clear is driven by server push_event("composer:clear")
  },
}
