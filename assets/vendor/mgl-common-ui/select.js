/**
 * Vertical-lr select UI. Native <select> popups ignore writing-mode and open
 * as a horizontal OS menu — this keeps the option list in the same vertical
 * column as the field.
 *
 *   enhanceSelect(nativeSelect)
 *   <mn-select name="…" value="…"><option …></option></mn-select>
 *
 * For LiveView, wrap the <select> in an element with phx-update="ignore" and
 * call enhanceSelect from a hook on that wrapper (or on the select).
 */

const HOST_CLASS = "mn-select-host"
const OPEN_CLASS = "mn-select-host--open"

/**
 * @typedef {{ destroy: () => void, sync: () => void, open: () => void, close: () => void }} MnSelectApi
 */

/**
 * Enhance a native <select> with a vertical-lr listbox.
 * Keeps the <select> in the DOM (visually hidden) so forms / LiveView still see it.
 *
 * If the select's parent already has `.mn-select-host`, that node is reused
 * (preferred for LiveView wrappers).
 *
 * @param {HTMLSelectElement} select
 * @returns {MnSelectApi}
 */
export function enhanceSelect(select) {
  if (!(select instanceof HTMLSelectElement)) return noopApi()
  if (select.dataset.mnSelect === "on") return select._mnSelectApi || noopApi()

  const parent = select.parentNode
  const reuseHost = parent instanceof HTMLElement && parent.classList.contains(HOST_CLASS)
  const host = reuseHost ? parent : document.createElement("div")

  if (!reuseHost) {
    host.className = HOST_CLASS
    parent.insertBefore(host, select)
    host.appendChild(select)
  }

  const trigger = document.createElement("button")
  trigger.type = "button"
  trigger.className = "mn-select-trigger"
  trigger.setAttribute("aria-haspopup", "listbox")
  trigger.setAttribute("aria-expanded", "false")
  Object.assign(trigger.style, {
    display: "flex",
    flexDirection: "row",
    justifyContent: "flex-start",
    alignItems: "flex-start",
    alignContent: "flex-start",
    textAlign: "start",
    boxSizing: "border-box",
  })
  if (select.id) trigger.id = `${select.id}__trigger`

  const list = document.createElement("ul")
  list.className = "mn-select-list"
  list.setAttribute("role", "listbox")
  list.tabIndex = -1
  list.hidden = true
  // Inline layout beats stale/cached stylesheets: options run left→right.
  Object.assign(list.style, {
    display: "flex",
    flexDirection: "row",
    flexWrap: "nowrap",
    alignItems: "stretch",
    gap: "0.25rem",
    writingMode: "horizontal-tb",
    overflowX: "auto",
    overflowY: "hidden",
    position: "absolute",
    zIndex: "30",
    top: "0",
    left: "100%",
    right: "auto",
    bottom: "auto",
    margin: "0 0 0 0.35rem",
    padding: "0.35rem",
    listStyle: "none",
    boxSizing: "border-box",
    height: "min(18rem, calc(100dvh - 4rem))",
    maxWidth: "min(22rem, calc(100vw - 1.5rem))",
  })
  if (select.id) {
    list.id = `${select.id}__list`
    trigger.setAttribute("aria-controls", list.id)
  }

  host.appendChild(trigger)
  host.appendChild(list)

  select.classList.add("mn-select-native")
  select.dataset.mnSelect = "on"
  select.setAttribute("tabindex", "-1")
  select.setAttribute("aria-hidden", "true")

  let open = false
  /** @type {string|null} */
  let activeValue = null
  const margin = 8

  const syncHostClasses = () => {
    const extra = Array.from(select.classList).filter((c) => c !== "mn-select-native")
    const base = [HOST_CLASS, open ? OPEN_CLASS : "", ...extra].filter(Boolean)
    // Keep any host-only classes the app may have set (aside from state).
    for (const c of Array.from(host.classList)) {
      if (c === OPEN_CLASS || c === HOST_CLASS || extra.includes(c) || c === "mn-select-native") continue
      if (!base.includes(c)) base.push(c)
    }
    host.className = base.join(" ")
  }

  /**
   * Prefer opening to the physical right of the trigger. If that side is tight,
   * flip left. If the list would fall off the bottom, align to the bottom edge.
   */
  const positionList = () => {
    list.classList.remove("mn-select-list--flip-block", "mn-select-list--flip-inline")
    // Reset to prefer opening on the physical right.
    list.style.left = "100%"
    list.style.right = "auto"
    list.style.top = "0"
    list.style.bottom = "auto"
    list.style.margin = "0 0 0 0.35rem"
    void list.offsetWidth

    const hostRect = host.getBoundingClientRect()
    const listRect = list.getBoundingClientRect()
    const vw = window.innerWidth
    const vh = window.innerHeight

    const spaceRight = vw - hostRect.right
    const spaceLeft = hostRect.left
    const flipBlock = listRect.width + margin > spaceRight && spaceLeft > spaceRight

    if (flipBlock) {
      list.classList.add("mn-select-list--flip-block")
      list.style.left = "auto"
      list.style.right = "100%"
      list.style.margin = "0 0.35rem 0 0"
      void list.offsetWidth
    }

    const placed = list.getBoundingClientRect()
    const spaceBelow = vh - hostRect.top
    const flipInline = placed.height + margin > spaceBelow && hostRect.bottom > placed.height

    if (flipInline) {
      list.classList.add("mn-select-list--flip-inline")
      list.style.top = "auto"
      list.style.bottom = "0"
    }
  }

  const selectedLabel = () => {
    const opt = select.selectedOptions[0]
    return opt ? (opt.textContent ?? "") : ""
  }

  const rebuildOptions = () => {
    const frag = document.createDocumentFragment()
    for (const opt of Array.from(select.options)) {
      const li = document.createElement("li")
      li.className = "mn-select-option"
      li.setAttribute("role", "option")
      li.dataset.value = opt.value
      li.textContent = opt.textContent ?? ""
      Object.assign(li.style, {
        writingMode: "vertical-lr",
        textOrientation: "mixed",
        flex: "0 0 auto",
        height: "100%",
        whiteSpace: "nowrap",
        boxSizing: "border-box",
        cursor: "pointer",
      })
      const selected = opt.selected
      li.setAttribute("aria-selected", String(selected))
      if (selected) li.classList.add("mn-select-option--selected")
      if (opt.disabled) {
        li.setAttribute("aria-disabled", "true")
        li.classList.add("mn-select-option--disabled")
      }
      frag.appendChild(li)
    }
    list.replaceChildren(frag)
  }

  const sync = () => {
    rebuildOptions()
    trigger.textContent = selectedLabel()
    trigger.disabled = select.disabled
    host.toggleAttribute("aria-disabled", select.disabled)
    activeValue = select.value
    markActive()
    syncHostClasses()
  }

  const markActive = () => {
    for (const li of list.querySelectorAll('[role="option"]')) {
      const on = li.dataset.value === activeValue
      li.classList.toggle("mn-select-option--active", on)
      if (on) li.id = `${list.id || "mn-select"}__active`
    }
    const activeId = list.querySelector(".mn-select-option--active")?.id
    if (activeId) trigger.setAttribute("aria-activedescendant", activeId)
    else trigger.removeAttribute("aria-activedescendant")
  }

  const enabledOptions = () =>
    Array.from(list.querySelectorAll('[role="option"]:not([aria-disabled="true"])'))

  const setOpen = (next) => {
    if (select.disabled) next = false
    open = next
    list.hidden = !open
    trigger.setAttribute("aria-expanded", String(open))
    syncHostClasses()
    if (open) {
      activeValue = select.value
      markActive()
      positionList()
      list.querySelector(".mn-select-option--active")?.scrollIntoView?.({
        block: "nearest",
        inline: "nearest",
      })
    } else {
      list.classList.remove("mn-select-list--flip-block", "mn-select-list--flip-inline")
    }
  }

  const onViewportChange = () => {
    if (open) positionList()
  }

  const choose = (value) => {
    const changed = select.value !== value
    if (changed) {
      select.value = value
      select.dispatchEvent(new Event("input", {bubbles: true}))
      select.dispatchEvent(new Event("change", {bubbles: true}))
    }
    sync()
    setOpen(false)
    trigger.focus()
  }

  const moveActive = (delta) => {
    const options = enabledOptions()
    if (options.length === 0) return
    const idx = Math.max(
      0,
      options.findIndex((el) => el.dataset.value === activeValue)
    )
    const next = options[(idx + delta + options.length) % options.length]
    activeValue = next.dataset.value ?? ""
    markActive()
    next.scrollIntoView?.({block: "nearest", inline: "nearest"})
  }

  const onTriggerClick = (event) => {
    event.preventDefault()
    event.stopPropagation()
    setOpen(!open)
  }

  const onListClick = (event) => {
    const option = event.target?.closest?.("[role='option']")
    if (!option || option.getAttribute("aria-disabled") === "true") return
    event.preventDefault()
    choose(option.dataset.value ?? "")
  }

  const onDocPointer = (event) => {
    if (!open) return
    if (host.contains(/** @type {Node} */ (event.target))) return
    setOpen(false)
  }

  const onKey = (event) => {
    const nextKeys = event.key === "ArrowDown" || event.key === "ArrowRight"
    const prevKeys = event.key === "ArrowUp" || event.key === "ArrowLeft"
    const keysOpen = nextKeys || prevKeys || event.key === "Enter" || event.key === " "
    if (!open) {
      if (event.target === trigger && keysOpen) {
        event.preventDefault()
        setOpen(true)
        if (prevKeys) moveActive(-1)
        if (nextKeys) moveActive(1)
      }
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      setOpen(false)
      trigger.focus()
      return
    }
    if (nextKeys) {
      event.preventDefault()
      moveActive(1)
      return
    }
    if (prevKeys) {
      event.preventDefault()
      moveActive(-1)
      return
    }
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      choose(activeValue ?? select.value)
    }
  }

  trigger.addEventListener("click", onTriggerClick)
  list.addEventListener("click", onListClick)
  document.addEventListener("pointerdown", onDocPointer, true)
  window.addEventListener("resize", onViewportChange)
  window.addEventListener("scroll", onViewportChange, true)
  host.addEventListener("keydown", onKey)

  sync()

  const api = {
    sync,
    open: () => setOpen(true),
    close: () => setOpen(false),
    destroy() {
      setOpen(false)
      trigger.removeEventListener("click", onTriggerClick)
      list.removeEventListener("click", onListClick)
      document.removeEventListener("pointerdown", onDocPointer, true)
      window.removeEventListener("resize", onViewportChange)
      window.removeEventListener("scroll", onViewportChange, true)
      host.removeEventListener("keydown", onKey)
      trigger.remove()
      list.remove()
      select.classList.remove("mn-select-native")
      select.removeAttribute("tabindex")
      select.removeAttribute("aria-hidden")
      delete select.dataset.mnSelect
      delete select._mnSelectApi
      if (!reuseHost && host.parentNode) {
        host.parentNode.insertBefore(select, host)
        host.remove()
      }
    },
  }

  select._mnSelectApi = api
  return api
}

