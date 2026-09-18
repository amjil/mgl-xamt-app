/**
 * Maps vertical wheel delta to horizontal scroll for writing-mode: vertical-lr.
 * Respects native trackpad horizontal gestures and releases at scroll edges
 * so outer containers can continue scrolling.
 */
export function attachMongolianWheelScroll(el) {
  if (!el) return () => {}
  // Touch devices scroll these surfaces natively; intercepting fights the gesture
  if (window.matchMedia?.("(pointer: coarse)").matches) return () => {}

  const onWheel = (e) => {
    // Native trackpad horizontal swipe (or Shift+wheel → deltaX) — do not intervene
    if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return

    if (e.deltaY !== 0) {
      const atLeftLimit = el.scrollLeft <= 0 && e.deltaY < 0
      // Allow 1px float tolerance
      const atRightLimit =
        el.scrollLeft >= el.scrollWidth - el.clientWidth - 1 && e.deltaY > 0

      // Only preventDefault while this element can still scroll horizontally
      if (!atLeftLimit && !atRightLimit) {
        e.preventDefault()
        el.scrollLeft += e.deltaY
      }
    }
  }

  el.addEventListener("wheel", onWheel, {passive: false})
  return () => el.removeEventListener("wheel", onWheel)
}

export const MongolianScroll = {
  mounted() {
    this._detachWheel = attachMongolianWheelScroll(this.el)
  },

  destroyed() {
    this._detachWheel?.()
  },
}
