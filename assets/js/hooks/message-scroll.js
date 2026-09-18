/**
 * Keeps visual position stable when older messages are prepended into a
 * horizontal (vertical-lr) message list and scrollWidth grows on the left.
 */
export function attachMessageScrollLock(el) {
  if (!el) return () => {}

  let lastWidth = el.scrollWidth

  const observer = new MutationObserver(() => {
    // Layout may settle one frame after the childList mutation
    requestAnimationFrame(() => {
      const currentWidth = el.scrollWidth
      const widthDiff = currentWidth - lastWidth

      // Near the left edge ≈ reading older history; pin the viewport in place
      if (widthDiff > 0 && el.scrollLeft < 100) {
        el.scrollLeft += widthDiff
      }

      lastWidth = el.scrollWidth
    })
  })

  observer.observe(el, {childList: true})
  return () => observer.disconnect()
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
