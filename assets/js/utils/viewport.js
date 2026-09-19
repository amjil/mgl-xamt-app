/**
 * Keeps `--xamt-vh` in sync with the *visual* viewport so the composer stays
 * above the on-screen keyboard. Mobile keyboards overlay the layout viewport
 * without resizing it, which is why `100dvh` alone is not enough.
 *
 * `--xamt-ime-kb` tracks the custom Mongolian virtual keyboard so the two-column
 * chat shell can shrink instead of sitting behind the keys.
 */
const MAX_TRACKED_SCALE = 1.01

export function trackViewportHeight() {
  const vv = window.visualViewport
  if (!vv) return

  const root = document.documentElement

  const apply = () => {
    // Pinch-zoom also shrinks the visual viewport — leave the CSS default alone
    if (vv.scale > MAX_TRACKED_SCALE) {
      root.style.removeProperty("--xamt-vh")
      return
    }
    root.style.setProperty("--xamt-vh", `${Math.round(vv.height)}px`)
  }

  vv.addEventListener("resize", apply)
  vv.addEventListener("scroll", apply)
  apply()
}

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
