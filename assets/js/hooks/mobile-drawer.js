/**
 * Mobile drawers: edge-swipe to open, opposite swipe or Escape to close.
 * The drawers themselves are pure CSS driven by the `xamt-app--panel-*` class.
 */
const CLOSED_PANEL = "messages"
const SWIPE_DISTANCE = 60
const SWIPE_DRIFT = 50
const EDGE = 28
const DRAWER_BREAKPOINT = 960

export const MobileDrawer = {
  mounted() {
    this._onKey = (e) => {
      if (e.key === "Escape" && this.openPanel()) this.close()
    }

    this._onTouchStart = (e) => {
      if (!this.isMobile() || e.touches.length !== 1) {
        this._start = null
        return
      }
      this._start = {
        x: e.touches[0].clientX,
        y: e.touches[0].clientY,
        target: e.target,
      }
    }

    this._onTouchEnd = (e) => {
      const start = this._start
      this._start = null
      if (!start || !this.isMobile()) return

      const touch = e.changedTouches[0]
      const dx = touch.clientX - start.x
      const dy = Math.abs(touch.clientY - start.y)
      if (dy >= SWIPE_DRIFT) return

      const panel = this.openPanel()
      // Channel/member lists are vertical-lr, so browsing them is a horizontal
      // drag. Don't treat that as "close the drawer".
      if (panel && this.startedInRail(start.target)) return

      if (panel === "members") {
        if (dx > SWIPE_DISTANCE) this.close()
        return
      }
      if (panel) {
        if (dx < -SWIPE_DISTANCE) this.close()
        return
      }

      if (start.x < EDGE && dx > SWIPE_DISTANCE) {
        this.pushEvent("set_mobile_panel", {panel: "channels"})
      } else if (start.x > window.innerWidth - EDGE && dx < -SWIPE_DISTANCE) {
        this.pushEvent("set_mobile_panel", {panel: "members"})
      }
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

  isMobile() {
    return window.innerWidth <= DRAWER_BREAKPOINT
  },

  openPanel() {
    const app = this.el.querySelector(".xamt-app")
    const match = app?.className.match(/xamt-app--panel-([a-z]+)/)
    return match && match[1] !== CLOSED_PANEL ? match[1] : null
  },

  close() {
    this.pushEvent("set_mobile_panel", {panel: CLOSED_PANEL})
  },

  startedInRail(target) {
    const el = target?.nodeType === 1 ? target : target?.parentElement
    return Boolean(el?.closest?.(".xamt-rail"))
  },
}
