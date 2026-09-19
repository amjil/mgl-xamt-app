import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/xamt"
import topbar from "../vendor/topbar"
import "../vendor/mgl-web-ime/mgl-web-ime.js"
import {MongolianIME} from "./hooks/mongolian-ime"
import {MessageComposer, MessageList} from "./hooks/message-composer"
import {InfiniteScroll} from "./hooks/infinite-scroll"
import {MongolianScroll, installGlobalMongolianWheelScroll} from "./hooks/mongolian-scroll"
import {MessageScroll} from "./hooks/message-scroll"
import {MobileDrawer} from "./hooks/mobile-drawer"
import {ToastHandler} from "./hooks/toast-handler"
import {ReadReceipt} from "./hooks/read-receipt"
import {WebPush} from "./hooks/web-push"
import {adoptImeElements} from "./utils/ime"
import {initVisualViewport, trackImeKeyboard} from "./utils/viewport"
import {toast} from "./utils/offline-store"
import {highlightMessageById} from "./utils/highlight-message"

// Bind --xamt-vh before LiveSocket so the shell is already keyboard-aware
initVisualViewport()
trackImeKeyboard()

const Hooks = {
  ...colocatedHooks,
  MongolianIME,
  MessageComposer,
  MessageList,
  MessageScroll,
  InfiniteScroll,
  MongolianScroll,
  MobileDrawer,
  ToastHandler,
  ReadReceipt,
  WebPush,
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

// Map vertical wheel → horizontal scroll for Mongolian (vertical-lr) surfaces
installGlobalMongolianWheelScroll()

// Dispatched by JS.dispatch/2 from quote buttons — no per-message Hook needed.
window.addEventListener("xamt:highlight", (event) => {
  const targetId = event.detail?.target_id
  if (!highlightMessageById(targetId)) {
    // Reply target may be outside the loaded stream window; MessageList can
    // opt into loading history later via push_event.
    console.warn(`Message ${targetId} not found in DOM.`)
  }
})

window.addEventListener("xamt:copy", async (event) => {
  const el =
    event.target instanceof HTMLElement ? event.target.closest("[data-copy]") : null
  if (!el) return

  const text = el.getAttribute("data-copy")
  if (!text) return

  try {
    await navigator.clipboard.writeText(text)
    toast("success", el.getAttribute("data-copied") || "Copied")
  } catch {
    toast("error", el.getAttribute("data-copy-failed") || "Could not copy")
  }
})

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
    // Root scope is required so chat pages can register Background Sync.
    // The SW file is under /pwa/, so the Endpoint sends Service-Worker-Allowed: /.
    navigator.serviceWorker.register("/pwa/service-worker.js", {scope: "/"}).catch(() => {})
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
