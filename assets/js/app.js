import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/xamt"
import topbar from "../vendor/topbar"
import "../vendor/mgl-web-ime/mgl-web-ime.js"
import {MongolianIME} from "./hooks/mongolian-ime"
import {MessageComposer, MessageList} from "./hooks/message-composer"
import {InfiniteScroll} from "./hooks/infinite-scroll"
import {MongolianScroll, attachMongolianWheelScroll} from "./hooks/mongolian-scroll"
import {MobileDrawer} from "./hooks/mobile-drawer"
import {ToastHandler} from "./hooks/toast-handler"
import {adoptImeElements} from "./utils/ime"
import {trackViewportHeight} from "./utils/viewport"

const Hooks = {
  ...colocatedHooks,
  MongolianIME,
  MessageComposer,
  MessageList,
  InfiniteScroll,
  MongolianScroll,
  MobileDrawer,
  ToastHandler,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

topbar.config({
  barColors: {0: "#3d8f6e"},
  shadowColor: "rgba(0, 0, 0, .3)",
  className: "xamt-topbar",
})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Map vertical wheel to horizontal scroll on .xamt-main-content
window.addEventListener("DOMContentLoaded", () => {
  const mainContent = document.querySelector(".xamt-main-content")
  if (mainContent) {
    attachMongolianWheelScroll(mainContent)
  }
})

// Dispatched by JS.dispatch/2 on a quoted message so we can reveal it in the
// horizontally scrolling message list.
const HIGHLIGHT_MS = 1600

window.addEventListener("xamt:scroll-to", (event) => {
  const el = event.target
  if (!(el instanceof HTMLElement)) return

  el.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"})
  el.classList.add("is-highlighted")
  setTimeout(() => el.classList.remove("is-highlighted"), HIGHLIGHT_MS)
})

trackViewportHeight()
adoptImeElements()
window.addEventListener("DOMContentLoaded", () => adoptImeElements())

liveSocket.connect()
window.liveSocket = liveSocket

const THEME_COLORS = {dark: "#101412", light: "#f4efe4"}

const applyTheme = (theme) => {
  const root = document.documentElement
  const mode = theme || "system"
  root.setAttribute("data-theme-mode", mode)

  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
  const useDark = mode === "dark" || (mode === "system" && prefersDark)

  root.classList.toggle("dark", useDark)

  const themeColor = document.querySelector("meta[name='theme-color']")
  if (themeColor) themeColor.setAttribute("content", THEME_COLORS[useDark ? "dark" : "light"])

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
