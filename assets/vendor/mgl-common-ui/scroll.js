/**
 * Wheel → horizontal scroll, keyboard page-turn, optional touch-drag.
 *
 * Default selector: `.mn-surface`
 * Nested vertical scroll: `[data-mn-scroll-y]` or any ancestor that overflows Y
 * Touch drag (link-dense galleries): `[data-mn-drag]`
 */

const DEFAULT_SELECTOR = ".mn-surface"
const VERTICAL_ALLOW = "[data-mn-scroll-y], .mn-latin, .mn-overlay"
const EDITABLE =
  "textarea, input, select, [contenteditable], .mn-input, .mn-textarea, .mgl-editor-scope"
const DRAG_THRESHOLD = 6

function canScrollAxis(el, axis) {
  if (!el) return false
  if (axis === "x") return el.scrollWidth > el.clientWidth + 1
  return el.scrollHeight > el.clientHeight + 1
}

function overflowsY(el) {
  if (!(el instanceof Element)) return false
  const style = getComputedStyle(el)
  const oy = style.overflowY
  if (oy === "hidden" || oy === "clip" || oy === "visible") return false
  return el.scrollHeight > el.clientHeight + 1
}

function hasNestedVerticalIntent(target, scrollContainer) {
  if (!(target instanceof Element)) return false
  if (target.closest(VERTICAL_ALLOW)) return true

  let node = target
  while (node && node !== scrollContainer) {
    if (overflowsY(node)) return true
    node = node.parentElement
  }
  return false
}

function isEditable(target) {
  return target instanceof Element && Boolean(target.closest(EDITABLE))
}

function closestSurface(target, selector) {
  return target instanceof Element ? target.closest(selector) : null
}

function wheelDelta(event) {
  if (event.shiftKey) return 0
  if (Math.abs(event.deltaX) >= Math.abs(event.deltaY)) return 0
  if (event.deltaY === 0) return 0
  return event.deltaMode === 1 ? event.deltaY * 24 : event.deltaY
}

function applyWheel(el, delta) {
  if (!el || canScrollAxis(el, "y")) return false
  const maxLeft = Math.max(0, el.scrollWidth - el.clientWidth)
  el.scrollLeft = Math.min(maxLeft, Math.max(0, el.scrollLeft + delta))
  return true
}

function axisDelta(event, axis) {
  const raw = axis === "x" ? event.deltaX : event.deltaY
  if (raw === 0) return 0
  return event.deltaMode === 1 ? raw * 24 : raw
}

function canConsumeScrollX(el, deltaX) {
  if (!(el instanceof Element) || !deltaX) return false
  const maxLeft = el.scrollWidth - el.clientWidth
  if (maxLeft <= 1) return false
  if (deltaX < 0 && el.scrollLeft > 0) return true
  if (deltaX > 0 && el.scrollLeft < maxLeft - 1) return true
  return false
}

function canConsumeScrollXFrom(target, deltaX) {
  let node = target instanceof Element ? target : null
  while (node && node !== document.documentElement) {
    const ox = getComputedStyle(node).overflowX
    if (ox === "auto" || ox === "scroll" || ox === "overlay") {
      if (canConsumeScrollX(node, deltaX)) return true
    }
    node = node.parentElement
  }
  return false
}

function nearestOverflowX(target) {
  let node = target instanceof Element ? target : null
  while (node && node !== document.documentElement) {
    const ox = getComputedStyle(node).overflowX
    if (
      (ox === "auto" || ox === "scroll" || ox === "overlay") &&
      node.scrollWidth > node.clientWidth + 1
    ) {
      return node
    }
    node = node.parentElement
  }
  return document.querySelector(DEFAULT_SELECTOR)
}

function installWheel(selector) {
  const coarse = window.matchMedia?.("(pointer: coarse)").matches
  if (coarse) return () => {}

  const onWheel = (event) => {
    if (event.ctrlKey) return
    const el = closestSurface(event.target, selector)
    if (!el) return
    if (hasNestedVerticalIntent(event.target, el)) return
    if (isEditable(event.target)) return

    const delta = wheelDelta(event)
    if (!delta) return
    if (applyWheel(el, delta)) event.preventDefault()
  }

  window.addEventListener("wheel", onWheel, {passive: false})
  return () => window.removeEventListener("wheel", onWheel)
}

/**
 * Stop leftover horizontal pans from becoming Back/Forward.
 * `overscroll-behavior: contain` still shows Chromium's history swipe;
 * `none` plus swallowing unconsumed deltaX is what actually blocks it.
 */
