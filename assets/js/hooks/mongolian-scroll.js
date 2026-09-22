/**
 * Global wheel → horizontal scroll for writing-mode: vertical-lr.
 *
 * Event delegation covers all Mongolian scroll surfaces with one listener.
 * Nested elements that genuinely need vertical scroll (Latin dropdowns,
 * auth forms, etc.) are left to the browser.
 */

const SCROLL_CONTAINERS = [
  ".xamt-main-content",
  ".xamt-messages",
  ".xamt-rail__section",
  ".xamt-composer__editor",
  ".xamt-upload-preview",
  ".xamt-settings-panel",
  ".xamt-sheet__body",
].join(", ")

/** Surfaces that intentionally scroll on the Y axis (Latin / horizontal-tb). */
const VERTICAL_SCROLL_ALLOW = [
  ".xamt-auth-body",
  "[data-scroll-y]",
].join(", ")

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

/**
 * True when the wheel originated inside a nested vertical scroller that should
 * keep native deltaY behaviour (e.g. Latin multiline inputs / dropdowns).
 */
function hasNestedVerticalIntent(target, scrollContainer) {
  if (!(target instanceof Element)) return false
  if (target.closest(VERTICAL_SCROLL_ALLOW)) return true

  let node = target
  while (node && node !== scrollContainer) {
    if (overflowsY(node)) return true
    node = node.parentElement
  }
  return false
}

function onWheel(e) {
  // Shift+wheel is already remapped to horizontal by most browsers
  if (e.shiftKey) return

  // Prefer native trackpad horizontal gestures
  if (Math.abs(e.deltaX) >= Math.abs(e.deltaY)) return
  if (e.deltaY === 0) return

  const scrollContainer = e.target instanceof Element
    ? e.target.closest(SCROLL_CONTAINERS)
    : null
  if (!scrollContainer) return

  if (hasNestedVerticalIntent(e.target, scrollContainer)) return

  const canScrollX = canScrollAxis(scrollContainer, "x")
  const canScrollY = canScrollAxis(scrollContainer, "y")

  // Only hijack when the container is horizontal-primary
  if (!canScrollX || canScrollY) return

  const maxLeft = scrollContainer.scrollWidth - scrollContainer.clientWidth
  const atLeftLimit = scrollContainer.scrollLeft <= 0 && e.deltaY < 0
  const atRightLimit = scrollContainer.scrollLeft >= maxLeft - 1 && e.deltaY > 0

  // Release at edges so an outer Mongolian scroller can continue
  if (atLeftLimit || atRightLimit) return

  e.preventDefault()
  scrollContainer.scrollLeft += e.deltaY
}

let installed = false

/**
 * Register the site-wide wheel interceptor once.
 * Safe to call multiple times (idempotent).
 */
export function installGlobalMongolianWheelScroll() {
  if (installed) return
  // Touch devices scroll these surfaces natively; intercepting fights the gesture
  if (window.matchMedia?.("(pointer: coarse)").matches) return

  window.addEventListener("wheel", onWheel, {passive: false})
  installed = true
}

/**
 * @deprecated Prefer installGlobalMongolianWheelScroll(); kept for call sites
 * that still attach to a single element during migration.
 */
export function attachMongolianWheelScroll(el) {
  if (!el) return () => {}
  if (window.matchMedia?.("(pointer: coarse)").matches) return () => {}

  const handler = (e) => {
    if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return
    if (e.deltaY === 0) return

    const atLeftLimit = el.scrollLeft <= 0 && e.deltaY < 0
    const atRightLimit =
      el.scrollLeft >= el.scrollWidth - el.clientWidth - 1 && e.deltaY > 0

    if (!atLeftLimit && !atRightLimit) {
      e.preventDefault()
      el.scrollLeft += e.deltaY
    }
  }

  el.addEventListener("wheel", handler, {passive: false})
  return () => el.removeEventListener("wheel", handler)
}

/**
 * Legacy per-element hook. Wheel mapping is handled globally; this remains
 * registered so existing phx-hook="MongolianScroll" markup does not error.
 *
 * Channel-aware scroll-to-latest, unread edge badge, and mobile layout-settle
 * delay (rAF + timeout) live on the MessageList hook — driven by LiveView
 * `messages:scroll_bottom` and `data-channel-id`, not DOM MutationObserver.
 */
export const MongolianScroll = {
  mounted() {},
  destroyed() {},
}
