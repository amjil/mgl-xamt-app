/**
 * Shared candidate provider for every mgl-web-ime instance on the page.
 *
 * Typing hits the remote backend when a base URL is configured. The vendored
 * RemoteCandidateProvider swallows network errors, so a dead backend would
 * otherwise cost a full timeout on every keystroke — three consecutive
 * timeouts trip the circuit for the session (reset when the browser comes
 * back online).
 */
import {
  CandidateProvider,
  LocalCandidateProvider,
  RemoteCandidateProvider,
} from "../../vendor/mgl-web-ime/mgl-web-ime.js"

const DEFAULT_IME_BASE_URL = "http://dev1:3003"
const REMOTE_TIMEOUT_MS = 800
const FAILURES_BEFORE_TRIP = 3

export function imeBaseUrl() {
  const meta = document.querySelector('meta[name="ime-base-url"]')
  const raw = (meta?.getAttribute("content") || DEFAULT_IME_BASE_URL).trim()
  if (!raw || raw === "local") return ""
  const withScheme = /^https?:\/\//i.test(raw) ? raw : `http://${raw}`
  return withScheme.replace(/\/+$/, "")
}

class GatedRemoteProvider extends CandidateProvider {
  constructor(baseUrl) {
    super()
    this.baseUrl = baseUrl.replace(/\/+$/, "")
    this.local = new LocalCandidateProvider()
    this.remote = new RemoteCandidateProvider({
      baseUrl: this.baseUrl,
      timeoutMs: REMOTE_TIMEOUT_MS,
    })
    this._failures = 0
    this._open = false
    this._onOnline = () => this.reset()
    window.addEventListener("online", this._onOnline)
  }

  reset() {
    this._open = false
    this._failures = 0
  }

  _noteFailure() {
    this._failures += 1
    if (this._failures >= FAILURES_BEFORE_TRIP) this._open = true
  }

  async getCandidates(input, context = {}) {
    if (this._open || navigator.onLine === false) {
      return this.local.getCandidates(input, context)
    }

    const started = performance.now()
    const words = await this.remote.getCandidates(input, context)
    if (words.length) {
      this._failures = 0
      return words
    }

    // Empty list after ~timeout is almost certainly a dead backend
    if (performance.now() - started >= REMOTE_TIMEOUT_MS - 50) {
      this._noteFailure()
    }

    return this.local.getCandidates(input, context)
  }

  async getNextWords(word) {
    if (this._open || navigator.onLine === false) return []
    return this.remote.getNextWords(word)
  }
}

let shared = null

/**
 * One provider for the whole page so the candidate cache and circuit state
 * are shared between the composer and plain inputs.
 */
export function imeProvider() {
  if (!shared) {
    const baseUrl = imeBaseUrl()
    shared = baseUrl ? new GatedRemoteProvider(baseUrl) : new LocalCandidateProvider()
  }
  return shared
}

/**
 * `<mgl-ime>` builds its own provider from a `base-url` attribute, which the
 * controller-rendered pages cannot configure. Swap ours in after upgrade.
 */
export function adoptImeElements(root = document) {
  root.querySelectorAll("mgl-ime").forEach((el) => {
    el.ime?.core?.setProvider?.(imeProvider())
  })
}
