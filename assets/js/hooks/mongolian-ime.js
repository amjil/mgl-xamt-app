/**
 * Mongolian IME hook for plain <input> / <textarea>.
 * Uses ../mgl-web-ime.js (vendored).
 */
import { MglIME } from "../../vendor/mgl-web-ime/mgl-web-ime.js"

const instances = new WeakMap()

export const MongolianIME = {
  mounted() {
    const ime = new MglIME({
      target: this.el,
      profile: "auto",
      keyboard: "auto",
      baseUrl: this.el.dataset.imeBaseUrl || "http://dev1:3003",
      mount: document.body,
    })
    instances.set(this.el, ime)
  },

  destroyed() {
    const ime = instances.get(this.el)
    if (ime && typeof ime.destroy === "function") ime.destroy()
    instances.delete(this.el)
  },
}
