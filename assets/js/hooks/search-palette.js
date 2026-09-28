/**
 * Global Cmd+K search palette. Listens for `xamt:open_search` (dispatched from
 * app.js) and focuses the vertical query field when the overlay opens.
 */
export const SearchPalette = {
  mounted() {
    this.onOpen = () => this.pushEvent("open_search", {})
    window.addEventListener("xamt:open_search", this.onOpen)
  },

  updated() {
    if (!this.el.querySelector("[data-search-open]")) return

    const input = this.el.querySelector("#global-search-q")
    if (input && document.activeElement !== input) {
      input.focus({preventScroll: true})
    }
  },

  destroyed() {
    window.removeEventListener("xamt:open_search", this.onOpen)
  },
}
