/**
 * One virtual keyboard on screen at a time.
 *
 * Each MglIME instance mounts its own <mgl-keyboard>. On mobile they all call
 * show() in the constructor, so search / form fields would stack a second
 * keyboard over the composer. This helper hides the keyboard until the field
 * is focused, and hides any other instance when claiming.
 */

let owner = null

export function attachVirtualKeyboard(ime, {eager = false} = {}) {
  if (!ime || ime.keyboardMode !== "virtual") return () => {}

  ime.hideKeyboard()

  const target = ime.targetEl
  let hideTimer = null

  const claim = () => {
    clearTimeout(hideTimer)
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

  const onBlur = () => {
    clearTimeout(hideTimer)
    hideTimer = setTimeout(() => {
      if (owner !== ime) return
      const ae = document.activeElement
      if (target === ae || target?.contains?.(ae)) return
      if (ime.keyboardEl?.contains?.(ae)) return
      release()
    }, 250)
  }

  // Tapping a key blurs the editor; keep the keyboard from dismissing.
  const onKeyPointer = (e) => {
    e.preventDefault()
    clearTimeout(hideTimer)
  }

  target?.addEventListener("focusin", onFocus)
  target?.addEventListener("focusout", onBlur)
  ime.keyboardEl?.addEventListener("pointerdown", onKeyPointer)

  if (eager) claim()

  return () => {
    clearTimeout(hideTimer)
    target?.removeEventListener("focusin", onFocus)
    target?.removeEventListener("focusout", onBlur)
    ime.keyboardEl?.removeEventListener("pointerdown", onKeyPointer)
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
