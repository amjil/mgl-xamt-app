/**
 * Intersection-triggered pagination.
 *
 * For the horizontal message list (`.xamt-messages`), older pages prepend on
 * the left (`at: 0`). After LiveView patches, `updated()` restores scrollLeft
 * by the newly added width so the viewport does not jump.
 *
 * Event name comes from `data-event` so the same hook drives both
 * `load_older` (messages) and `load_more_members` (members rail).
 */
export const InfiniteScroll = {
  mounted() {
    this.pending = false
    this.prevScrollWidth = 0
    this.prevScrollLeft = 0
    this.eventName = this.el.dataset.event || "load_older"
    this._timer = null
    this.scrollContainer =
      this.el.closest(".xamt-messages") || this.el.parentElement

    this.observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0]
        if (!entry?.isIntersecting || this.pending || !this.scrollContainer) return

        // Message list: only fire near the left edge, and only after the
        // container has already been scrolled to the right initially.
        if (this.scrollContainer.classList.contains("xamt-messages")) {
          const maxScroll =
            this.scrollContainer.scrollWidth - this.scrollContainer.clientWidth
          if (maxScroll > 0 && this.scrollContainer.scrollLeft > 50) return
        }

        this.pending = true
        this.prevScrollWidth = this.scrollContainer.scrollWidth
        this.prevScrollLeft = this.scrollContainer.scrollLeft
        this.armUnlock()
        this.pushEvent(this.eventName, {}, () => this.unlock())
      },
      {root: this.scrollContainer, threshold: 0.1}
    )

    this.observer.observe(this.el)

    this.handleEvent("infinite_scroll:done", ({event} = {}) => {
      if (!event || event === this.eventName) this.observer.disconnect()
    })
  },

  updated() {
    // When older messages are prepended at the left (at: 0),
    // compensate scrollLeft by the newly added width so the viewport stays put.
    if (this.pending && this.scrollContainer) {
      const newScrollWidth = this.scrollContainer.scrollWidth
      const addedWidth = newScrollWidth - this.prevScrollWidth
      if (addedWidth > 0) {
        this.scrollContainer.scrollLeft = this.prevScrollLeft + addedWidth
      }
    }
    this.unlock()
  },

  destroyed() {
    this.clearUnlock()
    if (this.observer) this.observer.disconnect()
  },

  armUnlock() {
    this.clearUnlock()
    this._timer = window.setTimeout(() => this.unlock(), 8000)
  },

  unlock() {
    this.clearUnlock()
    this.pending = false
  },

  clearUnlock() {
    if (this._timer) {
      window.clearTimeout(this._timer)
      this._timer = null
    }
  },
}
