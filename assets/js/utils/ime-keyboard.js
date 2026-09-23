/**
 * One virtual keyboard on screen at a time.
 *
 * Each MglIME instance mounts its own <mgl-keyboard>. On mobile they all call
 * show() in the constructor, so search / form fields would stack a second
 * keyboard over the composer. This helper hides the keyboard until the field
 * is focused, and hides any other instance when claiming.
 */

let owner = null

function pathOf(event) {
  return typeof event.composedPath === "function" ? event.composedPath() : []
}

function inNode(event, node) {
  if (!node) return false
  const path = pathOf(event)
  if (path.includes(node)) return true
  const target = event.target
  return target === node || node.contains?.(target)
}

const GHOST_MOUSE_MS = 800
const CLAIM_GRACE_MS = 500
let lastTouchAt = 0

export function attachVirtualKeyboard(ime, {eager = false} = {}) {
  if (!ime || ime.keyboardMode !== "virtual") return () => {}

  ime.hideKeyboard()

  const target = ime.targetEl
  let claimedAt = 0

  const claim = () => {
    suppressSystemKeyboard(target)
    navigator.virtualKeyboard?.hide?.()
    if (owner && owner !== ime) owner.hideKeyboard()
    owner = ime
    claimedAt = performance.now()
    ime.showKeyboard()
  }

  const release = () => {
    if (owner !== ime) return
    dismissVirtualIme(ime)
    owner = null
  }

  const onFocus = () => claim()
  const onTargetPointer = () => claim()

  // Tapping a key blurs the editor; keep the keyboard from dismissing.
  const onKeyPointer = (e) => {
    e.preventDefault()
  }

  const onDocPointer = (e) => {
    if (e.pointerType === "touch" || e.pointerType === "pen") {
      lastTouchAt = performance.now()
    } else if (
      e.pointerType === "mouse" &&
      lastTouchAt > 0 &&
      performance.now() - lastTouchAt < GHOST_MOUSE_MS
    ) {
      return
    }
    if (owner !== ime) return
    if (e.target?.closest?.(".xamt-search-hit, #search-results")) {
      release()
      return
    }
    if (performance.now() - claimedAt < CLAIM_GRACE_MS) return
    if (e.target?.closest?.("#composer-peek")) return
    if (inNode(e, target)) return
    if (inNode(e, ime.keyboardEl)) return
    if (inNode(e, ime.candidatesEl)) return
    if (inNode(e, ime.emojiPickerEl)) return
    if (e.target?.closest?.("mgl-candidates, mgl-emoji-picker, .xamt-ime-emoji, #composer-emoji")) return
    release()
  }

  target?.addEventListener("focusin", onFocus)
  target?.addEventListener("pointerdown", onTargetPointer)
  ime.keyboardEl?.addEventListener("pointerdown", onKeyPointer)
  document.addEventListener("pointerdown", onDocPointer, true)

  const ae = document.activeElement
  if (eager || target === ae || target?.contains?.(ae)) claim()

  return () => {
    target?.removeEventListener("focusin", onFocus)
    target?.removeEventListener("pointerdown", onTargetPointer)
    ime.keyboardEl?.removeEventListener("pointerdown", onKeyPointer)
    document.removeEventListener("pointerdown", onDocPointer, true)
    if (owner === ime) {
      dismissVirtualIme(ime)
      owner = null
    }
  }
}

function isEditable(el) {
  if (!(el instanceof HTMLElement)) return false
  if (el.isContentEditable || el.getAttribute?.("contenteditable") === "true") return true
  return el.tagName === "INPUT" || el.tagName === "TEXTAREA"
}

/**
 * Stop the OS / WebView keyboard from covering mgl-web-ime.
 *
 * Native <input> / <textarea> still summon iOS/Android's keyboard on focus
 * unless inputmode is none. Do not set `readonly` — that hides the caret.
 * LiveView morphs strip JS-only attributes, so callers must re-apply this
 * after patches.
 */
export function suppressSystemKeyboard(root) {
  if (!root) return
  const apply = (el) => {
    if (!isEditable(el)) return
    el.setAttribute("inputmode", "none")
    el.setAttribute("virtualkeyboardpolicy", "manual")
    if (el.tagName === "INPUT" || el.tagName === "TEXTAREA") {
      el.removeAttribute("readonly")
    }
  }

  apply(root)
  root.querySelectorAll?.("[contenteditable], input, textarea").forEach(apply)
  navigator.virtualKeyboard?.hide?.()
}

/** Hide the virtual keyboard and candidate bar without leaving a stale list. */
export function dismissVirtualIme(ime) {
  if (!ime) return
  ime.core?.setState?.({
    keyboardVisible: false,
    candidateVisible: false,
    candidates: [],
    composition: "",
  })
  ime.hideCandidates?.()
  ime.hideKeyboard?.()
  if (ime.candidatesEl) ime.candidatesEl.visible = false
  ime.blur?.()
}

/** Dismiss whichever IME currently owns the on-screen keyboard. */
export function dismissOwnedIme() {
  if (owner) {
    dismissVirtualIme(owner)
    owner = null
  }
  document.querySelectorAll("mgl-candidates[visible]").forEach((el) => {
    el.visible = false
  })
}

/** Match the mobile chat breakpoint so a wide phone still gets the virtual IME. */
export function preferVirtualIme() {
  if (typeof window === "undefined") return false
  if (/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile/i.test(navigator.userAgent)) {
    return true
  }
  const touch = "ontouchstart" in window || (navigator.maxTouchPoints ?? 0) > 0
  return touch && window.matchMedia("(max-width: 960px)").matches
}
