/**
 * Mongolian IME hook for plain <input> / <textarea>.
 * Uses ../mgl-web-ime.js (vendored).
 *
 * The IME already dispatches native `input` events, so LiveView `phx-change`
 * / submit sees the composed value. Keyboard and candidate UI mount on
 * `document.body` (z-index 10000) so they stay above form drawers.
 *
 * Do not recreate the instance on `updated()` — LiveView morphs the same
 * node in place, and remounting would reset composition / caret.
 */
import { MglIME } from "../../vendor/mgl-web-ime/mgl-web-ime.js"
import { imeProvider } from "../utils/ime.js"
import {
  attachFieldEmojiTrigger,
  fieldEmojiTrigger,
  refreshFieldEmojiMirror,
  syncDesktopImeClass,
} from "../utils/ime-emoji.js"
import {
  attachVirtualKeyboard,
  dismissOwnedIme,
  preferVirtualIme,
  suppressSystemKeyboard,
} from "../utils/ime-keyboard.js"

const instances = new WeakMap()

function composing(ime) {
  const state = ime?.getState?.()
  if (!state) return false
  return Boolean(state.composition) || (state.candidates?.length ?? 0) > 0
}

async function commitPending(ime) {
  if (!ime || !composing(ime)) return
  await ime.core?.commitCurrent?.({ addSpaceAfter: false })
}

/** Vertical-lr native fields drop a range that includes offset 0 on mouseup. */
function retainNativeSelection(el) {
  if (!el || !("selectionStart" in el)) return () => {}

  let pending = null
  let restoring = false

  const remember = () => {
    if (restoring || document.activeElement !== el) return
    const start = el.selectionStart
    const end = el.selectionEnd
    if (typeof start === "number" && typeof end === "number" && start !== end) {
      pending = {start, end}
    }
  }

  const restore = () => {
    if (!pending || restoring) return
    const {start, end} = pending
    pending = null
    if (el.selectionStart === el.selectionEnd && start !== end) {
      restoring = true
      try {
        el.setSelectionRange(start, end)
      } catch {
        /* ignore */
      }
      restoring = false
    }
  }

  const onLabelPointer = (event) => {
    if (event.target === el || el.contains(event.target)) return
    if (document.activeElement !== el) return
    if (el.selectionStart === el.selectionEnd) return
    event.preventDefault()
  }

  el.addEventListener("select", remember)
  document.addEventListener("selectionchange", remember)
  el.addEventListener("mouseup", restore)
  el.addEventListener("keyup", restore)

  const label = el.closest("label")
  label?.addEventListener("mousedown", onLabelPointer)
  label?.addEventListener("click", onLabelPointer)

  return () => {
    el.removeEventListener("select", remember)
    document.removeEventListener("selectionchange", remember)
    el.removeEventListener("mouseup", restore)
    el.removeEventListener("keyup", restore)
    label?.removeEventListener("mousedown", onLabelPointer)
    label?.removeEventListener("click", onLabelPointer)
  }
}

export const MongolianIME = {
  mounted() {
    if (instances.has(this.el)) return

    const virtual = preferVirtualIme()
    const ime = new MglIME({
      target: this.el,
      profile: virtual ? "mobile" : "auto",
      keyboard: virtual ? "virtual" : "auto",
      provider: imeProvider(),
      mount: document.body,
    })
    if (ime.keyboardMode === "virtual") suppressSystemKeyboard(this.el)
    this._detachKeyboard = attachVirtualKeyboard(ime)
    this._detachEmoji = attachFieldEmojiTrigger(ime, this.el)
    this._detachSelection = retainNativeSelection(this.el)
    syncDesktopImeClass(ime)
    instances.set(this.el, ime)

    this.handleEvent("search:focus", () => {
      if (this.el.id !== "channel-search-q") return
      if (ime.keyboardMode === "virtual") suppressSystemKeyboard(this.el)
      this.el.focus({preventScroll: true})
      if (ime.keyboardMode === "virtual") ime.showKeyboard()
    })

    this.handleEvent("search:dismiss", () => {
      if (this.el.id !== "channel-search-q") return
      dismissOwnedIme()
    })

    // Commit the candidate before HTML5 / LiveView read the field. pointerdown
    // runs before blur, so the input still has a caret for replaceBeforeCaret.
    this._form = this.el.form
    if (this._form) {
      this._onFormPointerDown = (e) => {
        const submitter = e.target?.closest?.("button, input[type=submit]")
        if (!submitter || submitter.type === "button" || submitter.type === "reset") return
        if (!this._form.contains(submitter)) return
        void commitPending(ime)
      }
      this._onFormSubmit = () => {
        void commitPending(ime)
      }
      this._form.addEventListener("pointerdown", this._onFormPointerDown, true)
      this._form.addEventListener("submit", this._onFormSubmit)
    }
  },

  updated() {
    // Morphs strip inputmode / readonly; put them back before iOS can
    // treat the field as a normal text input and raise the system keyboard.
    const ime = instances.get(this.el)
    if (ime?.keyboardMode === "virtual") suppressSystemKeyboard(this.el)
    if (ime?.keyboardMode !== "virtual") {
      if (!fieldEmojiTrigger(this.el)) {
        this._detachEmoji?.()
        this._detachEmoji = attachFieldEmojiTrigger(ime, this.el)
      } else {
        refreshFieldEmojiMirror(this.el)
      }
    }
  },

  destroyed() {
    this._form?.removeEventListener("pointerdown", this._onFormPointerDown, true)
    this._form?.removeEventListener("submit", this._onFormSubmit)
    this._detachEmoji?.()
    this._detachKeyboard?.()
    this._detachSelection?.()
    const ime = instances.get(this.el)
    if (ime && typeof ime.destroy === "function") ime.destroy()
    instances.delete(this.el)
  },
}
