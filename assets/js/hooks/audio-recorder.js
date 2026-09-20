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

function setRecordingState(btn, recording) {
  if (!btn) return
  btn.classList.toggle("is-recording", recording)
  btn.setAttribute("aria-pressed", recording ? "true" : "false")
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
    this._unmounted = false
    this.recordBtn = this.el.querySelector("#btn-record")

    this._onClick = () => {
      if (this.isRecording) {
        this.stopRecording()
        return
      }

      this.prepareAudioContext()
      this.startInAppRecording().then((started) => {
        setRecordingState(this.recordBtn, started)
      })
    }

    this.recordBtn?.addEventListener("click", this._onClick)
  },

  destroyed() {
    this._unmounted = true
    this.recordBtn?.removeEventListener("click", this._onClick)
    this.stopRecording()
    if (this.audioCtx) {
      this.audioCtx.close()
      this.audioCtx = null
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
    setRecordingState(this.recordBtn, false)

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
      return
    }

    const type = (mimeType || blob.type || "audio/webm").split(";")[0]
    const ext = extensionFor(type)
    this.uploadFile(blobToFile(blob, `voice_${Date.now()}.${ext}`, type))
  },

  uploadFile(file) {
    this.upload("audio", [file])
    requestAnimationFrame(() => {
      this.el.requestSubmit()
    })
  },
}
