/**
 * Optimistic "sending…" bubbles for messages queued in IndexedDB.
 * Injected into #offline-pending (phx-update="ignore") so LiveView streams
 * cannot wipe them while the socket is down.
 */
import {OfflineStore} from "./offline-store.js"

function pendingRoot() {
  const list = document.getElementById("message-list")
  if (!list) return null

  let root = document.getElementById("offline-pending")
  if (root) return root

  root = document.createElement("div")
  root.id = "offline-pending"
  root.className = "xamt-offline-pending"
  root.setAttribute("phx-update", "ignore")
  list.appendChild(root)
  return root
}

function waitingLabel(root) {
  return root?.dataset?.waitingLabel || "Waiting for network…"
}

function pendingDomId(id) {
  return `offline-pending-${id}`
}

function sanitizePendingHtml(html) {
  const doc = new DOMParser().parseFromString(`<div>${html || ""}</div>`, "text/html")
  const root = doc.body.firstElementChild
  if (!root) return document.createDocumentFragment()

  root.querySelectorAll("script,style,iframe,object,embed,form").forEach((el) => el.remove())
  root.querySelectorAll("*").forEach((el) => {
    for (const attr of [...el.attributes]) {
      const name = attr.name.toLowerCase()
      if (name.startsWith("on") || name === "srcdoc") {
        el.removeAttribute(attr.name)
        continue
      }
      if ((name === "href" || name === "src") && /^\s*javascript:/i.test(attr.value)) {
        el.removeAttribute(attr.name)
      }
    }
  })

  const fragment = document.createDocumentFragment()
  fragment.append(...root.childNodes)
  return fragment
}

function excerptFromRecord(record) {
  const html = record?.payload?.content_html || record?.content_html || ""
  if (html) return html

  const text = record?.payload?.content || record?.content || ""
  if (!text) return ""
  const p = document.createElement("p")
  p.className = "block-content"
  p.textContent = text
  return p.outerHTML
}

export function renderPendingMessage(record) {
  const root = pendingRoot()
  if (!root || !record?.id) return null
  if (document.getElementById(pendingDomId(record.id))) return document.getElementById(pendingDomId(record.id))

  const article = document.createElement("article")
  article.id = pendingDomId(record.id)
  article.className = "xamt-message xamt-message--pending group"
  article.dataset.offlineId = record.id
  article.dataset.channelId = record.channel_id || ""

  const header = document.createElement("div")
  header.className = "xamt-message__header xamt-message__header--spacer"
  header.setAttribute("aria-hidden", "true")

  const body = document.createElement("div")
  body.className = "xamt-message__body"

  const content = document.createElement("div")
  content.className = "xamt-message__content mongol-text"
  content.appendChild(sanitizePendingHtml(excerptFromRecord(record)))

  const status = document.createElement("div")
  status.className = "xamt-message__pending-status mongol-text"
  const spinner = document.createElement("span")
  spinner.className = "hero-arrow-path size-3 motion-safe:animate-spin"
  spinner.setAttribute("aria-hidden", "true")
  const label = document.createElement("span")
  label.textContent = waitingLabel(root)
  status.append(spinner, label)

  body.append(content, status)
  article.append(header, body)
  root.appendChild(article)

  const list = document.getElementById("message-list")
  if (list) list.scrollLeft = list.scrollWidth

  return article
}

export function removePendingMessage(id) {
  if (!id) return
  document.getElementById(pendingDomId(id))?.remove()
}

export async function restorePendingMessages(channelId) {
  const root = pendingRoot()
  if (!root) return []

  if (channelId) root.dataset.channelId = channelId

  const pending = await OfflineStore.listByChannel(channelId)
  const keep = new Set(pending.map((msg) => String(msg.id)))

  for (const node of [...root.querySelectorAll("[data-offline-id]")]) {
    if (!keep.has(String(node.dataset.offlineId))) node.remove()
  }

  pending.forEach((msg) => renderPendingMessage(msg))
  return pending
}
