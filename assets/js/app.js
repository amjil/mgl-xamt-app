import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/xamt"
import topbar from "../vendor/topbar"
import "../vendor/mgl-web-ime/mgl-web-ime.js"
import {MongolianIME} from "./hooks/mongolian-ime"
import {MessageComposer} from "./hooks/message-composer"
import {MessageList} from "./hooks/message-list"
import {AudioRecorder} from "./hooks/audio-recorder"
import {InfiniteScroll} from "./hooks/infinite-scroll"
import {MongolianScroll, installGlobalMongolianWheelScroll} from "./hooks/mongolian-scroll"
import {MessageScroll} from "./hooks/message-scroll"
import {MobileDrawer} from "./hooks/mobile-drawer"
import {ToastHandler} from "./hooks/toast-handler"
import {ReadReceipt} from "./hooks/read-receipt"
import {WebPush} from "./hooks/web-push"
import {LightboxSwipe} from "./hooks/lightbox-swipe"
import {StatusEmoji} from "./hooks/status-emoji"
import {adoptImeElements} from "./utils/ime"
import {initVisualViewport, trackImeKeyboard} from "./utils/viewport"
import {toast} from "./utils/offline-store"
import {highlightMessageById} from "./utils/highlight-message"
import {copyText} from "./utils/clipboard"

// Bind --xamt-vh before LiveSocket so the shell is already keyboard-aware
initVisualViewport()
trackImeKeyboard()

const Hooks = {
  ...colocatedHooks,
  MongolianIME,
  MessageComposer,
  MessageList,
  AudioRecorder,
  MessageScroll,
  InfiniteScroll,
  MongolianScroll,
  MobileDrawer,
  ToastHandler,
  ReadReceipt,
  WebPush,
  LightboxSwipe,
  StatusEmoji,
}

// Jittered backoff for reconnect/rejoin so a server restart or regional
// outage does not stampede the node when every client retries at once.
const backoffJitter = (tries) => {
  const intervals = [
    [1000, 3000],
    [3000, 10000],
    [10000, 30000],
  ]

  const index = Math.min(tries - 1, intervals.length - 1)
  const [min, max] = intervals[index]

  return Math.floor(Math.random() * (max - min + 1)) + min
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
    timezone_offset: new Date().getTimezoneOffset(),
  },
  hooks: Hooks,
  reconnectAfterMs: backoffJitter,
  rejoinAfterMs: backoffJitter,
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

// Channel-scoped custom status badges — patch DOM without re-streaming messages.
window.addEventListener("phx:sync_status_badges", (event) => {
  const {user_id: userId, emoji, text} = event.detail || {}
  if (!userId) return

  document
    .querySelectorAll(`.status-badge-container[data-user-id="${CSS.escape(String(userId))}"]`)
    .forEach((container) => {
      container.replaceChildren()

      if (!emoji) return

      const badge = document.createElement("span")
      badge.className = "xamt-status-badge is-pop"

      const emojiEl = document.createElement("span")
      emojiEl.className = "xamt-status-badge__emoji"
      emojiEl.setAttribute("aria-hidden", "true")
      emojiEl.textContent = emoji
      badge.appendChild(emojiEl)

      if (text) {
        const tip = document.createElement("span")
        tip.className = "xamt-status-badge__tip mongol-text"
        tip.textContent = text
        badge.appendChild(tip)
      }

      container.appendChild(badge)
      window.setTimeout(() => badge.classList.remove("is-pop"), 320)
    })
})

// Poll bar chart — animate widths without re-streaming the message article.
window.addEventListener("phx:update_poll_chart", (event) => {
  const {poll_id: pollId, total_votes: totalVotes, options, selected_option_ids: selected} =
    event.detail || {}
  if (!pollId || !Array.isArray(options)) return

  const pollContainer = document.getElementById(`poll-${pollId}`)
  if (!pollContainer) return

  const card = pollContainer.closest(".xamt-poll")
  const totalEl = card?.querySelector(".poll-total-count")
  if (totalEl) totalEl.textContent = String(totalVotes ?? 0)

  const denom = Math.max(Number(totalVotes) || 0, 1)

  options.forEach((opt) => {
    const percent = Math.round((Number(opt.count) / denom) * 100)
    const bar = pollContainer.querySelector(`.poll-bar[data-option-id="${CSS.escape(opt.id)}"]`)
    const text = pollContainer.querySelector(
      `.poll-percent[data-option-id="${CSS.escape(opt.id)}"]`
    )
    if (bar) bar.style.setProperty("--poll-pct", `${percent}%`)
    if (text) text.textContent = `${percent}%`
  })

  if (Array.isArray(selected)) {
    const selectedSet = new Set(selected)
    pollContainer.querySelectorAll(".xamt-poll__option").forEach((row) => {
      const btn = row.querySelector("[data-option-id], .poll-percent")
      const optionId = btn?.getAttribute("data-option-id")
      if (!optionId) return
      row.classList.toggle("is-selected", selectedSet.has(optionId))
    })
  }
})

// Native click keeps the user-activation token that clipboard APIs require.
// Capture phase so a LiveView handler cannot swallow the event before we copy.
window.addEventListener(
  "click",
  (event) => {
    const el = event.target instanceof Element ? event.target.closest("[data-copy]") : null
    if (!el) return

    const text = el.getAttribute("data-copy")
    if (!text) return

    copyText(text)
      .then(() => toast("success", el.getAttribute("data-copied") || "Copied"))
      .catch(() => toast("error", el.getAttribute("data-copy-failed") || "Could not copy"))
  },
  true
)

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
