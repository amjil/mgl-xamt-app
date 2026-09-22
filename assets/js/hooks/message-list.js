/**
 * Horizontal message list + new-message edge indicator.
 *
 * Relies on LiveView `messages:scroll_bottom` (not MutationObserver) so
 * infinite-scroll prepends / reaction re-inserts do not inflate the unread
 * count. When the user has scrolled left into history, auto-scroll is blocked
 * and `#jump-latest` slides in on the right edge with a running count.
 *
 * Channel switches (`data-channel-id`) pin to latest and defer scrollTo until
 * after rAF + a short settle so mobile browsers finish text layout first.
 */
import { highlightMessage as flashHighlight } from "../utils/highlight-message.js"
import { attachMessageScrollLock } from "./message-scroll.js"
import { attachReadReceipt } from "./read-receipt.js"

// vertical-lr: newest message is the right-most column.
// Mobile Mongolian layout often leaves a few dozen px of subpixel slack.
const NEAR_LATEST_PX = 80

/** Wait for mobile layout engines to finish measuring scrollWidth after a stream swap. */
const SCROLL_SETTLE_MS = 50

export const MessageList = {
  mounted() {
    this.jumpBtn = document.getElementById("jump-latest")
    this.countSpan = document.getElementById("jump-latest-count")
    this.unreadCount = 0
    this._channelId = this.el.dataset.channelId
    this._atLatest = true
    this._scrollTimer = null

    this._onJump = () => this.scrollToLatest(true)
    this.jumpBtn?.addEventListener("click", this._onJump)

    this._onScroll = () => {
      this._atLatest = this.nearLatestEdge()
      if (this._atLatest) this.hideJump()
    }
    this.el.addEventListener("scroll", this._onScroll, {passive: true})

    // Lock scrollLeft when older messages prepend and scrollWidth grows
    this._detachScrollLock = attachMessageScrollLock(this.el)
    this._receipt = attachReadReceipt(this)

    this.scrollToLatest(false)

    this.handleEvent("messages:scroll_bottom", () => {
      requestAnimationFrame(() => {
        if (this.nearLatest()) {
          this.scrollToLatest(true)
        } else {
          this.unreadCount += 1
          this.showJump()
        }
      })
    })

    this.handleEvent("messages:scroll_to", ({id}) => this.highlightMessage(id))
    this.highlightFromDataset()
  },

  updated() {
    const channelId = this.el.dataset.channelId
    if (channelId !== this._channelId) {
      this._channelId = channelId
      // Treat switch as "at latest" while layout settles; avoids false unread.
      this._atLatest = true
      this.hideJump()
      this.scrollToLatest(false)
    }

    this.highlightFromDataset()
    this._receipt?.updated()
  },

  destroyed() {
    if (this._scrollTimer != null) clearTimeout(this._scrollTimer)
    this.jumpBtn?.removeEventListener("click", this._onJump)
    this.el.removeEventListener("scroll", this._onScroll)
    this._detachScrollLock?.()
    this._receipt?.destroyed()
  },

  nearLatestEdge() {
    const scrollRight =
      this.el.scrollWidth - this.el.scrollLeft - this.el.clientWidth
    return scrollRight <= NEAR_LATEST_PX
  },

  nearLatest() {
    return this._atLatest || this.nearLatestEdge()
  },

  scrollToLatest(smooth) {
    this.hideJump()
    this._atLatest = true

    if (this._scrollTimer != null) clearTimeout(this._scrollTimer)

    // rAF: wait for LiveView's DOM patch to paint; then give mobile engines
    // a beat to finish measuring the final scrollWidth before scrolling.
    requestAnimationFrame(() => {
      this._scrollTimer = setTimeout(() => {
        this._scrollTimer = null
        this.el.scrollTo({
          left: this.el.scrollWidth,
          behavior: smooth ? "smooth" : "auto",
        })
      }, SCROLL_SETTLE_MS)
    })
  },

  showJump() {
    if (!this.jumpBtn) return
    if (this.countSpan) this.countSpan.textContent = String(this.unreadCount)
    this.jumpBtn.classList.add("is-visible")
    this.jumpBtn.setAttribute("aria-hidden", "false")
  },

  hideJump() {
    this.unreadCount = 0
    if (this.countSpan) this.countSpan.textContent = "0"
    this.jumpBtn?.classList.remove("is-visible")
    this.jumpBtn?.setAttribute("aria-hidden", "true")
  },

  highlightFromDataset() {
    const id = this.el.dataset.highlight
    if (id) this.highlightMessage(id)
  },

  highlightMessage(id) {
    if (!id || this._highlighted === id) return
    const article = this.el.querySelector(`[data-message-id="${CSS.escape(id)}"]`)
    if (!article) return

    this._highlighted = id
    flashHighlight(article)
  },
}