function installHistorySwipeGuard() {
  const EDGE = 16
  const STEAL = 12
  const IGNORE = "a, button, input, textarea, select, [contenteditable], summary, label"
  let session = null

  const onWheel = (event) => {
    if (event.ctrlKey || event.defaultPrevented) return
    const dx = axisDelta(event, "x")
    if (!dx) return
    if (!canConsumeScrollXFrom(event.target, dx)) event.preventDefault()
  }

  const onTouchStart = (event) => {
    if (event.touches.length !== 1) return
    const t = event.touches[0]
    if (t.clientX > EDGE && t.clientX < window.innerWidth - EDGE) return
    if (event.target instanceof Element && event.target.closest(IGNORE)) return
    const scroller = nearestOverflowX(event.target)
    if (!scroller) return
    session = {scroller, x: t.clientX, y: t.clientY, claimed: false}
    if (t.clientX <= STEAL || t.clientX >= window.innerWidth - STEAL) {
      event.preventDefault()
    }
  }

  const onTouchMove = (event) => {
    if (!session || event.touches.length !== 1) return
    const t = event.touches[0]
    const dx = t.clientX - session.x
    const dy = t.clientY - session.y

    if (!session.claimed) {
      if (Math.hypot(dx, dy) < DRAG_THRESHOLD) return
      if (Math.abs(dx) <= Math.abs(dy)) {
        session = null
        return
      }
      session.claimed = true
    }

    event.preventDefault()
    session.scroller.scrollLeft -= dx
    session.x = t.clientX
    session.y = t.clientY
  }

  const onTouchEnd = () => {
    session = null
  }

  window.addEventListener("wheel", onWheel, {passive: false, capture: true})
  window.addEventListener("touchstart", onTouchStart, {passive: false, capture: true})
  window.addEventListener("touchmove", onTouchMove, {passive: false, capture: true})
  window.addEventListener("touchend", onTouchEnd, true)
  window.addEventListener("touchcancel", onTouchEnd, true)

  return () => {
    window.removeEventListener("wheel", onWheel, true)
    window.removeEventListener("touchstart", onTouchStart, true)
    window.removeEventListener("touchmove", onTouchMove, true)
    window.removeEventListener("touchend", onTouchEnd, true)
    window.removeEventListener("touchcancel", onTouchEnd, true)
  }
}

function installKeyboard(selector) {
  const onKey = (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (isEditable(event.target)) return
    if (event.target instanceof Element && event.target.closest(VERTICAL_ALLOW)) return

    const el =
      closestSurface(event.target, selector) || document.querySelector(selector)
    if (!el) return

    const jump = el.clientWidth * 0.85
    const moves = {
      ArrowDown: 120,
      ArrowUp: -120,
      ArrowRight: 120,
      ArrowLeft: -120,
      PageDown: jump,
      PageUp: -jump,
      " ": jump,
    }

    if (event.key === "Home" || event.key === "End") {
      el.scrollTo({
        left: event.key === "Home" ? 0 : el.scrollWidth,
        behavior: "smooth",
      })
      event.preventDefault()
      return
    }

    const move = moves[event.key]
    if (move === undefined) return
    el.scrollBy({left: move, behavior: "smooth"})
    event.preventDefault()
  }

  document.addEventListener("keydown", onKey)
  return () => document.removeEventListener("keydown", onKey)
}

/**
 * Pointer / touch drag → scrollLeft. Use on link-dense vertical galleries
 * where native overflow-x would steal taps.
 */
