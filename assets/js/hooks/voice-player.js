let currentPlayer = null

const PLAYED_PREFIX = "xamt:voice-played:"

function clampDuration(value) {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return null
  return Math.max(1, Math.min(60, Math.round(n)))
}

function playedKey(messageId) {
  return `${PLAYED_PREFIX}${messageId}`
}

function hasPlayed(messageId) {
  if (!messageId) return false
  try {
    return localStorage.getItem(playedKey(messageId)) === "1"
  } catch (_err) {
    return false
  }
}

function markPlayed(messageId) {
  if (!messageId) return
  try {
    localStorage.setItem(playedKey(messageId), "1")
  } catch (_err) {
    // Ignore quota / private-mode failures; UI still updates for this session.
  }
}

export const VoicePlayer = {
  mounted() {
    this.audio = this.el.querySelector("audio")
    this.button = this.el.querySelector("button")
    this.playing = false
    this.messageId = this.el.dataset.messageId || ""
    this.own = this.el.dataset.own === "true"

    this._onClick = () => this.toggle()
    this._onEnded = () => this.stop({ reset: true })
    this._onTimeUpdate = () => this.syncProgress()
    this._onMeta = () => this.applyMeasuredDuration()

    this.button?.addEventListener("click", this._onClick)
    this.audio?.addEventListener("ended", this._onEnded)
    this.audio?.addEventListener("timeupdate", this._onTimeUpdate)
    this.audio?.addEventListener("loadedmetadata", this._onMeta)
    this.audio?.addEventListener("durationchange", this._onMeta)

    this.applyServerDuration()
    this.applyMeasuredDuration()
    this.syncPlayedUi()
    this.setPlaying(false)
  },

  destroyed() {
    if (currentPlayer === this) currentPlayer = null
    this.button?.removeEventListener("click", this._onClick)
    this.audio?.removeEventListener("ended", this._onEnded)
    this.audio?.removeEventListener("timeupdate", this._onTimeUpdate)
    this.audio?.removeEventListener("loadedmetadata", this._onMeta)
    this.audio?.removeEventListener("durationchange", this._onMeta)
    if (this.audio) {
      this.audio.pause()
      this.audio.currentTime = 0
    }
  },

  applyServerDuration() {
    const seconds = clampDuration(this.el.dataset.duration)
    if (seconds) this.el.style.setProperty("--voice-duration", String(seconds))
  },

  applyMeasuredDuration() {
    if (clampDuration(this.el.dataset.duration)) return
    const seconds = clampDuration(this.audio?.duration)
    if (seconds) this.el.style.setProperty("--voice-duration", String(seconds))
  },

  syncPlayedUi() {
    if (this.own || hasPlayed(this.messageId)) {
      this.el.classList.add("is-played")
    }
  },

  markAsPlayed() {
    if (this.own) return
    markPlayed(this.messageId)
    this.el.classList.add("is-played")
  },

  toggle() {
    if (this.playing) {
      this.stop({ reset: true })
      return
    }
    this.play()
  },

  play() {
    if (!this.audio) return
    if (currentPlayer && currentPlayer !== this) {
      currentPlayer.stop({ reset: true })
    }

    currentPlayer = this
    const start = this.audio.play()
    if (start && typeof start.then === "function") {
      start
        .then(() => {
          this.markAsPlayed()
          this.setPlaying(true)
          this.syncProgress()
        })
        .catch(() => this.stop({ reset: true }))
      return
    }

    this.markAsPlayed()
    this.setPlaying(true)
    this.syncProgress()
  },

  stop(opts = {}) {
    if (this.audio) {
      this.audio.pause()
      if (opts.reset) this.audio.currentTime = 0
    }
    if (currentPlayer === this) currentPlayer = null
    this.setPlaying(false)
    this.el.style.setProperty("--voice-progress", "0")
  },

  syncProgress() {
    if (!this.audio || !this.playing) return
    const duration = this.audio.duration
    if (!Number.isFinite(duration) || duration <= 0) return
    const ratio = Math.max(0, Math.min(1, this.audio.currentTime / duration))
    this.el.style.setProperty("--voice-progress", String(ratio))
  },

  setPlaying(playing) {
    this.playing = playing
    this.button?.classList.toggle("is-playing", playing)
    this.button?.setAttribute("aria-pressed", playing ? "true" : "false")
    const label = playing
      ? this.el.dataset.stopLabel || "Stop voice message"
      : this.el.dataset.playLabel || "Play voice message"
    this.button?.setAttribute("aria-label", label)
    this.button?.setAttribute("title", label)
  },
}
