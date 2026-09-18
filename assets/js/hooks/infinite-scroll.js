export const InfiniteScroll = {
  mounted() {
    this.loading = false
    this.oldScrollWidth = null

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.loading) {
            this.loading = true
            this.oldScrollWidth = this.el.parentNode.scrollWidth

            // Read event name dynamically; fall back to load_older for compatibility
            const eventName = this.el.dataset.event || "load_older"
            this.pushEvent(eventName, {})
          }
        })
      },
      // 触发无限加载的距离
      {root: this.el.parentNode, rootMargin: "200px"}
    )

    this.observer.observe(this.el)

    this.handleEvent("infinite_scroll:done", () => {
      this.observer.disconnect()
    })
  },

  updated() {
    // 渲染旧消息后，补偿水平滚动条，使用户视线停留
    if (this.oldScrollWidth != null) {
      const newScrollWidth = this.el.parentNode.scrollWidth
      this.el.parentNode.scrollLeft += newScrollWidth - this.oldScrollWidth
      this.oldScrollWidth = null
    }

    this.loading = false
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },
}