export function bindDrag(el) {
  if (!el || el.dataset.mnDragBound === "1") return () => {}
  el.dataset.mnDragBound = "1"
  el.style.touchAction = "none"

  let pointerId = null
  let startX = 0
  let startY = 0
  let lastX = 0
  let lastY = 0
  let dragging = false
  let activated = false
  let suppressClick = false
  let touchMode = false

  const applyDelta = (dx, dy) => {
    const delta = Math.abs(dx) >= Math.abs(dy) ? dx : dy
    el.scrollLeft -= delta
  }

  const onPointerDown = (event) => {
    if (event.pointerType === "touch") return
    if (!event.isPrimary || event.button !== 0) return
    if (isEditable(event.target)) return
    touchMode = false
    pointerId = event.pointerId
    startX = lastX = event.clientX
    startY = lastY = event.clientY
    dragging = true
    activated = false
    suppressClick = false
  }

  const onPointerMove = (event) => {
    if (touchMode || !dragging || event.pointerId !== pointerId) return
    const dx = event.clientX - lastX
    const dy = event.clientY - lastY
    lastX = event.clientX
    lastY = event.clientY

    if (!activated) {
      if (Math.hypot(event.clientX - startX, event.clientY - startY) < DRAG_THRESHOLD) {
        return
      }
      activated = true
      suppressClick = true
      try {
        el.setPointerCapture(event.pointerId)
      } catch {
        /* ignore */
      }
    }

    event.preventDefault()
    applyDelta(dx, dy)
  }

  const onPointerUp = (event) => {
    if (touchMode || !dragging) return
    if (event?.pointerId != null && event.pointerId !== pointerId) return
    dragging = false
    activated = false
    pointerId = null
    try {
      if (event?.pointerId != null) el.releasePointerCapture(event.pointerId)
    } catch {
      /* ignore */
    }
  }

  const onTouchStart = (event) => {
    if (event.touches.length !== 1) return
    if (isEditable(event.target)) return
    const t = event.touches[0]
    touchMode = true
    startX = lastX = t.clientX
    startY = lastY = t.clientY
    dragging = true
    activated = false
    suppressClick = false
  }

  const onTouchMove = (event) => {
    if (!touchMode || !dragging || event.touches.length !== 1) return
    const t = event.touches[0]
    const dx = t.clientX - lastX
    const dy = t.clientY - lastY
    lastX = t.clientX
    lastY = t.clientY

    if (!activated) {
      if (Math.hypot(t.clientX - startX, t.clientY - startY) < DRAG_THRESHOLD) return
      activated = true
      suppressClick = true
    }

    event.preventDefault()
    applyDelta(dx, dy)
  }

  const onTouchEnd = () => {
    if (!touchMode) return
    dragging = false
    activated = false
    touchMode = false
  }

  const onClick = (event) => {
    if (!suppressClick) return
    suppressClick = false
    event.preventDefault()
    event.stopPropagation()
  }

  el.addEventListener("pointerdown", onPointerDown, {passive: true, capture: true})
  el.addEventListener("pointermove", onPointerMove, {passive: false, capture: true})
  el.addEventListener("pointerup", onPointerUp, true)
  el.addEventListener("pointercancel", onPointerUp, true)
  el.addEventListener("lostpointercapture", onPointerUp, true)
  el.addEventListener("touchstart", onTouchStart, {passive: true, capture: true})
  el.addEventListener("touchmove", onTouchMove, {passive: false, capture: true})
  el.addEventListener("touchend", onTouchEnd, true)
  el.addEventListener("touchcancel", onTouchEnd, true)
  el.addEventListener("click", onClick, true)

  return () => {
    el.removeEventListener("pointerdown", onPointerDown, true)
    el.removeEventListener("pointermove", onPointerMove, true)
    el.removeEventListener("pointerup", onPointerUp, true)
    el.removeEventListener("pointercancel", onPointerUp, true)
    el.removeEventListener("lostpointercapture", onPointerUp, true)
    el.removeEventListener("touchstart", onTouchStart, true)
    el.removeEventListener("touchmove", onTouchMove, true)
    el.removeEventListener("touchend", onTouchEnd, true)
    el.removeEventListener("touchcancel", onTouchEnd, true)
    el.removeEventListener("click", onClick, true)
    delete el.dataset.mnDragBound
    el.style.removeProperty("touch-action")
  }
}

function installDrag(selector) {
  const cleanups = new Map()

  const bindAll = (root = document) => {
    const nodes = root.querySelectorAll?.(`${selector}[data-mn-drag], [data-mn-drag]`) ?? []
    for (const el of nodes) {
      if (cleanups.has(el)) continue
      cleanups.set(el, bindDrag(el))
    }
  }

  bindAll()

  const observer = new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (!(node instanceof Element)) continue
        if (node.matches?.("[data-mn-drag]")) bindAll(node.parentElement || document)
        else bindAll(node)
      }
    }
  })
  observer.observe(document.documentElement, {childList: true, subtree: true})

  return () => {
    observer.disconnect()
    for (const stop of cleanups.values()) stop()
    cleanups.clear()
  }
}

/**
 * Bind wheel / keys / drag on one surface. Returns an unbind function.
 */
export function bindSurface(el, options = {}) {
  if (!el) return () => {}
  const stops = []
  const id = el.id ? `#${CSS.escape(el.id)}` : null
  const selector = id || DEFAULT_SELECTOR

  if (options.wheel !== false) {
    const onWheel = (event) => {
      if (hasNestedVerticalIntent(event.target, el) || isEditable(event.target)) return
      const delta = wheelDelta(event)
      if (!delta) return
      if (applyWheel(el, delta)) event.preventDefault()
    }
    el.addEventListener("wheel", onWheel, {passive: false})
    stops.push(() => el.removeEventListener("wheel", onWheel))
  }

  if (options.keyboard) {
    stops.push(installKeyboard(selector))
  }

  if (options.drag || el.hasAttribute("data-mn-drag")) {
    stops.push(bindDrag(el))
  }

  return () => {
    for (const stop of stops) stop()
  }
}

let installed = null

/**
 * Site-wide install. Safe to call more than once.
 *
 * @param {{ selector?: string, wheel?: boolean, keyboard?: boolean, drag?: boolean, historySwipe?: boolean }} [options]
 */
export function install(options = {}) {
  if (installed) return installed.stop
  const selector = options.selector || DEFAULT_SELECTOR
  const stops = []

  if (options.wheel !== false) stops.push(installWheel(selector))
  if (options.keyboard !== false) stops.push(installKeyboard(selector))
  if (options.drag !== false) stops.push(installDrag(selector))
  if (options.historySwipe !== false) stops.push(installHistorySwipeGuard())

  const stop = () => {
    for (const fn of stops) fn()
    installed = null
  }
  installed = {stop}
  return stop
}
