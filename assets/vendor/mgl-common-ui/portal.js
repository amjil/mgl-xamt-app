/**
 * Mount a node on document.body so it is not rotated by a vertical-lr ancestor.
 * Overlays (IME, mention pickers, quote toolbars) must use this.
 *
 * @param {HTMLElement} node
 * @param {{ className?: string }} [options]
 * @returns {() => void} unmount
 */
export function portal(node, options = {}) {
  if (!(node instanceof Node)) return () => {}

  node.classList.add("mn-overlay")
  if (options.className) node.classList.add(options.className)
  document.body.appendChild(node)

  return () => {
    if (node.parentNode) node.parentNode.removeChild(node)
  }
}
