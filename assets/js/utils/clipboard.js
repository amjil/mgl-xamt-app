/**
 * Copy text to the clipboard during a user click.
 *
 * `navigator.clipboard` is missing on non-secure HTTP hosts (e.g. http://dev1:4002)
 * and its Promise can hang on a permission prompt. Prefer synchronous
 * execCommand while we still have the click gesture; use the Clipboard API
 * only as a short-timeout backup.
 */
export function copyText(text) {
  if (copyWithExecCommand(text)) {
    return Promise.resolve()
  }

  if (navigator.clipboard?.writeText) {
    return Promise.race([
      navigator.clipboard.writeText(text),
      new Promise((_resolve, reject) => {
        window.setTimeout(() => reject(new Error("clipboard timeout")), 500)
      }),
    ])
  }

  return Promise.reject(new Error("copy failed"))
}

function copyWithExecCommand(text) {
  const active = document.activeElement
  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.setAttribute("aria-hidden", "true")
  textarea.style.fontSize = "12pt"
  textarea.style.position = "fixed"
  textarea.style.top = "0"
  textarea.style.left = "0"
  textarea.style.width = "1px"
  textarea.style.height = "1px"
  textarea.style.opacity = "0"
  textarea.style.padding = "0"
  textarea.style.border = "0"
  textarea.style.writingMode = "horizontal-tb"

  document.body.appendChild(textarea)
  textarea.focus({preventScroll: true})
  textarea.select()
  textarea.setSelectionRange(0, text.length)

  let ok = false
  try {
    ok = document.execCommand("copy")
  } catch {
    ok = false
  }

  textarea.remove()
  if (active instanceof HTMLElement) active.focus({preventScroll: true})
  return ok
}
