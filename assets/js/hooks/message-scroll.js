/**
 * Keeps visual position stable when older messages are prepended into a
 * horizontal (vertical-lr) message list and scrollWidth grows on the left.
 */
export function attachMessageScrollLock(el) {
  if (!el) return () => {}

  let lastWidth = el.scrollWidth
  let touching = false
  let pendingDiff = 0

  const applyDiff = (diff) => {
    // Near the left edge ≈ reading older history; pin the viewport in place
    if (diff > 0 && el.scrollLeft < 100) {
      el.scrollLeft += diff
    }
  }

  const onTouchStart = () => {
    touching = true
  }

  const onTouchEnd = () => {
    touching = false
    if (pendingDiff) {
      applyDiff(pendingDiff)
      pendingDiff = 0
    }
    lastWidth = el.scrollWidth
  }

  const observer = new MutationObserver(() => {
    // Layout may settle one frame after the childList mutation
    requestAnimationFrame(() => {
      const currentWidth = el.scrollWidth
      const widthDiff = currentWidth - lastWidth
      lastWidth = currentWidth

      // Writing scrollLeft mid-gesture cancels iOS momentum / pan
      if (touching) {
        pendingDiff += widthDiff
        return
      }

      applyDiff(widthDiff)
    })
  })

  el.addEventListener("touchstart", onTouchStart, {passive: true})
  el.addEventListener("touchend", onTouchEnd, {passive: true})
  el.addEventListener("touchcancel", onTouchEnd, {passive: true})
  observer.observe(el, {childList: true})
  return () => {
    observer.disconnect()
    el.removeEventListener("touchstart", onTouchStart)
    el.removeEventListener("touchend", onTouchEnd)
    el.removeEventListener("touchcancel", onTouchEnd)
  }
}

/** Standalone LiveView hook when the list element is not already hooked. */
export const MessageScroll = {
  mounted() {
    this._detach = attachMessageScrollLock(this.el)
  },

  destroyed() {
    this._detach?.()
  },
}
