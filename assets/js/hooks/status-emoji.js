/**
 * Custom-status emoji slot: open <mgl-emoji-picker> and replace the value.
 * Desktop and mobile both use the picker — this field is not an IME target.
 */

export const StatusEmoji = {
  mounted() {
    this.picker = document.createElement("mgl-emoji-picker")
    document.body.appendChild(this.picker)

    this._onSelect = (event) => {
      const emoji = event.detail?.emoji
      if (!emoji) return
      this.applyEmoji(emoji)
      this.picker.hide()
    }

    this._onPointerDown = (event) => {
      event.preventDefault()
    }

    this._onClick = (event) => {
      event.preventDefault()
      event.stopPropagation()
      this.picker.toggle({ignore: this.el})
      if (this.picker.open) this.picker.positionNear(this.el)
      this.syncExpanded()
    }

    this._onOpen = () => this.syncExpanded()
    this._onClose = () => this.syncExpanded()

    // Capture Escape before the status sheet's phx-window-keydown closes it.
    this._onKey = (event) => {
      if (event.key !== "Escape" || !this.picker.open) return
      event.preventDefault()
      event.stopPropagation()
      this.picker.hide()
    }

    this.picker.addEventListener("mgl-emoji-select", this._onSelect)
    this.picker.addEventListener("mgl-emoji-open", this._onOpen)
    this.picker.addEventListener("mgl-emoji-close", this._onClose)
    this.el.addEventListener("pointerdown", this._onPointerDown)
    this.el.addEventListener("click", this._onClick)
    document.addEventListener("keydown", this._onKey, true)

    this.el.setAttribute("aria-haspopup", "dialog")
    this.el.setAttribute("inputmode", "none")
    this.el.setAttribute("readonly", "")
    this.syncExpanded()
  },

  destroyed() {
    document.removeEventListener("keydown", this._onKey, true)
    this.el.removeEventListener("pointerdown", this._onPointerDown)
    this.el.removeEventListener("click", this._onClick)
    this.picker?.removeEventListener("mgl-emoji-select", this._onSelect)
    this.picker?.removeEventListener("mgl-emoji-open", this._onOpen)
    this.picker?.removeEventListener("mgl-emoji-close", this._onClose)
    this.picker?.remove()
    this.picker = null
  },

  applyEmoji(emoji) {
    this.el.value = emoji
    this.el.dispatchEvent(new Event("input", {bubbles: true}))
  },

  syncExpanded() {
    this.el.setAttribute("aria-expanded", String(Boolean(this.picker?.open)))
  },
}
