/**
 * Keep color emoji facing the reader inside vertical-lr Mongolian columns.
 * Desktop Chromium rotates Extended_Pictographic glyphs under
 * `text-orientation: mixed`; wrap them in `.xamt-emoji` (horizontal-tb).
 */

const KEYCAP = "[0-9#*]\\uFE0F?\\u20E3"
const EMOJI =
  "\\p{Extended_Pictographic}(?:\\p{Emoji_Modifier}|\\uFE0F|\\uFE0E)*"
const ZWJ_SEQ = `${EMOJI}(?:\\u200D(?:${EMOJI}|${KEYCAP}))*`
const FLAG = "\\p{Regional_Indicator}{2}"
const EMOJI_SEQ_SRC = `(?:${FLAG}|${ZWJ_SEQ}|${KEYCAP})`

const ONLY_EMOJI = new RegExp(`^(?:${EMOJI_SEQ_SRC}|\\s)+$`, "u")
const FIND_EMOJI = new RegExp(EMOJI_SEQ_SRC, "gu")

const SKIP_WRAP = ".xamt-emoji, .xamt-mention, .xamt-upright, code, pre"
const ATOMIC_ISLAND = ".xamt-emoji, .xamt-mention"
const ZWSP_ONLY = /^[\u200b\u200c\u200d\ufeff]*$/

export function isEmojiText(text) {
  return typeof text === "string" && text.length > 0 && ONLY_EMOJI.test(text) && /\p{Extended_Pictographic}/u.test(text)
}

export function containsEmoji(text) {
  if (typeof text !== "string" || text.length === 0) return false
  FIND_EMOJI.lastIndex = 0
  return FIND_EMOJI.test(text)
}

export function emojiHtml(text) {
  return `<span class="xamt-emoji" contenteditable="false">${escapeHtml(text)}</span>`
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
  if (text === "\n" || text === "\r\n") {
    document.execCommand("insertLineBreak")
    return
  }
  if (isEmojiText(text)) {
    // ZWSP after the island, same as mention chips: insertHTML otherwise
    // leaves the caret inside horizontal-tb and Mongolian types sideways.
    document.execCommand("insertHTML", false, `${emojiHtml(text)}\u200b`)
    leaveEmojiIsland()
    return
  }
  document.execCommand("insertText", false, text)
}

export function wrapEmojis(root) {
  if (!root) return
  for (const span of [...root.querySelectorAll(".xamt-emoji")]) {
    splitEmojiIsland(span)
  }

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
    textNode.replaceWith(fragmentFor(textNode.data))
  }

  for (const span of root.querySelectorAll(".xamt-emoji")) {
    span.setAttribute("contenteditable", "false")
    ensureZwspAfter(span)
  }
}

let islandDeletedAt = 0

/** Backspace/delete an emoji (or mention) island plus its ZWSP pad in one stroke. */
export function deleteAtomicIsland(direction = "backward") {
  const sel = window.getSelection()
  if (!sel || sel.rangeCount === 0) return false
  const range = sel.getRangeAt(0)
  if (!range.collapsed) return false
  const island = direction === "forward" ? islandAfter(range) : islandBefore(range)
  if (!island) return false
  removeIsland(island)
  islandDeletedAt = performance.now()
  return true
}

export function islandJustDeleted(withinMs = 40) {
  return performance.now() - islandDeletedAt < withinMs
}

function fragmentFor(value) {
  const frag = document.createDocumentFragment()
  let last = 0
  FIND_EMOJI.lastIndex = 0
  let match
  while ((match = FIND_EMOJI.exec(value))) {
    if (match.index > last) {
      frag.appendChild(document.createTextNode(value.slice(last, match.index)))
    }
    frag.appendChild(emojiSpan(match[0]))
    last = match.index + match[0].length
  }
  if (last < value.length) {
    frag.appendChild(document.createTextNode(value.slice(last)))
  }
  return frag
}

function emojiSpan(text) {
  const span = document.createElement("span")
  span.className = "xamt-emoji"
  span.setAttribute("contenteditable", "false")
  span.textContent = text
  return span
}

function splitEmojiIsland(span) {
  const value = span.textContent || ""
  if (isEmojiText(value)) return
  if (!containsEmoji(value)) {
    span.replaceWith(document.createTextNode(value))
    return
  }
  span.replaceWith(fragmentFor(value))
}

function leaveEmojiIsland() {
  const sel = window.getSelection()
  if (!sel || sel.rangeCount === 0) return
  const node = sel.anchorNode
  const el = node?.nodeType === 1 ? node : node?.parentElement
  let island = el?.closest?.(".xamt-emoji")
  if (!island && node) {
    const prev =
      node.nodeType === Node.TEXT_NODE
        ? node.previousSibling
        : el?.childNodes?.[sel.anchorOffset - 1]
    if (isIsland(prev)) island = prev
  }
  if (!island) return
  ensureZwspAfter(island)
  placeCaretInPad(island.nextSibling)
}

