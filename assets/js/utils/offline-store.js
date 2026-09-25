/**
 * IndexedDB queue for messages that could not go out over LiveView.
 *
 * The Service Worker cannot reuse the LiveView socket, so queued sends are
 * flushed over POST /api/messages/sync (session cookie + CSRF). Keep the
 * database name, version, and store in sync with priv/static/pwa/service-worker.js.
 *
 * Items are claimed (status: sending) before POST and only deleted after a
 * 2xx response, so a crash mid-flush cannot drop the message.
 */
export const SYNC_TAG = "sync-messages"

const CLAIM_LEASE_MS = 60_000

export const OfflineStore = {
  dbName: "XamtOfflineDB",
  storeName: "pending_messages",
  version: 3,
  _dbPromise: null,

  init() {
    if (this._dbPromise) return this._dbPromise

    this._dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(this.dbName, this.version)

      req.onupgradeneeded = (e) => {
        const db = e.target.result
        // Never wipe the queue on upgrade — only create the store if missing.
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName, {keyPath: "id"})
        }
      }

      req.onsuccess = (e) => {
        const db = e.target.result
        db.onversionchange = () => {
          db.close()
          this._dbPromise = null
        }
        resolve(db)
      }

      req.onerror = (e) => {
        this._dbPromise = null
        reject(e.target.error)
      }
    })

    return this._dbPromise
  },

  async save(message) {
    const db = await this.init()
    const record = {
      id: message.id || crypto.randomUUID(),
      channel_id: message.channel_id,
      event: message.event || "send_message",
      payload: message.payload || {},
      csrf_token: message.csrf_token || csrfToken(),
      timestamp: message.timestamp || Date.now(),
    }

    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite")
      tx.objectStore(this.storeName).put(record)
      tx.oncomplete = () => resolve(record)
      tx.onerror = () => reject(tx.error)
    })
  },

  /**
   * Claim the next queued message for sending without deleting it.
   * Skips rows still within an active claim lease so the page and Service
   * Worker cannot both flush the same item.
   */
  async claimNext(leaseMs = CLAIM_LEASE_MS) {
    const db = await this.init()
    const now = Date.now()

    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite")
      const store = tx.objectStore(this.storeName)
      const req = store.openCursor()

      req.onsuccess = (e) => {
        const cursor = e.target.result
        if (!cursor) {
          resolve(null)
          return
        }

        const value = cursor.value
        const claimedAt = value.claimed_at || 0
        if (value.status === "sending" && now - claimedAt < leaseMs) {
          cursor.continue()
          return
        }

        const claimed = {...value, status: "sending", claimed_at: now}
        cursor.update(claimed)
        resolve(claimed)
      }

      req.onerror = () => reject(req.error)
      tx.onerror = () => reject(tx.error)
    })
  },

  async remove(id) {
    if (!id) return
    const db = await this.init()

    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite")
      tx.objectStore(this.storeName).delete(id)
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  },

  /** Clear the claim lease so another flusher can retry. */
  async release(message) {
    if (!message?.id) return

    const db = await this.init()
    const record = {
      id: message.id,
      channel_id: message.channel_id,
      event: message.event || "send_message",
      payload: message.payload || {},
      csrf_token: message.csrf_token || csrfToken(),
      timestamp: message.timestamp || Date.now(),
    }

    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite")
      tx.objectStore(this.storeName).put(record)
      tx.oncomplete = () => resolve(record)
      tx.onerror = () => reject(tx.error)
    })
  },

  async count() {
    const db = await this.init()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readonly")
      const req = tx.objectStore(this.storeName).count()
      req.onsuccess = () => resolve(req.result || 0)
      req.onerror = () => reject(req.error)
    })
  },
}

export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}

export async function registerBackgroundSync() {
  if (!("serviceWorker" in navigator) || !("SyncManager" in window)) return false

  try {
    const registration = await navigator.serviceWorker.ready
    await registration.sync.register(SYNC_TAG)
    return true
  } catch (_err) {
    return false
  }
}

export function shouldRetrySyncStatus(status) {
  return status === 401 || status === 403 || status === 408 || status === 429 || status >= 500
}

export async function postQueuedMessage(msg) {
  const csrf = msg.csrf_token || csrfToken()
  const payload = msg.payload || {}

  return fetch("/api/messages/sync", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "x-csrf-token": csrf,
    },
    body: JSON.stringify({
      channel_id: msg.channel_id,
      content_html: payload.content_html ?? msg.content_html,
      content_json: payload.content_json ?? msg.content_json,
      content_type: payload.content_type ?? msg.content_type ?? "rich_text",
      reply_to_id: payload.reply_to_id ?? msg.reply_to_id ?? null,
    }),
  })
}

export async function flushPendingMessages() {
  let sent = 0

  for (;;) {
    const msg = await OfflineStore.claimNext()
    if (!msg) return sent

    try {
      const response = await postQueuedMessage(msg)
      if (response.ok) {
        await OfflineStore.remove(msg.id)
        sent += 1
        continue
      }

      if (shouldRetrySyncStatus(response.status)) {
        await OfflineStore.release(msg)
        throw new Error(`sync failed: ${response.status}`)
      }

      // Non-retryable 4xx: drop — retrying will not help.
      await OfflineStore.remove(msg.id)
    } catch (err) {
      if (err?.message?.startsWith("sync failed:")) throw err
      await OfflineStore.release(msg)
      throw err
    }
  }
}

export function toast(type, text) {
  window.dispatchEvent(
    new CustomEvent("xamt:toast", {
      detail: {type, text},
    })
  )
}