function noopApi() {
  return {destroy() {}, sync() {}, open() {}, close() {}}
}

const Base = typeof HTMLElement !== "undefined" ? HTMLElement : class {}

/**
 * Custom element wrapper. Light-DOM <option> children are moved into an
 * internal native <select>, then enhanced.
 */
export class MnSelect extends Base {
  static formAssociated = true

  constructor() {
    super()
    /** @type {ElementInternals|null} */
    this._internals = null
    if (typeof this.attachInternals === "function") {
      try {
        this._internals = this.attachInternals()
      } catch {
        this._internals = null
      }
    }
    /** @type {MnSelectApi|null} */
    this._api = null
    /** @type {HTMLSelectElement|null} */
    this._native = null
  }

  static get observedAttributes() {
    return ["name", "value", "disabled", "required"]
  }

  connectedCallback() {
    this.classList.add(HOST_CLASS, "mn-select")
    this._ensureNative()
    this._collectOptions()
    if (!this._api) this._api = enhanceSelect(this._native)
    this._api.sync()
    this._reflectValue()
  }

  disconnectedCallback() {
    this._api?.destroy()
    this._api = null
  }

  attributeChangedCallback(name, _old, value) {
    if (!this._native) return
    if (name === "name") this._native.name = value ?? ""
    if (name === "value" && value != null && this._native.value !== value) {
      this._native.value = value
      this._api?.sync()
      this._reflectValue()
    }
    if (name === "disabled") {
      this._native.disabled = this.hasAttribute("disabled")
      this._api?.sync()
    }
    if (name === "required") {
      this._native.required = this.hasAttribute("required")
    }
  }

