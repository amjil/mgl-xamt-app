/**
 * @mention picker for MessageComposer.
 * Popup is mounted on document.body so it is not rotated by vertical-lr.
 */

const QUERY_RE = /(^|[^\w])@([a-zA-Z0-9_]{0,32})$/
const DEBOUNCE_MS = 150
const PICKER_ID = "mention-picker"

export function attachMentionAutocomplete(hook) {
  const state = {
    open: false,
    query: "",
    members: [],
    selected: 0,
    timer: null,
    req: 0,
    picker: null,
  }

  const onInput = () => scan(hook, state)
  const onKeyDown = (e) => handleKeyDown(e, hook, state)
  const onPointerDown = (e) => {
    if (!state.open) return
    if (state.picker?.contains(e.target)) return
    close(state)
  }

  hook.host.addEventListener("input", onInput)
  hook.host.addEventListener("keydown", onKeyDown, true)
  document.addEventListener("pointerdown", onPointerDown, true)

  const offCommit = hook.ime?.on?.("mgl-ime-commit", () => scan(hook, state))
  const offInput = hook.ime?.on?.("mgl-ime-input", () => scan(hook, state))

  return () => {
    clearTimeout(state.timer)
    close(state)
    hook.host.removeEventListener("input", onInput)
    hook.host.removeEventListener("keydown", onKeyDown, true)
    document.removeEventListener("pointerdown", onPointerDown, true)
    offCommit?.()
    offInput?.()
  }
}

export function hydrateMentions(root) {
  if (!root) return
  root.querySelectorAll("[data-mention-id]").forEach((el) => {
    el.setAttribute("contenteditable", "false")
    el.classList.add("xamt-mention", "mongol-text")
    el.classList.remove("xamt-upright")
    el.addEventListener("click", (e) => e.preventDefault())
    if (!el.nextSibling || el.nextSibling.nodeType !== Node.TEXT_NODE || !el.nextSibling.data?.startsWith("\u200b")) {
      el.after(document.createTextNode("\u200b"))
    }
  })
}

function imeBusy(hook) {
  const s = hook.ime?.getState?.() || {}
  return !!(s.composing || s.candidateVisible)
}

function handleKeyDown(e, hook, state) {
  if (e.isComposing || e.key === "Process") return

  if (state.open && ["ArrowDown", "ArrowUp", "Enter", "Tab", "Escape"].includes(e.key)) {
    e.preventDefault()
    e.stopPropagation()
    e.stopImmediatePropagation()
    if (e.key === "Escape") {
      close(state)
      return
    }
    if (e.key === "ArrowDown") {
      state.selected = (state.selected + 1) % Math.max(state.members.length, 1)
      renderPicker(hook, state)
      return
    }
    if (e.key === "ArrowUp") {
      const n = Math.max(state.members.length, 1)
      state.selected = (state.selected - 1 + n) % n
      renderPicker(hook, state)
      return
    }
    pickSelected(hook, state)
    return
  }

  if (e.key !== "@" || e.ctrlKey || e.metaKey || e.altKey) return
  if (imeBusy(hook)) return

  const mode = hook.ime?.getState?.()?.mode
  if (mode === "latin") return

  e.preventDefault()
  e.stopPropagation()
  hook.adapter?.insertText?.("@")
  queueMicrotask(() => scan(hook, state))
}

function scan(hook, state) {
  if (imeBusy(hook)) {
    close(state)
    return
  }

  const el = hook.adapter?.getElement?.()
  if (!el) {
    close(state)
    return
  }

  const before = textBeforeCaret(el)
  const match = before.match(QUERY_RE)
  if (!match) {
    close(state)
    return
  }

  const query = match[2]
  state.query = query
  state.open = true
  ensurePicker(hook, state)
  scheduleSearch(hook, state, query)
}

function scheduleSearch(hook, state, query) {
  clearTimeout(state.timer)
  const run = () => {
    if (!hook._canPush?.()) return
    const req = ++state.req
    hook.pushEvent("mention_search", { q: query }, (reply) => {
      if (req !== state.req || !state.open) return
      state.members = Array.isArray(reply?.members) ? reply.members : []
      state.selected = 0
      renderPicker(hook, state)
    })
  }

  if (query === "") run()
  else state.timer = setTimeout(run, DEBOUNCE_MS)
}

function pickSelected(hook, state) {
  const member = state.members[state.selected]
  if (!member) {
    close(state)
    return
  }
  insertChip(hook, state, member)
}

function insertChip(hook, state, member) {
  const el = hook.adapter?.getElement?.()
  if (!el || !hook.adapter) {
    close(state)
    return
  }

  const queryLen = 1 + (state.query || "").length
  const sel = hook.adapter.getSelection()
  const start = Math.max(0, (sel?.start || 0) - queryLen)
  hook.adapter.setSelection({ start, end: sel?.end || start })

  const id = escapeHtml(String(member.id || ""))
  const username = escapeHtml(String(member.username || ""))
  const html =
    `<span class="xamt-mention mongol-text" contenteditable="false" data-mention-id="${id}" data-mention-username="${username}">@${username}</span>\u200b`

  el.focus?.()
  document.execCommand("insertHTML", false, html)
  close(state)
}

