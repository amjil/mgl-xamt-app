/**
 * Viewport-based read watermark.
 *
 * Marks a channel as read only when the newest message actually intersects
 * the message list viewport (not merely when the channel is opened).
 */
export function attachReadReceipt(hook) {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue

        const el = entry.target
        const messageId = el.dataset.messageId
        const insertedAt = el.dataset.insertedAt

        if (!messageId || !insertedAt) {
          observer.unobserve(el)
          continue
        }

        // Monotonic within a channel: ignore older watermarks
        if (hook._lastMarkedAt && insertedAt < hook._lastMarkedAt) {
          observer.unobserve(el)
          continue
        }

        if (messageId === hook._lastMarkedId) {
          observer.unobserve(el)
          continue
        }

        hook._lastMarkedId = messageId
        hook._lastMarkedAt = insertedAt

        hook.pushEvent("mark_as_read", {
          message_id: messageId,
          inserted_at: insertedAt,
        })

        observer.unobserve(el)
      }
    },
    { root: hook.el, threshold: 0.5 }
  )

  const resetIfChannelChanged = () => {
    const channelId = hook.el.dataset.channelId || ""
    if (hook._channelId === channelId) return

    hook._channelId = channelId
    hook._lastMarkedId = null
    hook._lastMarkedAt = null

    if (hook._observedEl) {
      observer.unobserve(hook._observedEl)
      delete hook._observedEl.dataset.readObserved
      hook._observedEl = null
    }
  }

  const observeLatest = () => {
    resetIfChannelChanged()

    const messages = hook.el.querySelectorAll(".xamt-message[data-message-id]")
    if (messages.length === 0) return

    const lastMessage = messages[messages.length - 1]
    if (lastMessage.dataset.readObserved === "true") return

    // Drop observation on a previous "latest" that is no longer last
    if (hook._observedEl && hook._observedEl !== lastMessage) {
      observer.unobserve(hook._observedEl)
      delete hook._observedEl.dataset.readObserved
    }

    lastMessage.dataset.readObserved = "true"
    hook._observedEl = lastMessage
    observer.observe(lastMessage)
  }

  observeLatest()

  return {
    updated: observeLatest,
    destroyed: () => observer.disconnect(),
  }
}

export const ReadReceipt = {
  mounted() {
    this._receipt = attachReadReceipt(this)
  },

  updated() {
    this._receipt?.updated()
  },

  destroyed() {
    this._receipt?.destroyed()
  },
}
