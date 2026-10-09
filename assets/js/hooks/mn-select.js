/**
 * Progressive enhancement for native <select> in vertical-lr forms.
 * Runtime lives in mgl-common-ui (`enhanceSelect`).
 *
 * Hook this on a `.mn-select-host` wrapper with `phx-update="ignore"` so
 * LiveView does not strip the injected trigger/list.
 */

import {enhanceSelect} from "mgl-common-ui"

export const MnSelect = {
  mounted() {
    const select = this.el.matches("select") ? this.el : this.el.querySelector("select")
    if (!(select instanceof HTMLSelectElement)) return
    this._api = enhanceSelect(select)
  },

  updated() {
    this._api?.sync()
  },

  destroyed() {
    this._api?.destroy()
    this._api = null
  },
}
