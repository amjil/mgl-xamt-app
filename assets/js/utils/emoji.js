/**
 * Keep color emoji facing the reader inside vertical-lr Mongolian columns.
 * Desktop Chromium rotates Extended_Pictographic glyphs under
 * `text-orientation: mixed`; wrap them in `.xamt-emoji` (horizontal-tb).
 */

const EMOJI_SEQ =
  /\p{Extended_Pictographic}(?:\uFE0F|\uFE0E)?(?:\u200D\p{Extended_Pictographic}(?:\uFE0F|\uFE0E)?)*/u

const ONLY_EMOJI = new RegExp(`^(?:${EMOJI_SEQ.source}|\\s)+$`, "u")
const FIND_EMOJI = new RegExp(EMOJI_SEQ.source, "gu")

const SKIP_WRAP = ".xamt-emoji, .xamt-mention, .xamt-upright, code, pre"

export function isEmojiText(text) {
  return typeof text === "string" && text.length > 0 && ONLY_EMOJI.test(text) && /\p{Extended_Pictographic}/u.test(text)
}

export function containsEmoji(text) {
  if (typeof text !== "string" || text.length === 0) return false
  FIND_EMOJI.lastIndex = 0
  return FIND_EMOJI.test(text)
}

export function emojiHtml(text) {
  return `<span class="xamt-emoji">${escapeHtml(text)}</span>`
}

/** Escape `text` and wrap color-emoji runs so vertical-lr columns stay upright. */
export function emojiRichText(text) {
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

export function insertUprightText(text) {
  if (isEmojiText(text)) {
    document.execCommand("insertHTML", false, emojiHtml(text))
    return
  }
  document.execCommand("insertText", false, text)
}

export function wrapEmojis(root) {
  if (!root) return
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  const nodes = []
  let node
  while ((node = walker.nextNode())) {
    if (!node.data || !FIND_EMOJI.test(node.data)) {
      FIND_EMOJI.lastIndex = 0
      continue
    }
    FIND_EMOJI.lastIndex = 0
    if (node.parentElement?.closest(SKIP_WRAP)) continue
    nodes.push(node)
  }

  for (const textNode of nodes) {
    const frag = document.createDocumentFragment()
    const value = textNode.data
    let last = 0
    FIND_EMOJI.lastIndex = 0
    let match
    while ((match = FIND_EMOJI.exec(value))) {
      if (match.index > last) {
        frag.appendChild(document.createTextNode(value.slice(last, match.index)))
      }
      const span = document.createElement("span")
      span.className = "xamt-emoji"
      span.textContent = match[0]
      frag.appendChild(span)
      last = match.index + match[0].length
    }
    if (last < value.length) {
      frag.appendChild(document.createTextNode(value.slice(last)))
    }
    textNode.replaceWith(frag)
  }
}

function escapeHtml(text) {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}
