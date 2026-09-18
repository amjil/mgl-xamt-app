/**
 * IndexedDB-backed offline queue for pending LiveView pushEvents.
 * Non-blocking; survives tab reloads while messages await reconnect.
 */
export const OfflineStore = {
  dbName: "XamtOfflineDB",
  storeName: "pending_messages",
  version: 1,
  _dbPromise: null,

  init() {
    if (this._dbPromise) return this._dbPromise

    this._dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(this.dbName, this.version)

      req.onupgradeneeded = (e) => {
        const db = e.target.result
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName, { autoIncrement: true })
        }
      }

      req.onsuccess = (e) => resolve(e.target.result)
      req.onerror = (e) => {
        this._dbPromise = null
        reject(e.target.error)
      }
    })

    return this._dbPromise
  },

  async save(message) {
    const db = await this.init()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite")
      tx.objectStore(this.storeName).add({
        ...message,
        timestamp: Date.now(),
      })
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  },

  async popAll() {
    const db = await this.init()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite")
      const store = tx.objectStore(this.storeName)
      const req = store.getAll()

      req.onsuccess = () => {
        const items = req.result || []
        if (items.length > 0) store.clear()
        resolve(items)
      }
      req.onerror = () => reject(req.error)
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

export function toast(type, text) {
  window.dispatchEvent(
    new CustomEvent("xamt:toast", {
      detail: { type, text },
    })
  )
}
