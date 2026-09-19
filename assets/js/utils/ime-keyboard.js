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

export function attachVirtualKeyboard(ime, {eager = false} = {}) {
  if (!ime || ime.keyboardMode !== "virtual") return () => {}

  ime.hideKeyboard()

  const target = ime.targetEl

  const claim = () => {
    if (owner && owner !== ime) owner.hideKeyboard()
    owner = ime
    ime.showKeyboard()
  }

  const release = () => {
    if (owner !== ime) return
    ime.hideKeyboard()
    owner = null
  }

  const onFocus = () => claim()
  const onTargetPointer = () => claim()

  // Tapping a key blurs the editor; keep the keyboard from dismissing.
  const onKeyPointer = (e) => {
    e.preventDefault()
  }

  const onDocPointer = (e) => {
    if (owner !== ime) return
    if (inNode(e, target)) return
    if (inNode(e, ime.keyboardEl)) return
    if (inNode(e, ime.candidatesEl)) return
    if (e.target?.closest?.("mgl-candidates")) return
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
      ime.hideKeyboard()
      owner = null
    }
  }
}

/** Stop the OS keyboard from covering the custom IME on a contenteditable. */
export function suppressSystemKeyboard(root) {
  if (!root) return
  const apply = (el) => {
    if (!(el instanceof HTMLElement)) return
    if (!el.isContentEditable && el.getAttribute?.("contenteditable") !== "true") return
    el.setAttribute("inputmode", "none")
    el.setAttribute("virtualkeyboardpolicy", "manual")
  }

  apply(root)
  root.querySelectorAll?.("[contenteditable]").forEach(apply)
}
