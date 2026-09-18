/**
 * Message composer: richtext-editor.js + mgl-web-ime.js
 * Editor DOM is owned by this hook (phx-update="ignore").
 */
import { createMongolianEditor } from "../../vendor/mongolian-editor.js"
import { MglIME, createCustomAdapter } from "../../vendor/mgl-web-ime/mgl-web-ime.js"

function editorRoot(editorEl) {
  return editorEl?.querySelector?.(".editor-content") || editorEl
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
    this.host = this.el.querySelector(".xamt-composer__editor") || this.el
    this.editor = createMongolianEditor(this.host)
    this._root = () => editorRoot(this.host)

    this.ime = new MglIME({
      adapter: buildEditorAdapter(this._root),
      profile: "auto",
      keyboard: "auto",
      baseUrl: this.el.dataset.imeBaseUrl || "http://dev1:3003",
      mount: document.body,
    })

    this.sendBtn = this.el.querySelector("[data-composer-send]")
    this._onSend = () => this.submit()
    this.sendBtn?.addEventListener("click", this._onSend)

    this._typingTimer = null
    this.host.addEventListener("input", () => {
      this.pushEvent("typing_started", {})
      clearTimeout(this._typingTimer)
      this._typingTimer = setTimeout(() => this.pushEvent("typing_stopped", {}), 1200)
    })

    this.handleEvent("composer:clear", () => this.clear())
    this.handleEvent("composer:load", ({ html }) => {
      if (html != null) this.editor.setHtml(html)
      this.editor.focus()
    })
  },

  updated() {
    // Keep editor instance; only sync submit event name from dataset if needed.
  },

  destroyed() {
    clearTimeout(this._typingTimer)
    this.sendBtn?.removeEventListener("click", this._onSend)
    if (this.ime && typeof this.ime.destroy === "function") this.ime.destroy()
  },

  clear() {
    if (this.editor?.setHtml) this.editor.setHtml("<div class=\"block-wrapper\" data-block-type=\"paragraph\"><p class=\"block-content\" contenteditable=\"true\"><br></p></div>")
    this.pushEvent("typing_stopped", {})
  },

  submit() {
    const html = this.editor.getHtml()
    const json = this.editor.getJson()
    const text = (this._root()?.innerText || "").trim()
    if (!text && (!json || json.length === 0)) return

    const event = this.el.dataset.submitEvent || "send_message"
    this.pushEvent(event, {
      content_html: html,
      content_json: JSON.stringify({ type: "rich_text", blocks: json }),
      content_type: "rich_text",
    })
  },
}

export const MessageList = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight
    this.handleEvent("messages:scroll_bottom", () => {
      requestAnimationFrame(() => {
        this.el.scrollTop = this.el.scrollHeight
      })
    })
  },
}
