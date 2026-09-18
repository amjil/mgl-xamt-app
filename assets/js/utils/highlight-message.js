/**
 * Smooth-scroll to a message and replay the CSS highlight flash.
 * Uses a forced reflow so the animation can re-trigger on every click.
 */
export function highlightMessage(el) {
  if (!(el instanceof HTMLElement)) return false

  // Horizontal Mongolian message list: center on the inline axis.
  el.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"})

  el.classList.remove("is-highlighted")
  void el.offsetWidth
  el.classList.add("is-highlighted")

  const onEnd = (event) => {
    if (event.target !== el || event.animationName !== "xamt-highlight-flash") return
    el.classList.remove("is-highlighted")
    el.removeEventListener("animationend", onEnd)
  }
  el.addEventListener("animationend", onEnd)

  return true
}

export function highlightMessageById(targetId) {
  if (!targetId) return false
  return highlightMessage(document.getElementById(targetId))
}
