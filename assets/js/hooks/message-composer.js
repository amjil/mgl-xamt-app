/**
 * Message composer: richtext-editor.js + mgl-web-ime.js
 * Editor DOM is owned by this hook (phx-update="ignore").
 */
import { createMongolianEditor } from "../../vendor/mongolian-editor.js"
import { MglIME, createCustomAdapter } from "../../vendor/mgl-web-ime/mgl-web-ime.js"
import { imeProvider } from "../utils/ime.js"
import { attachVirtualKeyboard, suppressSystemKeyboard } from "../utils/ime-keyboard.js"
import { OfflineStore, toast } from "../utils/offline-store.js"
import { highlightMessage as flashHighlight } from "../utils/highlight-message.js"
import { attachMessageScrollLock } from "./message-scroll.js"
import { attachReadReceipt } from "./read-receipt.js"
import { attachMentionAutocomplete, hydrateMentions } from "./mention-autocomplete.js"

function editorRoot(editorEl) {
  return editorEl?.querySelector?.(".editor-content") || editorEl
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

function buildEditorAdapter(getRoot) {
  return createCustomAdapter({
    getElement: () => activeEditable(getRoot()),
    focus: () => activeEditable(getRoot())?.focus?.(),
    blur: () => activeEditable(getRoot())?.blur?.(),
    getText: () => activeEditable(getRoot())?.innerText || "",
    getSelection: () => {
      const el = activeEditable(getRoot())
      const sel = window.getSelection()
      if (!el || !sel || sel.rangeCount === 0) {
        const len = (el?.innerText || "").length
        return { start: len, end: len }
      }
      const range = sel.getRangeAt(0)
      if (!el.contains(range.commonAncestorContainer)) {
        const len = (el.innerText || "").length
        return { start: len, end: len }
      }
      const pre = range.cloneRange()
      pre.selectNodeContents(el)
      pre.setEnd(range.startContainer, range.startOffset)
      const start = pre.toString().length
      return { start, end: start + range.toString().length }
    },
    setSelection: ({ start, end }) => {
      const el = activeEditable(getRoot())
      if (!el) return
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT)
      let pos = 0
      let startNode = null
      let startOff = 0
      let endNode = null
      let endOff = 0
      let node
      while ((node = walker.nextNode())) {
        const len = node.textContent.length
        if (!startNode && pos + len >= start) {
          startNode = node
          startOff = start - pos
        }
        if (!endNode && pos + len >= end) {
          endNode = node
          endOff = end - pos
          break
        }
        pos += len
      }
      if (!startNode) {
        el.focus()
        return
      }
      if (!endNode) {
        endNode = startNode
        endOff = startOff
      }
      const range = document.createRange()
      range.setStart(startNode, Math.min(startOff, startNode.textContent.length))
      range.setEnd(endNode, Math.min(endOff, endNode.textContent.length))
      const sel = window.getSelection()
      sel.removeAllRanges()
      sel.addRange(range)
    },
    insertText: (text) => {
      const el = activeEditable(getRoot())
      el?.focus?.()
      document.execCommand("insertText", false, text)
    },
    deleteBackward: () => {
      activeEditable(getRoot())?.focus?.()
      document.execCommand("delete")
    },
    deleteForward: () => {
      activeEditable(getRoot())?.focus?.()
      document.execCommand("forwardDelete")
    },
    replaceSelection: (text) => {
      activeEditable(getRoot())?.focus?.()
      document.execCommand("insertText", false, text)
    },
    getCaretRect: () => {
      const sel = window.getSelection()
      if (!sel || sel.rangeCount === 0) return null
      const rect = sel.getRangeAt(0).getBoundingClientRect()
      if (rect.width || rect.height) return rect
      return activeEditable(getRoot())?.getBoundingClientRect?.() || null
    },
  })
}

