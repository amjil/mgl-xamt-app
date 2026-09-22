/** Touch / pointer swipe between lightbox originals. */
export const LightboxSwipe = {
  mounted() {
    this.startX = null
    this.startY = null

    this.onPointerDown = (event) => {
      if (event.pointerType === "mouse" && event.button !== 0) return
      this.startX = event.clientX
      this.startY = event.clientY
    }

    this.onPointerUp = (event) => {
      if (this.startX == null) return

      const dx = event.clientX - this.startX
      const dy = event.clientY - this.startY
      this.startX = null
      this.startY = null

      if (Math.abs(dx) < 48 || Math.abs(dx) < Math.abs(dy)) return

      if (dx < 0) {
        this.pushEvent("lightbox_next", {})
      } else {
        this.pushEvent("lightbox_prev", {})
      }
    }

    this.onPointerCancel = () => {
      this.startX = null
      this.startY = null
    }

    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointerup", this.onPointerUp)
    this.el.addEventListener("pointercancel", this.onPointerCancel)
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("pointerup", this.onPointerUp)
    this.el.removeEventListener("pointercancel", this.onPointerCancel)
  },
}
