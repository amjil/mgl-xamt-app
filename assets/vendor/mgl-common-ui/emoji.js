/**
 * Desktop Chromium rotates color emoji under vertical-lr + text-orientation: mixed.
 * Wrap runs in `.mn-emoji` (horizontal-tb).
 */

const KEYCAP = "[0-9#*]\\uFE0F?\\u20E3"
const EMOJI = "\\p{Extended_Pictographic}(?:\\p{Emoji_Modifier}|\\uFE0F|\\uFE0E)*"
const ZWJ_SEQ = `${EMOJI}(?:\\u200D(?:${EMOJI}|${KEYCAP}))*`
const FLAG = "\\p{Regional_Indicator}{2}"
const EMOJI_SEQ_SRC = `(?:${FLAG}|${ZWJ_SEQ}|${KEYCAP})`

const ONLY_EMOJI = new RegExp(`^(?:${EMOJI_SEQ_SRC}|\\s)+$`, "u")
const FIND_EMOJI = new RegExp(EMOJI_SEQ_SRC, "gu")

export function escapeHtml(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

export function isEmojiText(text) {
  return (
    typeof text === "string" &&
    text.length > 0 &&
    ONLY_EMOJI.test(text) &&
    /\p{Extended_Pictographic}/u.test(text)
  )
}

export function containsEmoji(text) {
  if (typeof text !== "string" || text.length === 0) return false
  FIND_EMOJI.lastIndex = 0
  return FIND_EMOJI.test(text)
}

export function emojiHtml(text) {
  return `<span class="mn-emoji">${escapeHtml(text)}</span>`
}

/** Escape `text` and wrap color-emoji runs so vertical-lr columns stay upright. */
export function wrapEmoji(text) {
  if (!text) return ""
  const parts = []
  let last = 0
  FIND_EMOJI.lastIndex = 0
  let match
  while ((match = FIND_EMOJI.exec(text))) {
    if (match.index > last) parts.push(escapeHtml(text.slice(last, match.index)))
    parts.push(emojiHtml(match[0]))
    last = match.index + match[0].length
  }
  if (last < text.length) parts.push(escapeHtml(text.slice(last)))
  return parts.join("")
}
