/**
 * Keeps `--xamt-vh` in sync with the *visual* viewport so the composer stays
 * above the on-screen keyboard. Mobile keyboards overlay the layout viewport
 * without resizing it, which is why `100dvh` alone is not enough.
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