export const MessageComposer = {
  mounted() {
    this.wrap = this.el.closest(".xamt-composer-wrap") || this.el
    this.host = this.el.querySelector(".xamt-composer__editor") || this.el
    this.editor = createMongolianEditor(this.host)
    this._root = () => editorRoot(this.host)
    const starter = this._root()?.innerText?.trim() || ""
    if (starter === "Type traditional Mongolian here...") {
      this.editor.setHtml(
        '<div class="block-wrapper" data-block-type="paragraph"><p class="block-content" contenteditable="true"></p></div>'
      )
    }

    this.adapter = buildEditorAdapter(this._root)
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
    this._onHostPointer = () => {
      if (!this.host.contains(document.activeElement)) this.editor.focus()
    }
    this.host.addEventListener("pointerdown", this._onHostPointer)
    this._detachKeyboard = attachVirtualKeyboard(this.ime)

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
    document.addEventListener("click", this._onSend)

    this._flushing = false
    this._onOnline = () => this.flushOfflineQueue()
    window.addEventListener("online", this._onOnline)

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

    // Throttle typing events: one typing_started until idle timeout
    this._typingTimer = null
    this._isTyping = false

    this.host.addEventListener("input", () => {
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
    this.handleEvent("composer:focus", () => this.editor.focus())
    this.handleEvent("composer:load", ({ html }) => {
      if (html != null) this.editor.setHtml(html)
      hydrateMentions(this._root())
      this.editor.focus()
    })

    this._detachMentions = attachMentionAutocomplete(this)

    // Flush any messages left from a previous session once LiveView is up
    this.flushOfflineQueue()
  },

  updated() {
    this.wrap = this.el.closest(".xamt-composer-wrap") || this.wrap
  },

  // LiveView WebSocket restored — retry queued pushEvents
  reconnected() {
    this.flushOfflineQueue()
  },

  destroyed() {
    clearTimeout(this._typingTimer)
    document.removeEventListener("click", this._onSend)
    window.removeEventListener("online", this._onOnline)
    this.host?.removeEventListener("paste", this._onPaste, true)
    this.host?.removeEventListener("focusin", this._onEditableFocus)
    this.host?.removeEventListener("pointerdown", this._onHostPointer)
    this._detachMentions?.()
    this._detachKeyboard?.()
    if (this.ime && typeof this.ime.destroy === "function") this.ime.destroy()
  },

  clear() {
    if (this.editor?.setHtml) {
      this.editor.setHtml(
        "<div class=\"block-wrapper\" data-block-type=\"paragraph\"><p class=\"block-content\" contenteditable=\"true\"><br></p></div>"
      )
    }
    // Stop typing indicator immediately after send/clear
    if (this._isTyping) {
      if (this._canPush()) this.pushEvent("typing_stopped", {})
      this._isTyping = false
      clearTimeout(this._typingTimer)
    }
  },

  _canPush() {
    if (navigator.onLine === false) return false
    const ls = window.liveSocket
    if (ls && typeof ls.isConnected === "function") return ls.isConnected()
    return true
  },

  async flushOfflineQueue() {
    if (this._flushing || !this._canPush()) return

    this._flushing = true
    try {
      const pending = await OfflineStore.popAll()
      if (pending.length === 0) return

      for (const msg of pending) {
        this.pushEvent(msg.event, msg.payload)
      }

      toast("success", `Synced ${pending.length} offline message${pending.length === 1 ? "" : "s"}`)
    } catch (_err) {
      // IndexedDB unavailable — ignore; next reconnect will retry
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

    const event = this.wrap.dataset.submitEvent || this.el.dataset.submitEvent || "send_message"
    const payload = {
      content_html: html,
      content_json: JSON.stringify({ type: "rich_text", blocks: json }),
      content_type: "rich_text",
    }

    // Intercept when browser is offline or LiveView socket is down
    if (!this._canPush()) {
      OfflineStore.save({ event, payload })
        .then(() => {
          toast("warning", "You're offline — message saved to local drafts")
          this.clear()
        })
        .catch(() => {
          toast("error", "Failed to save offline — please try again later")
        })
      return
    }

    this.pushEvent(event, payload)
    // Online clear is driven by server push_event("composer:clear")
  },
}

// vertical-lr: newest message is the right-most column
const NEAR_LATEST_PX = 150

export const MessageList = {
  mounted() {
    this.jumpBtn = document.getElementById("jump-latest")
    this._onJump = () => this.scrollToLatest(true)
    this.jumpBtn?.addEventListener("click", this._onJump)

    this._onScroll = () => {
      if (this.nearLatest()) this.showJump(false)
    }
    this.el.addEventListener("scroll", this._onScroll, { passive: true })

    // Lock scrollLeft when older messages prepend and scrollWidth grows
    this._detachScrollLock = attachMessageScrollLock(this.el)
    this._receipt = attachReadReceipt(this)

    this.scrollToLatest(false)

    this.handleEvent("messages:scroll_bottom", () => {
      requestAnimationFrame(() => {
        if (this.nearLatest()) {
          this.scrollToLatest(true)
        } else {
          this.showJump(true)
        }
      })
    })

    this.handleEvent("messages:scroll_to", ({id}) => this.highlightMessage(id))
    this.highlightFromDataset()
  },

  updated() {
    this.highlightFromDataset()
    this._receipt?.updated()
  },

  destroyed() {
    this.jumpBtn?.removeEventListener("click", this._onJump)
    this.el.removeEventListener("scroll", this._onScroll)
    this._detachScrollLock?.()
    this._receipt?.destroyed()
  },

  nearLatest() {
    return this.el.scrollWidth - this.el.scrollLeft - this.el.clientWidth < NEAR_LATEST_PX
  },

  scrollToLatest(smooth) {
    this.el.scrollTo({ left: this.el.scrollWidth, behavior: smooth ? "smooth" : "auto" })
    this.showJump(false)
  },

  showJump(visible) {
    this.jumpBtn?.classList.toggle("is-visible", visible)
  },

  highlightFromDataset() {
    const id = this.el.dataset.highlight
    if (id) this.highlightMessage(id)
  },

  highlightMessage(id) {
    if (!id || this._highlighted === id) return
    const article = this.el.querySelector(`[data-message-id="${CSS.escape(id)}"]`)
    if (!article) return

    this._highlighted = id
    flashHighlight(article)
  },
}
