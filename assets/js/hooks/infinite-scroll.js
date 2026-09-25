export const InfiniteScroll = {
  mounted() {
    this.loading = false
    this.eventName = this.el.dataset.event || "load_older"
    this._timer = null

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.loading) {
            this.loading = true
            this.armUnlock()
            this.pushEvent(this.eventName, {}, () => this.unlock())
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
    this.unlock()
  },

  destroyed() {
    this.clearUnlock()
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  armUnlock() {
    this.clearUnlock()
    this._timer = window.setTimeout(() => this.unlock(), 8000)
  },

  unlock() {
    this.clearUnlock()
    this.loading = false
  },

  clearUnlock() {
    if (this._timer) {
      window.clearTimeout(this._timer)
      this._timer = null
    }
  },
}
