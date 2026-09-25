import { toast } from "../utils/offline-store.js"

const MIME_CANDIDATES = [
  "audio/webm;codecs=opus",
  "audio/webm",
  "audio/mp4",
  "audio/mp4;codecs=mp4a.40.2",
  "audio/aac",
  "audio/ogg;codecs=opus",
  "video/webm;codecs=opus",
  "video/mp4",
]

const DEFAULT_MAX_SECONDS = 60

function resolveGetUserMedia() {
  const devices = navigator.mediaDevices
  if (devices && typeof devices.getUserMedia === "function") {
    return (constraints) => devices.getUserMedia(constraints)
  }

  const legacy =
    navigator.webkitGetUserMedia || navigator.mozGetUserMedia || navigator.getUserMedia
  if (typeof legacy === "function") {
    return (constraints) =>
      new Promise((resolve, reject) => legacy.call(navigator, constraints, resolve, reject))
  }

  return null
}

function pickMimeType() {
  const Recorder = window.MediaRecorder
  if (typeof Recorder === "undefined" || typeof Recorder.isTypeSupported !== "function") {
    return ""
  }

  return MIME_CANDIDATES.find((type) => Recorder.isTypeSupported(type)) || ""
}

function extensionFor(mime) {
  const type = mime || ""
  if (type.includes("mp4") || type.includes("m4a") || type.includes("aac") || type.includes("3gpp")) {
    return "mp4"
  }
  if (type.includes("mpeg") || type.includes("mp3")) return "mp3"
  if (type.includes("ogg")) return "ogg"
  if (type.includes("wav")) return "wav"
  return "webm"
}

function blobToFile(blob, filename, mime) {
  const type = mime || blob.type || "application/octet-stream"
  try {
    return new File([blob], filename, { type })
  } catch (_err) {
    blob.name = filename
    blob.lastModifiedDate = new Date()
    return blob
  }
}

function writeString(view, offset, string) {
  for (let i = 0; i < string.length; i++) {
    view.setUint8(offset + i, string.charCodeAt(i))
  }
}

function encodeWav(samples, sampleRate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2)
  const view = new DataView(buffer)

  writeString(view, 0, "RIFF")
  view.setUint32(4, 36 + samples.length * 2, true)
  writeString(view, 8, "WAVE")
  writeString(view, 12, "fmt ")
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * 2, true)
  view.setUint16(32, 2, true)
  view.setUint16(34, 16, true)
  writeString(view, 36, "data")
  view.setUint32(40, samples.length * 2, true)

  let index = 44
  for (let i = 0; i < samples.length; i++, index += 2) {
    const s = Math.max(-1, Math.min(1, samples[i]))
    view.setInt16(index, s < 0 ? s * 0x8000 : s * 0x7fff, true)
  }

  return new Blob([buffer], { type: "audio/wav" })
}

function mergeFloat32(buffers) {
  const length = buffers.reduce((sum, chunk) => sum + chunk.length, 0)
  const result = new Float32Array(length)
  let offset = 0
  for (const chunk of buffers) {
    result.set(chunk, offset)
    offset += chunk.length
  }
  return result
}

function formatCountdown(seconds) {
  const total = Math.max(0, Math.ceil(seconds))
  const minutes = Math.floor(total / 60)
  const rest = total % 60
  return `${minutes}:${String(rest).padStart(2, "0")}`
}

function insecurePage() {
  return window.isSecureContext === false
}

