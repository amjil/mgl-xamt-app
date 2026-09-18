/**
 * Mongolian IME hook for plain <input> / <textarea>.
 * Uses ../mgl-web-ime.js (vendored).
 *
 * The IME already dispatches native `input` events, so LiveView `phx-change`
 * / submit sees the composed value. Keyboard and candidate UI mount on
 * `document.body` (z-index 10000) so they stay above form drawers.
 *
 * Do not recreate the instance on `updated()` — LiveView morphs the same
 * node in place, and remounting would reset composition / caret.
 */
import { MglIME } from "../../vendor/mgl-web-ime/mgl-web-ime.js"
import { imeProvider } from "../utils/ime.js"

const instances = new WeakMap()

export const MongolianIME = {
  mounted() {
    if (instances.has(this.el)) return

    const ime = new MglIME({
      target: this.el,
      profile: "auto",
      keyboard: "auto",
      provider: imeProvider(),
      mount: document.body,
    })
    instances.set(this.el, ime)
  },

  updated() {
    // Keep the existing IME across LiveView morphs (validation, patch).
  },

  destroyed() {
    const ime = instances.get(this.el)
    if (ime && typeof ime.destroy === "function") ime.destroy()
    instances.delete(this.el)
  },
}
