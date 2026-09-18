export const InfiniteScroll = {
  mounted() {
    this.loading = false
    this.oldScrollHeight = null

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.loading) {
            this.loading = true
            this.oldScrollHeight = this.el.parentNode.scrollHeight

            // Read event name dynamically; fall back to load_older for compatibility
            const eventName = this.el.dataset.event || "load_older"
            this.pushEvent(eventName, {})
          }
        })
      },
      // rootMargin 200px: trigger slightly before the top for smoother loading
      {root: this.el.parentNode, rootMargin: "200px"}
    )

    this.observer.observe(this.el)

    this.handleEvent("infinite_scroll:done", () => {
      this.observer.disconnect()
    })
  },

  updated() {
    // After LiveView stream_insert at: 0, compensate scroll so the viewport stays put
    if (this.oldScrollHeight != null) {
      const newScrollHeight = this.el.parentNode.scrollHeight
      this.el.parentNode.scrollTop += newScrollHeight - this.oldScrollHeight
      this.oldScrollHeight = null
    }

    this.loading = false
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },
}
