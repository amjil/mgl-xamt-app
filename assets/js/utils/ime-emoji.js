/**
 * Desktop emoji picker for mgl-web-ime.
 *
 * Mobile already has emoji on the virtual keyboard. Desktop uses
 * <mgl-emoji-picker>, which the host must open via toggleEmojiPicker().
 */

const SKIP_AUTO_IDS = new Set(["channel-search-q"])

export function desktopEmojiEnabled(ime) {
  return Boolean(ime && ime.keyboardMode !== "virtual")
}

/** Persist across LiveView toolbar morphs (the hook node is phx-update=ignore). */
export function syncDesktopImeClass(ime) {
  document.documentElement.classList.toggle("xamt-desktop-ime", desktopEmojiEnabled(ime))
}

export function isImeUiTarget(target) {
  return Boolean(
    target?.closest?.(
      "mgl-keyboard, mgl-candidates, mgl-emoji-picker, mgl-ime-toggle, .xamt-ime-emoji, #composer-emoji"
    )
  )
}

export function bindEmojiTrigger(ime, button) {
  if (!desktopEmojiEnabled(ime) || !button) return () => {}

  button.hidden = false
  button.setAttribute("aria-haspopup", "dialog")
  syncExpanded(ime, button)

  const onPointerDown = (event) => {
    event.preventDefault()
  }

  const onClick = (event) => {
    event.preventDefault()
    event.stopPropagation()
    ime.toggleEmojiPicker(button)
    syncExpanded(ime, button)
  }

  const onPickerChange = () => syncExpanded(ime, button)

  button.addEventListener("pointerdown", onPointerDown)
  button.addEventListener("click", onClick)
  ime.emojiPickerEl?.addEventListener("mgl-emoji-open", onPickerChange)
  ime.emojiPickerEl?.addEventListener("mgl-emoji-close", onPickerChange)

  return () => {
    button.removeEventListener("pointerdown", onPointerDown)
    button.removeEventListener("click", onClick)
    ime.emojiPickerEl?.removeEventListener("mgl-emoji-open", onPickerChange)
    ime.emojiPickerEl?.removeEventListener("mgl-emoji-close", onPickerChange)
    ime.hideEmojiPicker?.()
    button.removeAttribute("aria-expanded")
    button.hidden = true
  }
}

/**
 * Insert a compact 😊 trigger after a plain <input> / <textarea>.
 * LiveView morphs can drop the sibling; call again from updated().
 */
export function attachFieldEmojiTrigger(ime, input, {label = "Emoji"} = {}) {
  if (!desktopEmojiEnabled(ime) || !input) return () => {}
  if (input.id && SKIP_AUTO_IDS.has(input.id)) return () => {}

  const existing = nextEmojiButton(input)
  const button = existing || createFieldButton(input, label)
  if (!existing) input.insertAdjacentElement("afterend", button)

  const unbind = bindEmojiTrigger(ime, button)
  return () => {
    unbind()
    button.remove()
  }
}

function createFieldButton(input, label) {
  const button = document.createElement("button")
  button.type = "button"
  button.className = "xamt-ime-emoji"
  button.title = label
  button.setAttribute("aria-label", label)
  if (input.id) button.dataset.for = input.id

  const glyph = document.createElement("span")
  glyph.className = "xamt-ime-emoji__glyph"
  glyph.setAttribute("aria-hidden", "true")
  glyph.textContent = "😊"
  button.appendChild(glyph)
  return button
}

function nextEmojiButton(input) {
  const sibling = input.nextElementSibling
  if (sibling?.classList?.contains("xamt-ime-emoji")) return sibling
  return null
}

function syncExpanded(ime, button) {
  button.setAttribute("aria-expanded", String(Boolean(ime.emojiPickerEl?.open)))
}
