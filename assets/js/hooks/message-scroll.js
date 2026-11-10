import {attachMongolianWheelScroll} from "./mongolian-scroll.js"

/**
 * @deprecated Prefer MessageList + InfiniteScroll compensation.
 * Kept so any leftover `phx-hook="MessageScroll"` markup still mounts.
 */
export const MessageScroll = {
  mounted() {
    this.wasNearEnd = true
    this.lastChannelId = this.el.dataset.channelId
    this.cleanupScroll = attachMongolianWheelScroll(this.el)

    // Immediately snap to the latest messages on the right before paint
    this.scrollToEndInstant()

    // Track whether the user is actually near the rightmost edge (latest messages)
    this.onScroll = () => {
      const maxScroll = this.el.scrollWidth - this.el.clientWidth
      this.wasNearEnd = maxScroll - this.el.scrollLeft < 120
    }
    this.el.addEventListener("scroll", this.onScroll, {passive: true})

    // Re-anchor if images or voice players expand width while user is at the end
    this.resizeObserver = new ResizeObserver(() => {
      if (this.wasNearEnd) this.scrollToEndInstant()
    })
    this.resizeObserver.observe(this.el)

    this.onComposerSent = () => {
      this.wasNearEnd = true
      this.scrollToEndInstant()
    }
    window.addEventListener("xamt:composer:sent", this.onComposerSent)
  },

  updated() {
    const currentChannelId = this.el.dataset.channelId
    // If switched channel, immediately jump to the rightmost latest record
    if (currentChannelId !== this.lastChannelId) {
      this.lastChannelId = currentChannelId
      this.wasNearEnd = true
      this.scrollToEndInstant()
      return
    }

    // Only auto-scroll to right if user was already reading the latest messages
    if (this.wasNearEnd) this.scrollToEndInstant()
  },

  destroyed() {
    if (this.cleanupScroll) this.cleanupScroll()
    if (this.resizeObserver) this.resizeObserver.disconnect()
    this.el.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("xamt:composer:sent", this.onComposerSent)
  },

  scrollToEndInstant() {
    this.el.scrollLeft = this.el.scrollWidth
  },
}

/**
 * @deprecated InfiniteScroll now compensates scrollLeft when older messages
 * are prepended. Kept as a no-op so MessageList imports stay valid during
 * the transition.
 */
export function attachMessageScrollLock(_el) {
  return () => {}
}