export const AudioRecorder = {
  mounted() {
    this.chunks = []
    this.mediaRecorder = null
    this.wavRecorder = null
    this.audioCtx = null
    this.isRecording = false
    this.sending = false
    this.pendingFile = null
    this.previewUrl = null
    this.timerId = null
    this.deadlineAt = 0
    this._unmounted = false
    this._awaitingAck = false
    this._ackTimer = null

    this.chrome = this.el.querySelector("#voice-chrome")
    this.panel = this.el.querySelector("#voice-panel")
    this.countdownValue = this.el.querySelector("#voice-countdown-value")
    this.recordBtn = this.el.querySelector("#btn-record")
    this.previewEl = this.el.querySelector("#voice-preview")
    this.sendBtn = this.el.querySelector("#btn-voice-send")
    this.discardBtn = this.el.querySelector("#btn-voice-discard")

    this._onClick = () => {
      if (this.sending) return
      if (this.isRecording) {
        this.stopRecording()
        return
      }
      if (this.pendingFile) return

      this.prepareAudioContext()
      this.startInAppRecording().then((started) => {
        this.setRecordingState(started)
      })
    }

    this._onSend = () => this.sendPending()
    this._onDiscard = () => this.discardPending()

    this.recordBtn?.addEventListener("click", this._onClick)
    this.sendBtn?.addEventListener("click", this._onSend)
    this.discardBtn?.addEventListener("click", this._onDiscard)
    this.handleEvent("voice:sent", () => this.onVoiceSent())
    this.handleEvent("voice:failed", () => this.onVoiceFailed())
    this.setPanelState("idle")
  },

  destroyed() {
    this._unmounted = true
    this.clearAckTimer()
    this.recordBtn?.removeEventListener("click", this._onClick)
    this.sendBtn?.removeEventListener("click", this._onSend)
    this.discardBtn?.removeEventListener("click", this._onDiscard)
    this.stopRecording()
    this.discardPending({ silent: true })
    if (this.audioCtx) {
      this.audioCtx.close()
      this.audioCtx = null
    }
  },

  maxSeconds() {
    const n = Number(this.el.dataset.maxSeconds)
    return Number.isFinite(n) && n > 0 ? n : DEFAULT_MAX_SECONDS
  },

  setVoiceActive(active) {
    this.chrome?.classList.toggle("is-voice-active", active)
  },

  setPanelState(state) {
    if (this.panel) this.panel.dataset.state = state
    this.setVoiceActive(state === "recording" || state === "review")
    this.recordBtn?.classList.toggle("is-reviewing", state === "review")
    this.recordBtn?.toggleAttribute("disabled", state === "review" || this.sending)
  },

  setRecordingState(recording) {
    if (!this.recordBtn) return
    this.recordBtn.classList.toggle("is-recording", recording)
    this.recordBtn.setAttribute("aria-pressed", recording ? "true" : "false")
    const label = recording
      ? this.el.dataset.stopLabel || "Stop recording"
      : this.el.dataset.recordLabel || "Record voice message"
    this.recordBtn.setAttribute("aria-label", label)
    this.recordBtn.setAttribute("title", label)
  },

  setReviewBusy(busy) {
    this.sendBtn?.toggleAttribute("disabled", busy)
    this.discardBtn?.toggleAttribute("disabled", busy)
    this.recordBtn?.toggleAttribute("disabled", busy || this.panel?.dataset.state === "review")
  },

  startCountdown() {
    this.clearCountdown()
    const max = this.maxSeconds()
    this.deadlineAt = Date.now() + max * 1000
    this.renderCountdown(max)
    this.setPanelState("recording")
    this.timerId = window.setInterval(() => {
      const remaining = Math.max(0, (this.deadlineAt - Date.now()) / 1000)
      this.renderCountdown(remaining)
      if (remaining <= 0) this.stopRecording()
    }, 200)
  },

  renderCountdown(seconds) {
    if (this.countdownValue) this.countdownValue.textContent = formatCountdown(seconds)
    const max = this.maxSeconds()
    this.el.style.setProperty("--voice-remain", String(Math.max(0, Math.min(1, seconds / max))))
  },

  clearCountdown() {
    if (this.timerId) {
      window.clearInterval(this.timerId)
      this.timerId = null
    }
  },

  prepareAudioContext() {
    const Ctor = window.AudioContext || window.webkitAudioContext
    if (!Ctor) return
    if (!this.audioCtx) this.audioCtx = new Ctor()
    if (this.audioCtx.state === "suspended") this.audioCtx.resume()
  },

  unsupportedMessage() {
    if (insecurePage()) {
      return (
        this.el.dataset.micInsecure ||
        "Voice recording needs HTTPS. Open this page with https:// on this phone."
      )
    }

    return this.el.dataset.micUnsupported || "Voice recording is not supported in this browser"
  },

  async startInAppRecording() {
    const getUserMedia = resolveGetUserMedia()
    if (!getUserMedia) {
      toast("error", this.unsupportedMessage())
      return false
    }

    return this.startRecording(getUserMedia)
  },

  async acquireMic(getUserMedia) {
    try {
      return await getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: false,
      })
    } catch (err) {
      if (err?.name === "OverconstrainedError" || err?.name === "ConstraintNotSatisfiedError") {
        return getUserMedia({ audio: true })
      }

      throw err
    }
  },

  async startRecording(getUserMedia) {
    try {
      const stream = await this.acquireMic(getUserMedia)
      if (this._unmounted) {
        stream.getTracks().forEach((track) => track.stop())
        return false
      }

      const started = this.startMediaRecorder(stream) || this.startWavRecorder(stream)
      if (!started) {
        stream.getTracks().forEach((track) => track.stop())
        toast("error", this.unsupportedMessage())
        return false
      }

      this.isRecording = true
      this.startCountdown()
      return true
    } catch (err) {
      console.error("Microphone access failed:", err)
      if (insecurePage()) {
        toast("error", this.unsupportedMessage())
        return false
      }

      if (err?.name === "NotAllowedError" || err?.name === "PermissionDeniedError") {
        toast("error", this.el.dataset.micError || "Microphone access is required to record")
        return false
      }

      toast("error", this.unsupportedMessage())
      return false
    }
  },

  startMediaRecorder(stream) {
    const Recorder = window.MediaRecorder
    if (typeof Recorder === "undefined") return false

    try {
      const mimeType = pickMimeType()
      const recorder = mimeType ? new Recorder(stream, { mimeType }) : new Recorder(stream)
      this.chunks = []
      this.mediaRecorder = recorder
      this.wavRecorder = null

      recorder.ondataavailable = (e) => {
        if (e.data && e.data.size > 0) this.chunks.push(e.data)
      }
      recorder.onstop = () => this.processMediaRecorder()
      // timeslice on iOS Safari often yields an empty blob
      recorder.start()
      return true
    } catch (_err) {
      return false
    }
  },

  startWavRecorder(stream) {
    const ctx = this.audioCtx
    if (!ctx) return false

    try {
      if (ctx.state === "suspended") ctx.resume()
      const source = ctx.createMediaStreamSource(stream)
      const processor = ctx.createScriptProcessor(4096, 1, 1)
      const mute = ctx.createGain()
      mute.gain.value = 0
      const buffers = []

      processor.onaudioprocess = (e) => {
        if (!this.isRecording) return
        buffers.push(new Float32Array(e.inputBuffer.getChannelData(0)))
      }

      source.connect(processor)
      processor.connect(mute)
      mute.connect(ctx.destination)

      this.mediaRecorder = null
      this.wavRecorder = { stream, source, processor, mute, buffers, sampleRate: ctx.sampleRate }
      return true
    } catch (_err) {
      return false
    }
  },

  stopRecording() {
    if (!this.isRecording) return
    this.isRecording = false
    this.clearCountdown()
    this.setRecordingState(false)

    if (this.mediaRecorder && this.mediaRecorder.state !== "inactive") {
      this.mediaRecorder.stop()
      return
    }

    if (this.wavRecorder) this.processWavRecorder()
  },

  processMediaRecorder() {
    const stream = this.mediaRecorder?.stream
    stream?.getTracks().forEach((track) => track.stop())

    const mimeType = this.mediaRecorder?.mimeType || this.chunks[0]?.type || "audio/webm"
    const blob = new Blob(this.chunks, { type: mimeType.split(";")[0] })
    this.chunks = []
    this.mediaRecorder = null
    this.processBlob(blob, mimeType)
  },

  processWavRecorder() {
    const rec = this.wavRecorder
    this.wavRecorder = null
    if (!rec) return

    rec.processor.disconnect()
    rec.source.disconnect()
    rec.mute.disconnect()
    rec.stream.getTracks().forEach((track) => track.stop())

    const blob = encodeWav(mergeFloat32(rec.buffers), rec.sampleRate)
    this.processBlob(blob, "audio/wav")
  },

  processBlob(blob, mimeType) {
    if (this._unmounted) return

    if (!blob || blob.size === 0) {
      toast("error", this.el.dataset.micEmpty || "Recording was empty")
      this.resetVoiceUi()
      return
    }

    const type = (mimeType || blob.type || "audio/webm").split(";")[0]
    const ext = extensionFor(type)
    this.pendingFile = blobToFile(blob, `voice_${Date.now()}.${ext}`, type)
    this.revokePreview()
    this.previewUrl = URL.createObjectURL(blob)
    if (this.previewEl) {
      this.previewEl.src = this.previewUrl
      this.previewEl.currentTime = 0
    }

    this.setPanelState("review")
    this.setReviewBusy(false)
  },

  sendPending() {
    if (!this.pendingFile || this.sending || this._unmounted) return
    this.sending = true
    this.setReviewBusy(true)
    if (this.previewEl) this.previewEl.pause()
    this.uploadFile(this.pendingFile)
  },

  discardPending(opts = {}) {
    this.clearCountdown()
    this.clearAckTimer()
    this._awaitingAck = false
    if (this.previewEl) {
      this.previewEl.pause()
      this.previewEl.removeAttribute("src")
      this.previewEl.load()
    }
    this.revokePreview()
    this.pendingFile = null
    this.sending = false
    if (!opts.silent) this.resetVoiceUi()
  },

  onVoiceSent() {
    if (this._unmounted) return
    this._awaitingAck = false
    this.clearAckTimer()
    this.discardPending()
  },

  onVoiceFailed() {
    if (this._unmounted) return
    this._awaitingAck = false
    this.clearAckTimer()
    this.sending = false
    this.setReviewBusy(false)
    this.setPanelState("review")
  },

  clearAckTimer() {
    if (this._ackTimer) {
      window.clearTimeout(this._ackTimer)
      this._ackTimer = null
    }
  },

  awaitVoiceAck() {
    this.clearAckTimer()
    this._awaitingAck = true
    this._ackTimer = window.setTimeout(() => {
      if (!this._awaitingAck || this._unmounted) return
      this._awaitingAck = false
      this.sending = false
      this.setReviewBusy(false)
      this.setPanelState("review")
      toast("error", this.el.dataset.micUploadError || "Could not upload voice message")
    }, 30000)
  },

  revokePreview() {
    if (this.previewUrl) {
      URL.revokeObjectURL(this.previewUrl)
      this.previewUrl = null
    }
  },

  resetVoiceUi() {
    this.sending = false
    this.setReviewBusy(false)
    this.setRecordingState(false)
    this.setPanelState("idle")
    this.el.style.removeProperty("--voice-remain")
  },

  uploadFile(file) {
    this.upload("audio", [file])
    // LiveView auto_upload starts on the change event; submit once the
    // entry is done so a slow nginx/Tailscale hop cannot crash the LV
    // by consuming an in-progress upload.
    this.submitWhenUploaded()
  },

  submitWhenUploaded() {
    const input = this.el.querySelector("input[data-phx-upload-ref]")
    if (!input) {
      toast("error", this.el.dataset.micEmpty || "Recording was empty")
      this.sending = false
      this.setReviewBusy(false)
      return
    }

    let tries = 0
    const maxTries = 600

    const tick = () => {
      if (this._unmounted) return
      tries += 1

      const active = refsOf(input, "data-phx-active-refs")
      const done = refsOf(input, "data-phx-done-refs")
      const pre = refsOf(input, "data-phx-preflighted-refs")

      if (active.length > 0 && active.every((ref) => done.includes(ref))) {
        // Keep pendingFile until voice:sent — failed/cancelled submits can retry.
        this.el.requestSubmit()
        this.awaitVoiceAck()
        return
      }

      // Preflight finished but entry never completed (rejected / cancelled).
      if (tries > 15 && pre.length > 0 && done.length === 0 && active.length === 0) {
        toast("error", this.el.dataset.micUploadError || "Could not upload voice message")
        this.sending = false
        this.setReviewBusy(false)
        return
      }

      if (tries >= maxTries) {
        toast("error", this.el.dataset.micUploadError || "Could not upload voice message")
        this.sending = false
        this.setReviewBusy(false)
        return
      }

      setTimeout(tick, 100)
    }

    // First paint may still be awaiting LiveView's upload ref attributes.
    requestAnimationFrame(() => setTimeout(tick, 50))
  },
}

function refsOf(input, attr) {
  return (input.getAttribute(attr) || "").split(",").map((s) => s.trim()).filter(Boolean)
}
