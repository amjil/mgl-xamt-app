/**
 * Closes the mobile server/channel/member drawers with Escape or a left swipe.
 * The drawers themselves are pure CSS driven by the `xamt-app--panel-*` class.
 */
const CLOSED_PANEL = "messages"
const SWIPE_DISTANCE = 60
const SWIPE_DRIFT = 50

export const MobileDrawer = {
  mounted() {
    this._onKey = (e) => {
      if (e.key === "Escape" && this.openPanel()) this.close()
    }

    this._onTouchStart = (e) => {
      if (!this.openPanel() || e.touches.length !== 1) {
        this._start = null
        return
      }
      this._start = {x: e.touches[0].clientX, y: e.touches[0].clientY}
    }

    this._onTouchEnd = (e) => {
      const start = this._start
      this._start = null
      if (!start) return

      const touch = e.changedTouches[0]
      const dx = touch.clientX - start.x
      const dy = Math.abs(touch.clientY - start.y)
      // Drawers slide in from the left, so a leftward swipe dismisses them
      if (dx < -SWIPE_DISTANCE && dy < SWIPE_DRIFT) this.close()
    }

    document.addEventListener("keydown", this._onKey)
    this.el.addEventListener("touchstart", this._onTouchStart, {passive: true})
    this.el.addEventListener("touchend", this._onTouchEnd, {passive: true})
  },

  destroyed() {
    document.removeEventListener("keydown", this._onKey)
    this.el.removeEventListener("touchstart", this._onTouchStart)
    this.el.removeEventListener("touchend", this._onTouchEnd)
  },

  openPanel() {
    const app = this.el.querySelector(".xamt-app")
    const match = app?.className.match(/xamt-app--panel-([a-z]+)/)
    return match && match[1] !== CLOSED_PANEL ? match[1] : null
  },

  close() {
    this.pushEvent("set_mobile_panel", {panel: CLOSED_PANEL})
  },
}
