import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/xamt"
import topbar from "../vendor/topbar"
import "../vendor/mgl-web-ime/mgl-web-ime.js"
import {MongolianIME} from "./hooks/mongolian-ime"
import {MessageComposer, MessageList} from "./hooks/message-composer"

const Hooks = {
  ...colocatedHooks,
  MongolianIME,
  MessageComposer,
  MessageList,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

const applyTheme = (theme) => {
  const root = document.documentElement
  const mode = theme || "system"
  root.setAttribute("data-theme-mode", mode)

  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
  const useDark = mode === "dark" || (mode === "system" && prefersDark)

  root.classList.toggle("dark", useDark)
  localStorage.setItem("phx:theme", mode)
}

applyTheme(localStorage.getItem("phx:theme") || "dark")

window.addEventListener("phx:set-theme", (event) => {
  applyTheme(event.target?.dataset?.phxTheme)
})

window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  if (localStorage.getItem("phx:theme") === "system") {
    applyTheme("system")
  }
})

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/pwa/service-worker.js").catch(() => {})
  })
}

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)
    window.liveReloader = reloader
  })
}
