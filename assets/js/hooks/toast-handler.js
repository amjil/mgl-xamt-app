/**
 * Listens for window "xamt:toast" CustomEvents and renders transient UI toasts.
 * Mounted on a phx-update="ignore" container so LiveView patches never wipe toasts.
 */
export const ToastHandler = {
  mounted() {
    this._onToast = (e) => {
      const { type = "info", text } = e.detail || {}
      if (!text) return

      const toast = document.createElement("div")
      toast.setAttribute("role", "status")
      toast.className = [
        "xamt-alert",
        type === "warning" && "xamt-alert--warning",
        type === "success" && "xamt-alert--success",
        type === "error" && "xamt-alert--error",
        (!type || type === "info") && "xamt-alert--info",
      ]
        .filter(Boolean)
        .join(" ")

      toast.textContent = text
      this.el.appendChild(toast)

      window.setTimeout(() => {
        toast.style.opacity = "0"
        toast.style.transition = "opacity 300ms ease"
        window.setTimeout(() => toast.remove(), 300)
      }, 3000)
    }

    window.addEventListener("xamt:toast", this._onToast)
  },

  destroyed() {
    window.removeEventListener("xamt:toast", this._onToast)
  },
}
