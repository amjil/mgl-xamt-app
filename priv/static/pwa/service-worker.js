const HTML_CACHE = "xamt-html-v1";
const ASSET_CACHE = "xamt-assets-v1";
const FONT_CACHE = "xamt-fonts-v1";

const SHELL = ["/", "/pwa/manifest.json"];
const ASSETS = ["/assets/css/app.css", "/assets/js/app.js"];
const FONTS = ["/fonts/OyunQaganTig.ttf"];

// 1. 安装阶段：强预热核心文件和字体
self.addEventListener("install", (event) => {
  event.waitUntil(
    Promise.all([
      caches.open(HTML_CACHE).then((cache) => cache.addAll(SHELL)),
      caches.open(ASSET_CACHE).then((cache) => cache.addAll(ASSETS)),
      caches.open(FONT_CACHE).then((cache) => cache.addAll(FONTS))
    ]).then(() => self.skipWaiting())
  );
});

// 2. 激活阶段：清理旧版本缓存
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

// 3. 拦截请求：分发不同的缓存策略
self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  // 绕过 LiveView 的 WebSocket 握手和长连接
  if (request.url.includes("/live") || request.headers.get("upgrade") === "websocket") return;

  const url = new URL(request.url);

  // Do not cache the Background Sync HTTP endpoint (or any JSON API).
  if (url.pathname.startsWith("/api/")) return;

  // 策略 A: 字体文件 -> Cache-First (缓存优先)
  // 命中缓存立即返回，避免字体闪烁。未命中才走网络。
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

  // 策略 B: 静态资源 (CSS/JS/Images) -> Stale-While-Revalidate (异步验证)
  // 先返回缓存保证秒开，后台默默发请求更新缓存，下次生效。
  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/images/")) {
    event.respondWith(
      caches.match(request).then((cached) => {
        const networkFetch = fetch(request).then((response) => {
          const copy = response.clone();
          caches.open(ASSET_CACHE).then((cache) => cache.put(request, copy));
          return response;
        }).catch(() => {}); // 忽略断网时的后台更新失败

        return cached || networkFetch;
      })
    );
    return;
  }

  // 策略 C: 页面与 API -> Network-First (网络优先，断网退回缓存)
  // 保证能看到最新消息，只有完全离线时才显示 App Shell。
  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone();
        caches.open(HTML_CACHE).then((cache) => cache.put(request, copy));
        return response;
      })
      .catch(async () => {
        const cached = await caches.match(request);
        return cached || caches.match("/"); // 彻底断网返回首页离线包
      })
  );
});

// 4. Background Sync: replay IndexedDB-queued messages over HTTP.
// The worker cannot reuse the LiveView WebSocket; keep DB constants in sync
// with assets/js/utils/offline-store.js.
const OFFLINE_DB = "XamtOfflineDB";
const OFFLINE_STORE = "pending_messages";
const OFFLINE_DB_VERSION = 2;
const SYNC_TAG = "sync-messages";

self.addEventListener("sync", (event) => {
  if (event.tag === SYNC_TAG) {
    event.waitUntil(flushOfflineMessages());
  }
});

async function flushOfflineMessages() {
  let sent = 0;

  for (;;) {
    const msg = await takeNextPendingMessage();
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
        sent += 1;
        continue;
      }

      if (shouldRetrySyncStatus(response.status)) {
        await putPendingMessage(msg);
        throw new Error("Sync failed, will retry later: " + response.status);
      }
      // 4xx (other than 401/403/429): drop — retrying will not help
    } catch (err) {
      if (String(err.message || "").includes("will retry later")) throw err;
      await putPendingMessage(msg);
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
      if (db.objectStoreNames.contains(OFFLINE_STORE)) {
        db.deleteObjectStore(OFFLINE_STORE);
      }
      db.createObjectStore(OFFLINE_STORE, { keyPath: "id" });
    };

    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function takeNextPendingMessage() {
  const db = await openOfflineDB();
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
      cursor.delete();
      resolve(value);
    };

    req.onerror = () => reject(req.error);
    tx.onerror = () => reject(tx.error);
  });
}

async function putPendingMessage(msg) {
  const db = await openOfflineDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(OFFLINE_STORE, "readwrite");
    tx.objectStore(OFFLINE_STORE).put(msg);
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
