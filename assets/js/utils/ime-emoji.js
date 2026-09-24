/**
 * Desktop emoji picker for mgl-web-ime.
 *
 * Mobile already has emoji on the virtual keyboard. Desktop uses
 * <mgl-emoji-picker>, which the host must open via toggleEmojiPicker().
 */

import { containsEmoji, emojiRichText } from "./emoji.js"

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
      "mgl-keyboard, mgl-candidates, mgl-emoji-picker, mgl-ime-toggle, .xamt-ime-emoji, #composer-emoji, .xamt-status-picker__emoji"
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
 * Insert a compact 😊 trigger in the label column of a vertical field,
 * plus a mirror that keeps color emoji upright inside native inputs.
 * LiveView morphs can drop the siblings; call again from updated().
 */
export function attachFieldEmojiTrigger(ime, input, {label = "Emoji"} = {}) {
  if (!desktopEmojiEnabled(ime) || !input) return () => {}
  if (input.id && SKIP_AUTO_IDS.has(input.id)) return () => {}

  const existing = fieldEmojiTrigger(input)
  const button = existing || createFieldButton(input, label)
  if (!existing) placeFieldButton(input, button)

  const unbind = bindEmojiTrigger(ime, button)
  const detachMirror = attachEmojiMirror(input)
  return () => {
    unbind()
    detachMirror()
    button.remove()
  }
}

export function fieldEmojiTrigger(input) {
  const host = emojiHost(input)
  return host?.querySelector(":scope > .xamt-ime-emoji") ?? nextEmojiButton(input)
}

export function refreshFieldEmojiMirror(input) {
  if (!input) return
  syncEmojiMirror(input, fieldEmojiMirror(input) || createMirrorEl(input))
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

function placeFieldButton(input, button) {
  const host = emojiHost(input)
  const label = host?.querySelector(":scope > .xamt-field__label")
  if (label) {
    label.insertAdjacentElement("afterend", button)
    return
  }
  input.insertAdjacentElement("afterend", button)
}

function emojiHost(input) {
  return input.closest("label") || input.parentElement
}

function nextEmojiButton(input) {
  const sibling = input.nextElementSibling
  if (sibling?.classList?.contains("xamt-ime-emoji")) return sibling
  return null
}

function fieldEmojiMirror(input) {
  const host = emojiHost(input)
  return host?.querySelector(":scope > .xamt-ime-mirror") ?? null
}

function createMirrorEl(input) {
  const mirror = document.createElement("div")
  mirror.className = `${input.className} xamt-ime-mirror`
  if (input.tagName === "TEXTAREA") mirror.classList.add("xamt-textarea")
  mirror.setAttribute("aria-hidden", "true")
  input.insertAdjacentElement("afterend", mirror)
  return mirror
}

function attachEmojiMirror(input) {
  const onInput = () => {
    syncEmojiMirror(input, fieldEmojiMirror(input) || createMirrorEl(input))
  }
  const onScroll = () => {
    const mirror = fieldEmojiMirror(input)
    if (!mirror) return
    mirror.scrollTop = input.scrollTop
    mirror.scrollLeft = input.scrollLeft
  }
  input.addEventListener("input", onInput)
  input.addEventListener("scroll", onScroll)
  onInput()

  return () => {
    input.removeEventListener("input", onInput)
    input.removeEventListener("scroll", onScroll)
    fieldEmojiMirror(input)?.remove()
  }
}

function syncEmojiMirror(input, mirror) {
  if (!input || !mirror) return
  const value = input.value ?? ""
  if (!containsEmoji(value)) {
    mirror.hidden = true
    mirror.replaceChildren()
    return
  }
  mirror.hidden = false
  const cs = getComputedStyle(input)
  mirror.style.blockSize = cs.blockSize
  mirror.style.inlineSize = cs.inlineSize
  mirror.style.padding = cs.padding
  mirror.style.font = cs.font
  mirror.style.letterSpacing = cs.letterSpacing
  mirror.style.lineHeight = cs.lineHeight
  mirror.innerHTML = emojiRichText(value)
  mirror.scrollTop = input.scrollTop
  mirror.scrollLeft = input.scrollLeft
}

function syncExpanded(ime, button) {
  button.setAttribute("aria-expanded", String(Boolean(ime.emojiPickerEl?.open)))
}
