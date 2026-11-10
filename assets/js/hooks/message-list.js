/**
 * Horizontal message list + new-message edge indicator.
 *
 * Instant right-edge snap on mount / channel switch / composer send.
 * Auto-scroll only while the user is already near the latest messages.
 * InfiniteScroll compensates scrollLeft when older pages prepend on the left.
 */
import {highlightMessage as flashHighlight} from "../utils/highlight-message.js"
import {attachReadReceipt} from "./read-receipt.js"

// vertical-lr: newest message is the right-most column.
const NEAR_LATEST_PX = 120

export const MessageList = {
  mounted() {
    this.jumpBtn = document.getElementById("jump-latest")
    this.countSpan = document.getElementById("jump-latest-count")
    this.unreadCount = 0
    this._channelId = this.el.dataset.channelId
    this.wasNearEnd = true

    this._onJump = () => {
      if (this.el.dataset.viewingLatest === "false") {
        this.pushEvent("jump_latest", {})
      } else {
        this.scrollToEndInstant(true)
      }
    }
    this.jumpBtn?.addEventListener("click", this._onJump)

    this._onScroll = () => {
      this.wasNearEnd = this.nearLatestEdge()
      if (this.wasNearEnd) this.hideJump()
    }
    this.el.addEventListener("scroll", this._onScroll, {passive: true})

    this._receipt = attachReadReceipt(this)

    // Immediately snap to latest before paint
    this.scrollToEndInstant(false)

    // Re-anchor if images / voice players expand width while at the end
    this.resizeObserver = new ResizeObserver(() => {
      if (this.wasNearEnd) this.scrollToEndInstant(false)
    })
    this.resizeObserver.observe(this.el)

    this._onComposerSent = () => {
      this.wasNearEnd = true
      this.scrollToEndInstant(false)
    }
    window.addEventListener("xamt:composer:sent", this._onComposerSent)

    this.handleEvent("messages:scroll_bottom", () => {
      if (this.nearLatest()) {
        this.scrollToEndInstant(true)
      } else {
        this.unreadCount += 1
        this.showJump()
      }
    })

    this.handleEvent("messages:scroll_to", ({id}) => this.highlightMessage(id))
    this.handleEvent("messages:scroll_latest", () => this.scrollToEndInstant(true))
    this.highlightFromDataset()
  },

  updated() {
    const channelId = this.el.dataset.channelId
    // Channel switch: instant jump to rightmost latest messages
    if (channelId !== this._channelId) {
      this._channelId = channelId
      this.wasNearEnd = true
      this.hideJump()
      this.scrollToEndInstant(false)
      window.dispatchEvent(
        new CustomEvent("xamt:channel-changed", {detail: {channelId}})
      )
    }

    // Do not re-snap on every patch — InfiniteScroll compensates prepends,
    // and new messages arrive via messages:scroll_bottom / composer:sent.
    this.highlightFromDataset()
    this._receipt?.updated()
  },

  destroyed() {
    this.jumpBtn?.removeEventListener("click", this._onJump)
    this.el.removeEventListener("scroll", this._onScroll)
    this.resizeObserver?.disconnect()
    window.removeEventListener("xamt:composer:sent", this._onComposerSent)
    this._receipt?.destroyed()
  },

  nearLatestEdge() {
    const maxScroll = this.el.scrollWidth - this.el.clientWidth
    return maxScroll - this.el.scrollLeft < NEAR_LATEST_PX
  },

  nearLatest() {
    return this.wasNearEnd || this.nearLatestEdge()
  },

  scrollToEndInstant(smooth) {
    this.hideJump()
    this.wasNearEnd = true

    if (smooth) {
      this.el.scrollTo({left: this.el.scrollWidth, behavior: "smooth"})
      return
    }

    this.el.scrollLeft = this.el.scrollWidth
    // One rAF follow-up for mobile engines that finalize scrollWidth after paint
    requestAnimationFrame(() => {
      if (this.wasNearEnd) this.el.scrollLeft = this.el.scrollWidth
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
