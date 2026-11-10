/**
 * Wheel mapping for vertical-lr surfaces.
 * Runtime lives in mgl-common-ui; this file keeps Xamt's surface list
 * and the empty LiveView hook so existing phx-hook="MongolianScroll" markup
 * does not error.
 */
import {install} from "mgl-common-ui"

const SCROLL_CONTAINERS = [
  ".mn-surface",
  ".xamt-main-content",
  ".xamt-messages",
  ".xamt-rail__section",
  ".xamt-composer__editor",
  ".xamt-composer-wrap--poll",
  ".xamt-upload-preview",
  ".xamt-settings-panel",
  ".xamt-sheet__body",
  ".xamt-bot-modal-card",
].join(", ")

/**
 * Register the site-wide wheel interceptor once.
 * Keyboard page-turn and touch-drag stay off: chat uses Space/arrows elsewhere,
 * and message lists already scroll natively on touch.
 */
export function installGlobalMongolianWheelScroll() {
  install({
    selector: SCROLL_CONTAINERS,
    keyboard: false,
    drag: false,
  })
}

/**
 * @deprecated Prefer installGlobalMongolianWheelScroll().
 */
export function attachMongolianWheelScroll(_el) {
  return () => {}
}

export const MongolianScroll = {
  mounted() {
    if (!this.el.classList.contains("xamt-bot-modal-card")) return

    // Keep focused bot-manager fields visible above the Mongolian virtual keyboard.
    this._onFocusIn = (event) => {
      const target = event.target
      if (!(target instanceof HTMLElement)) return
      if (!target.matches("input, textarea, select")) return

      window.setTimeout(() => {
        target.scrollIntoView({behavior: "smooth", inline: "center", block: "nearest"})
      }, 150)
    }

    this.el.addEventListener("focusin", this._onFocusIn)
  },
  destroyed() {
    if (this._onFocusIn) this.el.removeEventListener("focusin", this._onFocusIn)
  },
}
