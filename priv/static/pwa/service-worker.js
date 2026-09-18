const CACHE = "xamt-shell-v1"
const SHELL = ["/", "/assets/css/app.css", "/assets/js/app.js", "/fonts/OyunQaganTig.ttf", "/pwa/manifest.json"]

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return

  // LiveView / websocket traffic should not be cached as offline chat
  if (request.url.includes("/live") || request.headers.get("upgrade") === "websocket") return

  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone()
        if (request.url.includes("/assets/") || request.url.includes("/fonts/")) {
          caches.open(CACHE).then((cache) => cache.put(request, copy))
        }
        return response
      })
      .catch(async () => {
        const cached = await caches.match(request)
        return cached || caches.match("/")
      })
  )
})