function ensurePicker(hook, state) {
  if (state.picker) return state.picker
  const el = document.createElement("div")
  el.id = PICKER_ID
  el.className = "xamt-mention-picker mongol-text"
  el.setAttribute("role", "listbox")
  el.hidden = true
  el.addEventListener("mousedown", (e) => {
    const row = e.target.closest?.("[data-mention-pick]")
    if (!row) return
    e.preventDefault()
    e.stopPropagation()
    const index = Number(row.dataset.mentionPick)
    if (!Number.isFinite(index)) return
    state.selected = index
    pickSelected(hook, state)
  })
  document.body.appendChild(el)
  state.picker = el
  return el
}

function renderPicker(hook, state) {
  const el = ensurePicker(hook, state)
  if (!state.open || state.members.length === 0) {
    el.hidden = true
    el.innerHTML = ""
    return
  }

  el.hidden = false
  el.replaceChildren(
    ...state.members.map((member, i) => rowEl(member, i === state.selected, i))
  )
  requestAnimationFrame(() => positionPicker(hook, el))
}

function rowEl(member, selected, index) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = "xamt-mention-picker__row"
  btn.setAttribute("role", "option")
  btn.setAttribute("aria-selected", selected ? "true" : "false")
  btn.dataset.mentionPick = String(index)
  if (selected) btn.classList.add("is-selected")

  const avatar = document.createElement(member.avatar ? "img" : "div")
  avatar.className = "xamt-mention-picker__avatar xamt-avatar xamt-avatar--sm"
  if (member.avatar) {
    avatar.src = member.avatar
    avatar.alt = ""
  } else {
    avatar.textContent = initial(member.display_name || member.username || "?")
  }

  const name = document.createElement("span")
  name.className = "xamt-mention-picker__name mongol-text"
  name.textContent = member.display_name || member.username || ""

  const handle = document.createElement("span")
  handle.className = "xamt-mention-picker__handle mongol-text"
  handle.textContent = `@${member.username || ""}`

  btn.append(avatar, name, handle)
  return btn
}

function positionPicker(hook, el) {
  if (hook.ime?.keyboardMode === "virtual") {
    el.style.left = "8px"
    el.style.right = "8px"
    el.style.top = "auto"
    el.style.bottom = "calc(var(--xamt-ime-kb, 0px) + 8px)"
    el.style.width = "auto"
    return
  }

  const rect = hook.adapter?.getCaretRect?.()
  if (!rect) return
  positionNear(el, rect)
}

function positionNear(el, rect) {
  const gap = 8
  const vw = window.innerWidth
  const vh = window.innerHeight
  const pWidth = el.offsetWidth || 220
  const pHeight = el.offsetHeight || 160
  const isVertical = rect.width > rect.height || rect.height < 5
  let place = isVertical ? "right" : "bottom"
  if (place === "right" && rect.right + gap + pWidth > vw) {
    place = rect.left - gap - pWidth > 0 ? "left" : "bottom"
  } else if (place === "bottom" && rect.bottom + gap + pHeight > vh) {
    place = rect.top - gap - pHeight > 0 ? "top" : "right"
  }

  let left = 0
  let top = 0
  if (place === "right") {
    left = rect.right + gap
    top = rect.top
  } else if (place === "left") {
    left = rect.left - gap - pWidth
    top = rect.top
  } else if (place === "bottom") {
    left = rect.left
    top = rect.bottom + gap
  } else {
    left = rect.left
    top = rect.top - gap - pHeight
  }

  left = Math.max(8, Math.min(left, vw - pWidth - 8))
  top = Math.max(8, Math.min(top, vh - pHeight - 8))
  el.style.left = `${left}px`
  el.style.top = `${top}px`
  el.style.bottom = "auto"
  el.style.right = "auto"
}

function close(state) {
  state.open = false
  state.query = ""
  state.members = []
  state.selected = 0
  clearTimeout(state.timer)
  if (state.picker) {
    state.picker.hidden = true
    state.picker.innerHTML = ""
  }
}

function textBeforeCaret(el) {
  const sel = window.getSelection()
  if (!sel || sel.rangeCount === 0) return el.innerText || ""
  const range = sel.getRangeAt(0)
  if (!el.contains(range.commonAncestorContainer)) return el.innerText || ""
  const pre = range.cloneRange()
  pre.selectNodeContents(el)
  pre.setEnd(range.startContainer, range.startOffset)
  return pre.toString()
}

function escapeHtml(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function initial(name) {
  const trimmed = String(name || "").trim()
  return trimmed ? Array.from(trimmed)[0] : "?"
}
