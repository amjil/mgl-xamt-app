/**
 * Keep `--mn-vh` in sync with the visual viewport so a locked shell stays
 * above the system keyboard. `100dvh` alone is not enough on iOS.
 */

const MAX_TRACKED_SCALE = 1.01
const REVEAL_DELAY_MS = 50

function isEditable(el) {
  if (!el || el === document.body || el === document.documentElement) return false
  return el.isContentEditable || el.tagName === "INPUT" || el.tagName === "TEXTAREA"
}

let revealTimer = null

function revealActiveInput() {
  const active = document.activeElement
  if (!isEditable(active)) return
  clearTimeout(revealTimer)
  revealTimer = setTimeout(() => {
    active.scrollIntoView({behavior: "smooth", block: "nearest", inline: "nearest"})
  }, REVEAL_DELAY_MS)
}

let installed = false

export function initVisualViewport() {
  const vv = window.visualViewport
  if (!vv || installed) return
  installed = true

  const root = document.documentElement

  const update = () => {
    if (vv.scale > MAX_TRACKED_SCALE) {
      root.style.removeProperty("--mn-vh")
      return
    }

    root.style.setProperty("--mn-vh", `${vv.height}px`)

    if (window.scrollY !== 0 || window.scrollX !== 0) {
      window.scrollTo(0, 0)
    }

    revealActiveInput()
  }

  vv.addEventListener("resize", update)
  vv.addEventListener("scroll", update)
  update()
}
