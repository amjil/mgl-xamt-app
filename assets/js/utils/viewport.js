/**
 * Keeps `--xamt-vh` in sync with the *visual* viewport so the composer, app
 * shell, and drawers stay above the on-screen keyboard. Mobile keyboards overlay
 * the layout viewport without resizing it, which is why `100dvh` alone is not
 * enough.
 *
 * `--xamt-ime-kb` tracks the custom Mongolian virtual keyboard so the two-column
 * chat shell can shrink instead of sitting behind the keys.
 */
const MAX_TRACKED_SCALE = 1.01
const REVEAL_DELAY_MS = 50

let revealTimer = null

function isEditable(el) {
  if (!el || el === document.body || el === document.documentElement) return false
  return el.isContentEditable || el.tagName === "INPUT" || el.tagName === "TEXTAREA"
}

function revealActiveInput() {
  const activeElement = document.activeElement
  if (!isEditable(activeElement)) return

  clearTimeout(revealTimer)
  revealTimer = setTimeout(() => {
    activeElement.scrollIntoView({behavior: "smooth", block: "nearest", inline: "nearest"})
  }, REVEAL_DELAY_MS)
}

/**
 * Real-time visualViewport listener: writes the keyboard-excluded height to
 * `--xamt-vh` so every `height: var(--xamt-vh)` container recomputes, then
 * scrolls the focused field into view after the browser finishes painting.
 */
export function initVisualViewport() {
  const vv = window.visualViewport
  if (!vv) return

  const root = document.documentElement

  const updateViewport = () => {
    // Pinch-zoom also shrinks the visual viewport — leave the CSS default alone
    if (vv.scale > MAX_TRACKED_SCALE) {
      root.style.removeProperty("--xamt-vh")
      return
    }

    // Real visible height, excluding space taken by the system keyboard
    const vh = vv.height
    root.style.setProperty("--xamt-vh", `${vh}px`)

    // iOS pans the layout viewport when the keyboard opens; snap it back so
    // the overflow:hidden shell is not pushed out of the visual viewport.
    if (window.scrollY !== 0 || window.scrollX !== 0) {
      window.scrollTo(0, 0)
    }

    // Keyboard open: keep the focused input/composer in the remaining viewport
    revealActiveInput()
  }

  // resize = keyboard show/hide; scroll = iOS panning the page behind the keys
  vv.addEventListener("resize", updateViewport)
  vv.addEventListener("scroll", updateViewport)
  updateViewport()
}

/** @deprecated Use {@link initVisualViewport} */
export const trackViewportHeight = initVisualViewport

export function trackImeKeyboard() {
  const root = document.documentElement
  let observer = null
  let watched = null

  const apply = (el) => {
    const height = el?.offsetHeight || 0
    root.style.setProperty("--xamt-ime-kb", `${height}px`)
    document.body.classList.toggle("mgl-ime-mobile-open", height > 0)
  }

  const watch = (el) => {
    observer?.disconnect()
    watched = el || null
    if (!el) {
      apply(null)
      return
    }
    observer = new ResizeObserver(() => apply(el))
    observer.observe(el)
    apply(el)
  }

  document.addEventListener("mgl-ime-keyboard-show", (event) => {
    watch(event.target)
  })

  document.addEventListener("mgl-ime-keyboard-hide", (event) => {
    const visible = document.querySelector("mgl-keyboard[visible]")
    if (visible && visible !== event.target) watch(visible)
    else if (watched === event.target || !visible) watch(null)
  })
}
