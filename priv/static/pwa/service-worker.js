const HTML_CACHE = "xamt-html-v1";
const ASSET_CACHE = "xamt-assets-v1";
const FONT_CACHE = "xamt-fonts-v1";

const SHELL = ["/", "/pwa/manifest.json"];
const ASSETS = ["/assets/css/app.css", "/assets/js/app.js"];
const FONTS = ["/fonts/OyunQaganTig.ttf"];

// 1. Install: pre-cache shell, assets, and fonts
self.addEventListener("install", (event) => {
  event.waitUntil(
    Promise.all([
      caches.open(HTML_CACHE).then((cache) => cache.addAll(SHELL)),
      caches.open(ASSET_CACHE).then((cache) => cache.addAll(ASSETS)),
      caches.open(FONT_CACHE).then((cache) => cache.addAll(FONTS))
    ]).then(() => self.skipWaiting())
  );
});

// 2. Activate: drop caches from older versions
self.addEventListener("activate", (event) => {
  const allowedCaches = [HTML_CACHE, ASSET_CACHE, FONT_CACHE];
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => !allowedCaches.includes(k)).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// 3. Fetch: pick a cache strategy per request type
self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  // Skip LiveView WebSocket handshakes and long-lived connections
  if (request.url.includes("/live") || request.headers.get("upgrade") === "websocket") return;

  const url = new URL(request.url);

  // Do not cache the Background Sync HTTP endpoint (or any JSON API).
  if (url.pathname.startsWith("/api/")) return;

  // Strategy A: fonts -> Cache-First
  // Serve from cache immediately to avoid FOUT; fetch only on miss.
  if (url.pathname.startsWith("/fonts/")) {
    event.respondWith(
      caches.match(request).then((cached) => {
        return cached || fetch(request).then((response) => {
          const copy = response.clone();
          caches.open(FONT_CACHE).then((cache) => cache.put(request, copy));
          return response;
        });
      })
    );
    return;
  }

  // Strategy B: static assets (CSS/JS/Images) -> Stale-While-Revalidate
  // Return cache for instant paint; refresh in the background for next visit.
  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/images/")) {
    event.respondWith(
      caches.match(request).then((cached) => {
        const networkFetch = fetch(request).then((response) => {
          const copy = response.clone();
          caches.open(ASSET_CACHE).then((cache) => cache.put(request, copy));
          return response;
        }).catch(() => {}); // Ignore background refresh failures while offline

        return cached || networkFetch;
      })
    );
    return;
  }

  // Strategy C: pages -> Network-First (fall back to cache offline)
  // Prefer fresh content; only show the app shell when fully offline.
  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone();
        caches.open(HTML_CACHE).then((cache) => cache.put(request, copy));
        return response;
      })
      .catch(async () => {
        const cached = await caches.match(request);
        return cached || caches.match("/"); // Fully offline: return home shell
      })
  );
});

// 4. Background Sync: replay IndexedDB-queued messages over HTTP.
// The worker cannot reuse the LiveView WebSocket; keep DB constants in sync
// with assets/js/utils/offline-store.js.
const OFFLINE_DB = "XamtOfflineDB";
const OFFLINE_STORE = "pending_messages";
const OFFLINE_DB_VERSION = 3;
const SYNC_TAG = "sync-messages";
const CLAIM_LEASE_MS = 60000;

self.addEventListener("sync", (event) => {
  if (event.tag === SYNC_TAG) {
    event.waitUntil(flushOfflineMessages());
  }
});

async function flushOfflineMessages() {
  let sent = 0;

  for (;;) {
    const msg = await claimNextPendingMessage();
    if (!msg) return sent;

    try {
      const response = await fetch("/api/messages/sync", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "x-csrf-token": msg.csrf_token || ""
        },
        body: JSON.stringify({
          channel_id: msg.channel_id,
          content_html: (msg.payload && msg.payload.content_html) || msg.content_html,
          content_json: (msg.payload && msg.payload.content_json) || msg.content_json,
          content_type:
            (msg.payload && msg.payload.content_type) || msg.content_type || "rich_text",
          reply_to_id: (msg.payload && msg.payload.reply_to_id) || msg.reply_to_id || null
        })
      });

      if (response.ok) {
        await removePendingMessage(msg.id);
        sent += 1;
        continue;
      }

      if (shouldRetrySyncStatus(response.status)) {
        await releasePendingMessage(msg);
        throw new Error("Sync failed, will retry later: " + response.status);
      }

      // 4xx (other than 401/403/429): drop — retrying will not help
      await removePendingMessage(msg.id);
    } catch (err) {
      if (String(err.message || "").includes("will retry later")) throw err;
      await releasePendingMessage(msg);
      console.error("Sync failed, will retry later:", err);
      throw err;
    }
  }
}

function shouldRetrySyncStatus(status) {
  return status === 401 || status === 403 || status === 408 || status === 429 || status >= 500;
}

function openOfflineDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(OFFLINE_DB, OFFLINE_DB_VERSION);

    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains(OFFLINE_STORE)) {
        db.createObjectStore(OFFLINE_STORE, { keyPath: "id" });
      }
    };

    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function claimNextPendingMessage() {
  const db = await openOfflineDB();
  const now = Date.now();

  return new Promise((resolve, reject) => {
    const tx = db.transaction(OFFLINE_STORE, "readwrite");
    const store = tx.objectStore(OFFLINE_STORE);
    const req = store.openCursor();

    req.onsuccess = (e) => {
      const cursor = e.target.result;
      if (!cursor) {
        resolve(null);
        return;
      }

      const value = cursor.value;
      const claimedAt = value.claimed_at || 0;
      if (value.status === "sending" && now - claimedAt < CLAIM_LEASE_MS) {
        cursor.continue();
        return;
      }

      const claimed = Object.assign({}, value, { status: "sending", claimed_at: now });
      cursor.update(claimed);
      resolve(claimed);
    };

    req.onerror = () => reject(req.error);
    tx.onerror = () => reject(tx.error);
  });
}

async function removePendingMessage(id) {
  if (!id) return;
  const db = await openOfflineDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(OFFLINE_STORE, "readwrite");
    tx.objectStore(OFFLINE_STORE).delete(id);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function releasePendingMessage(msg) {
  if (!msg || !msg.id) return;
  const db = await openOfflineDB();
  const record = {
    id: msg.id,
    channel_id: msg.channel_id,
    event: msg.event || "send_message",
    payload: msg.payload || {},
    csrf_token: msg.csrf_token || "",
    timestamp: msg.timestamp || Date.now()
  };

  return new Promise((resolve, reject) => {
    const tx = db.transaction(OFFLINE_STORE, "readwrite");
    tx.objectStore(OFFLINE_STORE).put(record);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

// 5. Web Push: show a system notification and open the target URL on click.
self.addEventListener("push", (event) => {
  event.waitUntil(showPushNotification(event));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || "/";

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        if (client.url.includes(targetUrl) && "focus" in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});

async function showPushNotification(event) {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch (_error) {
    payload = { title: "Xamt", body: event.data.text(), url: "/" };
  }

  const options = {
    body: payload.body,
    icon: "/images/logo.svg",
    badge: "/images/logo.svg",
    data: { url: payload.url || "/" },
    vibrate: [200, 100, 200]
  };

  await self.registration.showNotification(payload.title || "Xamt", options);
}
