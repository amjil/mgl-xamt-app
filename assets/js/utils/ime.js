/**
 * Shared candidate provider for every mgl-web-ime instance on the page.
 *
 * The vendored RemoteCandidateProvider swallows network errors and returns an
 * empty list, so an unreachable backend costs a full timeout on every lookup.
 * Typing always hits the local dictionary until a probe has confirmed the
 * remote is up; three consecutive remote failures trip it for the session.
 */
import {
  CandidateProvider,
  LocalCandidateProvider,
  RemoteCandidateProvider,
} from "../../vendor/mgl-web-ime/mgl-web-ime.js"

const REMOTE_TIMEOUT_MS = 800
const PROBE_TIMEOUT_MS = 800
const FAILURES_BEFORE_TRIP = 3

export function imeBaseUrl() {
  const meta = document.querySelector('meta[name="ime-base-url"]')
  return (meta?.getAttribute("content") || "").trim()
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
    this._ready = false
    this._probing = false
    this._failures = 0
    this._open = false
    this._onOnline = () => this.reset()
    window.addEventListener("online", this._onOnline)
    this._startProbe()
  }

  reset() {
    this._open = false
    this._ready = false
    this._failures = 0
    this._startProbe()
  }

  _startProbe() {
    if (this._open || this._probing || this._ready) return
    this._probing = true
    this._runProbe().finally(() => {
      this._probing = false
    })
  }

  async _runProbe() {
    if (navigator.onLine === false) {
      this._open = true
      this._ready = false
      return
    }

    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), PROBE_TIMEOUT_MS)
    try {
      const res = await fetch(`${this.baseUrl}/api/next_word/candidates`, {
        method: "POST",
        headers: {"Content-Type": "application/json; charset=UTF-8"},
        body: JSON.stringify({word: "ᠠ"}),
        signal: ctrl.signal,
      })
      if (res.ok) {
        this._failures = 0
        this._ready = true
        return
      }
      this._noteFailure()
    } catch {
      this._noteFailure()
    } finally {
      clearTimeout(timer)
    }
  }

  _noteFailure() {
    this._ready = false
    this._failures += 1
    if (this._failures >= FAILURES_BEFORE_TRIP) this._open = true
  }

  async getCandidates(input, context = {}) {
    if (!this._ready || this._open || navigator.onLine === false) {
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
    if (!this._ready || this._open) return []
    return this.remote.getNextWords(word)
  }
}

let shared = null

/**
 * One provider for the whole page so the candidate cache, reachability probe
 * and circuit state are shared between the composer and plain inputs.
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