function ensureZwspAfter(span) {
  const next = span.nextSibling
  if (next?.nodeType === Node.TEXT_NODE && next.data.startsWith("\u200b")) return
  span.after(document.createTextNode("\u200b"))
}

function isIsland(node) {
  return node?.nodeType === 1 && Boolean(node.matches?.(ATOMIC_ISLAND))
}

function isZwspNode(node) {
  return node?.nodeType === Node.TEXT_NODE && ZWSP_ONLY.test(node.data)
}

function islandBefore(range) {
  const inside = islandContaining(range.startContainer)
  if (inside) return inside

  const node = range.startContainer
  const offset = range.startOffset
  if (node.nodeType === Node.TEXT_NODE) {
    const before = node.data.slice(0, offset)
    if (before.length > 0 && !ZWSP_ONLY.test(before)) return null
    return previousIslandFrom(node)
  }
  if (node.nodeType === Node.ELEMENT_NODE) {
    for (let i = offset - 1; i >= 0; i -= 1) {
      const child = node.childNodes[i]
      if (isZwspNode(child) || (child.nodeType === Node.TEXT_NODE && child.data === "")) continue
      return isIsland(child) ? child : null
    }
  }
  return previousIslandFrom(node)
}

function islandAfter(range) {
  const inside = islandContaining(range.startContainer)
  if (inside) return inside

  const node = range.startContainer
  const offset = range.startOffset
  if (node.nodeType === Node.TEXT_NODE) {
    const after = node.data.slice(offset)
    if (after.length > 0 && !ZWSP_ONLY.test(after)) return null
    return nextIslandFrom(node)
  }
  if (node.nodeType === Node.ELEMENT_NODE) {
    for (let i = offset; i < node.childNodes.length; i += 1) {
      const child = node.childNodes[i]
      if (isZwspNode(child) || (child.nodeType === Node.TEXT_NODE && child.data === "")) continue
      return isIsland(child) ? child : null
    }
  }
  return nextIslandFrom(node)
}

function islandContaining(node) {
  const el = node?.nodeType === 1 ? node : node?.parentElement
  return el?.closest?.(ATOMIC_ISLAND) ?? null
}

function previousIslandFrom(node) {
  let current = node.previousSibling
  while (current) {
    if (isZwspNode(current) || (current.nodeType === Node.TEXT_NODE && current.data === "")) {
      current = current.previousSibling
      continue
    }
    return isIsland(current) ? current : null
  }
  return null
}

function nextIslandFrom(node) {
  let current = node.nextSibling
  while (current) {
    if (isZwspNode(current) || (current.nodeType === Node.TEXT_NODE && current.data === "")) {
      current = current.nextSibling
      continue
    }
    return isIsland(current) ? current : null
  }
  return null
}

function removeIsland(island) {
  const parent = island.parentNode
  let after = island.nextSibling
  if (isZwspNode(after)) {
    const next = after.nextSibling
    after.remove()
    after = next
  } else if (after?.nodeType === Node.TEXT_NODE) {
    after.data = after.data.replace(/^[\u200b\u200c\u200d\ufeff]+/, "")
    if (after.data === "") {
      const next = after.nextSibling
      after.remove()
      after = next
    }
  }
  island.remove()
  placeCaretAfterRemoval(parent, after)
}

function placeCaretAfterRemoval(parent, nextSibling) {
  if (!parent) return
  if (nextSibling?.nodeType === Node.TEXT_NODE) {
    placeCaretInPad(nextSibling, 0)
    return
  }
  if (isIsland(nextSibling) || !nextSibling) {
    const prev = nextSibling ? nextSibling.previousSibling : parent.lastChild
    if (prev?.nodeType === Node.TEXT_NODE) {
      placeCaretInPad(prev, prev.data.length)
      return
    }
    const pad = document.createTextNode("\u200b")
    if (nextSibling) parent.insertBefore(pad, nextSibling)
    else parent.appendChild(pad)
    placeCaretInPad(pad)
    return
  }
  const range = document.createRange()
  range.setStartBefore(nextSibling)
  range.collapse(true)
  const sel = window.getSelection()
  sel.removeAllRanges()
  sel.addRange(range)
}

function placeCaretInPad(pad, offset = pad?.data?.length ?? 0) {
  if (!pad || pad.nodeType !== Node.TEXT_NODE) return
  const range = document.createRange()
  range.setStart(pad, Math.min(offset, pad.data.length))
  range.collapse(true)
  const sel = window.getSelection()
  sel.removeAllRanges()
  sel.addRange(range)
}

function escapeHtml(text) {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}