  get value() {
    return this._native?.value ?? this.getAttribute("value") ?? ""
  }

  set value(v) {
    this.setAttribute("value", v == null ? "" : String(v))
  }

  get name() {
    return this.getAttribute("name") ?? ""
  }

  set name(v) {
    if (v == null) this.removeAttribute("name")
    else this.setAttribute("name", v)
  }

  /** Re-read light-DOM options after LiveView / host updates. */
  refresh() {
    this._collectOptions()
    this._api?.sync()
    this._reflectValue()
  }

  _ensureNative() {
    if (this._native) return
    const native = document.createElement("select")
    native.className = "mn-select"
    if (this.hasAttribute("name")) native.name = this.getAttribute("name") ?? ""
    native.disabled = this.hasAttribute("disabled")
    native.required = this.hasAttribute("required")
    if (this.id) native.id = `${this.id}__native`
    this.appendChild(native)
    this._native = native
    native.addEventListener("change", () => {
      this.setAttribute("value", native.value)
      this._reflectValue()
      this.dispatchEvent(new Event("change", {bubbles: true}))
      this.dispatchEvent(new Event("input", {bubbles: true}))
    })
  }

  _collectOptions() {
    if (!this._native) return
    const current = this.getAttribute("value")
    const options = Array.from(this.children).filter(
      (el) => el instanceof HTMLOptionElement && el.parentElement === this
    )

    if (options.length > 0) {
      this._native.replaceChildren()
      for (const opt of options) this._native.appendChild(opt)
    }

    if (current != null) this._native.value = current
  }

  _reflectValue() {
    const value = this._native?.value ?? ""
    this._internals?.setFormValue(value)
  }
}

export function defineMnSelect(tag = "mn-select") {
  if (typeof customElements === "undefined") return
  if (!customElements.get(tag)) customElements.define(tag, MnSelect)
}

defineMnSelect()
