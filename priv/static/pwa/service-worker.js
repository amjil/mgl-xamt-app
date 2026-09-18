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
