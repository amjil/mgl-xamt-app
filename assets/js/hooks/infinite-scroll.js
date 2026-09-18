export const InfiniteScroll = {
  mounted() {
    this.loading = false
    this.eventName = this.el.dataset.event || "load_older"

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.loading) {
            this.loading = true
            this.pushEvent(this.eventName, {})
          }
        })
      },
      // Distance at which infinite load is triggered
      {root: this.el.parentNode, rootMargin: "200px"}
    )

    this.observer.observe(this.el)

    this.handleEvent("infinite_scroll:done", ({event} = {}) => {
      if (!event || event === this.eventName) this.observer.disconnect()
    })
  },

  updated() {
    this.loading = false
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },
}
