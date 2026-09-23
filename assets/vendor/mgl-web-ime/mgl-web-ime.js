// src/core/state.js
function createInitialState(overrides = {}) {
  return {
    enabled: true,
    mode: "mongol",
    profile: "desktop",
    composing: false,
    composition: "",
    preview: "",
    previewLen: 0,
    candidates: [],
    selectedCandidate: 0,
    pageIndex: 0,
    pageSize: 5,
    keyboardVisible: false,
    candidateVisible: false,
    pendingSuffixDelete: false,
    ...overrides
  };
}
function totalPages(state) {
  const c = state.candidates.length;
  const ps = state.pageSize || 5;
  if (!c) return 0;
  return Math.ceil(c / ps);
}
function pageCandidates(state) {
  const start = state.pageIndex * state.pageSize;
  return state.candidates.slice(start, start + state.pageSize);
}
function currentCandidate(state) {
  const idx = state.pageIndex * state.pageSize;
  return state.candidates[idx] ?? null;
}
function clearCompositionFields(state) {
  return {
    ...state,
    composing: false,
    composition: "",
    preview: "",
    previewLen: 0,
    candidates: [],
    selectedCandidate: 0,
    pageIndex: 0,
    candidateVisible: false,
    pendingSuffixDelete: false
  };
}

// src/core/mapping.js
var LATIN_TO_MONGOL = {
  a: "\u1820",
  e: "\u1821",
  i: "\u1822",
  c: "\u1823",
  // ᠣ
  v: "\u1824",
  // ᠤ
  o: "\u1825",
  // ᠥ
  u: "\u1826",
  // ᠦ
  n: "\u1828",
  b: "\u182A",
  p: "\u182B",
  h: "\u182C",
  g: "\u182D",
  m: "\u182E",
  l: "\u182F",
  s: "\u1830",
  x: "\u1831",
  t: "\u1832",
  d: "\u1833",
  q: "\u1834",
  j: "\u1835",
  k: "\u183A",
  y: "\u1836",
  r: "\u1837",
  w: "\u1838",
  z: "\u183D",
  // Uppercase (shift strokes)
  A: "\u1820",
  G: "\u182D",
  N: "\u1829",
  H: "\u183E",
  Q: "\u1842",
  C: "\u183C",
  R: "\u183F",
  Z: "\u1841",
  L: "\u1840",
  // MVS
  "-": "\u180E",
  "=": "\u180E",
  // FVS
  "[": "\u180B",
  "]": "\u180C",
  "\\": "\u180D",
  // Punctuation
  ",": "\u1802",
  ".": "\u1803",
  "?": "\uFF1F",
  "!": "\uFF01"
};
function translate(latinStr) {
  if (!latinStr) return "";
  let out = "";
  for (const ch of latinStr) {
    out += LATIN_TO_MONGOL[ch] ?? LATIN_TO_MONGOL[ch.toLowerCase()] ?? ch;
  }
  return out;
}
function directCharFromKey(ev) {
  if (ev.latinMode) return null;
  const { key, code, shiftKey } = ev;
  if (shiftKey && (key === " " || code === "Space")) return "\u202F";
  if (code === "BracketLeft" || key === "[") return "\u180B";
  if (code === "BracketRight" || key === "]") return "\u180C";
  if (code === "Backslash" || key === "\\") return "\u180D";
  if (key === "," || code === "Comma") return "\u1802";
  if (key === "." || code === "Period") return "\u1803";
  if (key === "?" || key === "\uFF1F" || code === "Slash" && shiftKey) {
    return "\uFF1F";
  }
  if (key === "!" || key === "\uFF01" || code === "Digit1" && shiftKey) {
    return "\uFF01";
  }
  return null;
}

// src/core/composition.js
function appendToBuffer(buffer, char) {
  const mapped = char === "+" ? "=" : char;
  return (buffer ?? "") + mapped;
}
function backspaceBuffer(buffer) {
  if (!buffer) return "";
  return buffer.slice(0, -1);
}
function previewFromBuffer(buffer) {
  return translate(buffer ?? "");
}
function isCompositionChar(char) {
  return typeof char === "string" && /^[a-zA-Z\-=+]$/.test(char);
}

// src/core/candidate.js
function createCandidateSession() {
  let gen = 0;
  return {
    next() {
      gen += 1;
      return gen;
    },
    isStale(token) {
      return token !== gen;
    },
    current() {
      return gen;
    }
  };
}
function withCandidates(state, candidates) {
  return {
    ...state,
    candidates: candidates ?? [],
    pageIndex: 0,
    selectedCandidate: 0,
    candidateVisible: (candidates?.length ?? 0) > 0
  };
}
function shiftPage(state, delta) {
  const pages = totalPages(state);
  if (!pages) return state;
  const next = Math.min(Math.max(0, state.pageIndex + delta), pages - 1);
  return {
    ...state,
    pageIndex: next,
    selectedCandidate: next * state.pageSize
  };
}
function candidateAtPageIndex(state, pageLocalIndex) {
  const idx = state.pageIndex * state.pageSize + pageLocalIndex;
  return state.candidates[idx] ?? null;
}

// src/utils/mongol.js
var Mongol = {
  nirugu: 6154,
  fvs1: 6155,
  fvs2: 6156,
  fvs3: 6157,
  mvs: 6158,
  a: 6176,
  e: 6177,
  i: 6178,
  o: 6179,
  u: 6180,
  oe: 6181,
  ue: 6182,
  ee: 6183,
  na: 6184,
  ang: 6185,
  ba: 6186,
  pa: 6187,
  qa: 6188,
  ga: 6189,
  ma: 6190,
  la: 6191,
  sa: 6192,
  sha: 6193,
  ta: 6194,
  da: 6195,
  cha: 6196,
  ja: 6197,
  ya: 6198,
  ra: 6199,
  wa: 6200,
  tsa: 6204,
  haa: 6206,
  zra: 6207,
  lha: 6208,
  zhi: 6209,
  chi: 6210,
  questionExclamation: 8264,
  exclamationQuestion: 8265
};
var NNBSP = 8239;
var FVS_OR_MVS = /* @__PURE__ */ new Set([6155, 6156, 6157, 6158, 6159]);
function fromCodes(...codes) {
  return String.fromCodePoint(...codes);
}
function isMongolianLetter(code) {
  return code != null && code >= Mongol.a && code <= Mongol.chi;
}
function isMvsPrecedingChar(code) {
  if (code == null) return false;
  return code === Mongol.na || code === Mongol.qa || code === Mongol.ga || code === Mongol.ma || code === Mongol.la || code === Mongol.ja || code === Mongol.ya || code === Mongol.ra || code === Mongol.wa || code === Mongol.o || code === Mongol.u || code === Mongol.oe || code === Mongol.ue;
}
function isVowel(code) {
  return code != null && code >= Mongol.a && code <= Mongol.ee;
}
function isMasculineVowel(code) {
  return code === Mongol.a || code === Mongol.o || code === Mongol.u;
}
function isFeminineVowel(code) {
  return code === Mongol.e || code === Mongol.ee || code === Mongol.oe || code === Mongol.ue;
}
function joiningMongolianFromEnd(s2) {
  if (!s2) return false;
  for (let i = s2.length - 1; i >= 0; i--) {
    const c = s2.codePointAt(i);
    if (c === NNBSP) return false;
    if (FVS_OR_MVS.has(c)) {
      continue;
    }
    if (isMongolianLetter(c)) return true;
    return false;
  }
  return false;
}
function joiningMongolianFromStart(s2) {
  if (!s2) return false;
  for (let i = 0; i < s2.length; ) {
    const c = s2.codePointAt(i);
    const w = c > 65535 ? 2 : 1;
    if (c === NNBSP) return false;
    if (FVS_OR_MVS.has(c)) {
      i += w;
      continue;
    }
    if (isMongolianLetter(c)) return true;
    return false;
  }
  return false;
}
function isInitial(ctx) {
  if (!ctx || ctx.text == null || ctx.start == null || ctx.start < 0) return true;
  const text = ctx.text;
  if (!text) return true;
  const start = Math.min(ctx.start, text.length);
  const before = text.slice(Math.max(start - 2, 0), start);
  const after = text.slice(start, Math.min(start + 2, text.length));
  const prev = joiningMongolianFromEnd(before);
  const next = joiningMongolianFromStart(after);
  return !prev;
}
function getPreviousChar(ctx) {
  if (!ctx?.text || !ctx.start || ctx.start <= 0) return null;
  const before = ctx.text.slice(0, ctx.start);
  const cps = Array.from(before);
  if (!cps.length) return null;
  return cps[cps.length - 1].codePointAt(0);
}

// src/utils/unicode.js
var MONGOL_WORD_TAIL_RE = /([\u1800-\u18AF\u202F\u180E\u200C\u200D]+)$/u;
function codePoints(text) {
  return Array.from(text ?? "");
}
function graphemes(text) {
  if (typeof Intl !== "undefined" && Intl.Segmenter) {
    const seg = new Intl.Segmenter(void 0, { granularity: "grapheme" });
    return [...seg.segment(text ?? "")].map((s2) => s2.segment);
  }
  return codePoints(text);
}
function deleteLastGrapheme(text) {
  const parts = graphemes(text);
  if (!parts.length) return "";
  parts.pop();
  return parts.join("");
}
function trailingMongolWord(text) {
  const m = (text ?? "").match(MONGOL_WORD_TAIL_RE);
  return m ? m[1] : "";
}
function getLastWord(text) {
  if (!text || !text.trim()) return "";
  const normalized = text.replace(/᠂/g, " ").replace(/᠃/g, " ").replace(/\*/g, " ").replace(/\[/g, " ").replace(/\]/g, " ");
  const parts = normalized.split(/[\s\n\u202F]+/);
  return parts[parts.length - 1] || "";
}

// src/core/suffix.js
var MVS = String.fromCodePoint(Mongol.mvs);
function s(...codes) {
  return String.fromCodePoint(Mongol.mvs, ...codes);
}
var Suffix = {
  YIN: s(Mongol.ya, Mongol.i, Mongol.na),
  UN: s(Mongol.u, Mongol.na),
  UEN: s(Mongol.ue, Mongol.na),
  U: s(Mongol.u),
  UE: s(Mongol.ue),
  I: s(Mongol.i),
  YI: s(Mongol.ya, Mongol.i),
  DU: s(Mongol.da, Mongol.u),
  DUE: s(Mongol.da, Mongol.ue),
  TU: s(Mongol.ta, Mongol.u),
  TUE: s(Mongol.ta, Mongol.ue),
  DUR: s(Mongol.da, Mongol.u, Mongol.ra),
  DUER: s(Mongol.da, Mongol.ue, Mongol.ra),
  TUR: s(Mongol.ta, Mongol.u, Mongol.ra),
  TUER: s(Mongol.ta, Mongol.ue, Mongol.ra),
  DAQI: s(Mongol.da, Mongol.a, Mongol.qa, Mongol.i),
  DEQI: s(Mongol.da, Mongol.e, Mongol.qa, Mongol.i),
  TAQI: s(Mongol.ta, Mongol.a, Mongol.qa, Mongol.i),
  TEQI: s(Mongol.ta, Mongol.e, Mongol.qa, Mongol.i),
  ACHA: s(Mongol.a, Mongol.cha, Mongol.a),
  ECHE: s(Mongol.e, Mongol.cha, Mongol.e),
  BAR: s(Mongol.ba, Mongol.a, Mongol.ra),
  BER: s(Mongol.ba, Mongol.e, Mongol.ra),
  IYAR: s(Mongol.i, Mongol.ya, Mongol.a, Mongol.ra),
  IYER: s(Mongol.i, Mongol.ya, Mongol.e, Mongol.ra),
  TAI: s(Mongol.ta, Mongol.a, Mongol.i),
  TEI: s(Mongol.ta, Mongol.e, Mongol.i),
  LUGA: `${MVS}${String.fromCodePoint(Mongol.la, Mongol.u, Mongol.ga, Mongol.mvs, Mongol.a)}`,
  LUEGE: s(Mongol.la, Mongol.ue, Mongol.ga, Mongol.e),
  BAN: s(Mongol.ba, Mongol.a, Mongol.na),
  BEN: s(Mongol.ba, Mongol.e, Mongol.na),
  IYAN: s(Mongol.i, Mongol.ya, Mongol.a, Mongol.na),
  IYEN: s(Mongol.i, Mongol.ya, Mongol.e, Mongol.na),
  YUGAN: s(Mongol.ya, Mongol.u, Mongol.ga, Mongol.a, Mongol.na),
  YUEGEN: s(Mongol.ya, Mongol.ue, Mongol.ga, Mongol.e, Mongol.na),
  DAGAN: s(Mongol.da, Mongol.a, Mongol.ga, Mongol.a, Mongol.na),
  DEGEN: s(Mongol.da, Mongol.e, Mongol.ga, Mongol.e, Mongol.na),
  TAGAN: s(Mongol.ta, Mongol.a, Mongol.ga, Mongol.a, Mongol.na),
  TEGEN: s(Mongol.ta, Mongol.e, Mongol.ga, Mongol.e, Mongol.na),
  ACHAGAN: s(Mongol.a, Mongol.cha, Mongol.a, Mongol.ga, Mongol.a, Mongol.na),
  ECHEGEN: s(Mongol.e, Mongol.cha, Mongol.e, Mongol.ga, Mongol.e, Mongol.na),
  UD: s(Mongol.u, Mongol.da),
  UED: s(Mongol.ue, Mongol.da),
  NUGUD: s(Mongol.na, Mongol.u, Mongol.ga, Mongol.u, Mongol.da),
  NUEGUED: s(Mongol.na, Mongol.ue, Mongol.ga, Mongol.ue, Mongol.da),
  NAR: s(Mongol.na, Mongol.a, Mongol.ra),
  NER: s(Mongol.na, Mongol.e, Mongol.ra),
  UU: s(Mongol.u, Mongol.u),
  UEUE: s(Mongol.ue, Mongol.ue),
  DA: s(Mongol.da, Mongol.a),
  DE: s(Mongol.da, Mongol.e),
  CHU: s(Mongol.cha, Mongol.u),
  CHUE: s(Mongol.cha, Mongol.ue)
};
var ALL_SUFFIXES = [
  Suffix.YIN,
  Suffix.UN,
  Suffix.UEN,
  Suffix.U,
  Suffix.UE,
  Suffix.I,
  Suffix.YI,
  Suffix.DU,
  Suffix.DUE,
  Suffix.TU,
  Suffix.TUE,
  Suffix.DUR,
  Suffix.DUER,
  Suffix.TUR,
  Suffix.TUER,
  Suffix.DAQI,
  Suffix.DEQI,
  Suffix.TAQI,
  Suffix.TEQI,
  Suffix.ACHA,
  Suffix.ECHE,
  Suffix.BAR,
  Suffix.BER,
  Suffix.IYAR,
  Suffix.IYER,
  Suffix.TAI,
  Suffix.TEI,
  Suffix.LUGA,
  Suffix.LUEGE,
  Suffix.BAN,
  Suffix.BEN,
  Suffix.IYAN,
  Suffix.IYEN,
  Suffix.YUGAN,
  Suffix.YUEGEN,
  Suffix.DAGAN,
  Suffix.DEGEN,
  Suffix.TAGAN,
  Suffix.TEGEN,
  Suffix.ACHAGAN,
  Suffix.ECHEGEN,
  Suffix.UD,
  Suffix.UED,
  Suffix.NUGUD,
  Suffix.NUEGUED,
  Suffix.NAR,
  Suffix.NER,
  Suffix.UU,
  Suffix.UEUE,
  Suffix.DA,
  Suffix.DE,
  Suffix.CHU,
  Suffix.CHUE
];
var ALL_SUFFIX_SET = new Set(ALL_SUFFIXES);
function isKnownSuffix(text) {
  return ALL_SUFFIX_SET.has(text);
}
function getGender(word) {
  for (const ch of word ?? "") {
    const c = ch.codePointAt(0);
    if (!isVowel(c) || c === Mongol.i) continue;
    if (isMasculineVowel(c)) return "masculine";
    if (isFeminineVowel(c)) return "feminine";
  }
  return "neuter";
}
function isBGDRS(code) {
  return code === Mongol.ba || code === Mongol.ga || code === Mongol.da || code === Mongol.ra || code === Mongol.sa;
}
function buildSuffixCandidatesForWord(gender, lastChar) {
  const masc = gender === "masculine";
  return [
    // yinUnU
    isVowel(lastChar) ? Suffix.YIN : lastChar === Mongol.na ? masc ? Suffix.U : Suffix.UE : masc ? Suffix.UN : Suffix.UEN,
    // tuDu
    isBGDRS(lastChar) ? masc ? Suffix.TU : Suffix.TUE : masc ? Suffix.DU : Suffix.DUE,
    // taganDagan
    isBGDRS(lastChar) ? masc ? Suffix.TAGAN : Suffix.TEGEN : masc ? Suffix.DAGAN : Suffix.DEGEN,
    // taqiDaqi
    isBGDRS(lastChar) ? masc ? Suffix.TAQI : Suffix.TEQI : masc ? Suffix.DAQI : Suffix.DEQI,
    // yiI
    isVowel(lastChar) ? Suffix.YI : Suffix.I,
    // barIyar
    isVowel(lastChar) ? masc ? Suffix.BAR : Suffix.BER : masc ? Suffix.IYAR : Suffix.IYER,
    // banIyan
    isVowel(lastChar) ? masc ? Suffix.BAN : Suffix.BEN : masc ? Suffix.IYAN : Suffix.IYEN,
    // achaEche
    masc ? Suffix.ACHA : Suffix.ECHE,
    // taiTei
    masc ? Suffix.TAI : Suffix.TEI,
    // uu
    masc ? Suffix.UU : Suffix.UEUE,
    // ud
    masc ? Suffix.UD : Suffix.UED,
    // nugud
    masc ? Suffix.NUGUD : Suffix.NUEGUED,
    // chu
    masc ? Suffix.CHU : Suffix.CHUE
  ];
}
function getSuffixCandidates(textBeforeCursor = "") {
  if (!textBeforeCursor) return [...ALL_SUFFIXES];
  const lastWord = getLastWord(textBeforeCursor);
  if (!lastWord) return [...ALL_SUFFIXES];
  const chars = Array.from(lastWord);
  const lastChar = chars[chars.length - 1].codePointAt(0);
  if (!isMongolianLetter(lastChar)) return [...ALL_SUFFIXES];
  return buildSuffixCandidatesForWord(getGender(lastWord), lastChar);
}

// src/api/candidate-provider.js
var CandidateProvider = class {
  /**
   * @param {string} input
   * @param {object} [context]
   * @returns {Promise<string[]>}
   */
  async getCandidates(_input, _context = {}) {
    return [];
  }
  /**
   * @param {string} word
   * @returns {Promise<string[]>}
   */
  async getNextWords(_word) {
    return [];
  }
};
var LocalCandidateProvider = class extends CandidateProvider {
  async getCandidates(input) {
    if (!input) return [];
    const mongol = /[\u1800-\u18AF]/.test(input) ? input : translate(input);
    return mongol ? [mongol] : [];
  }
};
var RemoteCandidateProvider = class extends CandidateProvider {
  /** @param {RemoteOptions} [options] */
  constructor(options = {}) {
    super();
    this.baseUrl = (options.baseUrl ?? "http://dev1:3003").replace(/\/+$/, "");
    this.candidatesPath = options.candidatesPath ?? "/api/next_word/candidates";
    this.nextWordsPath = options.nextWordsPath ?? "/api/next_word/list";
    this.timeoutMs = options.timeoutMs ?? 2500;
    this._cache = /* @__PURE__ */ new Map();
    this._cacheSize = options.cacheSize ?? 256;
    this._controllers = /* @__PURE__ */ new Map();
  }
  /** @param {string} path @param {string} word @param {string} field */
  async _post(path, word, field) {
    if (!word) return [];
    const cps = Array.from(word);
    const safeWord = cps.length > 256 ? cps.slice(0, 256).join("") : word;
    const cacheKey = `${path}:${safeWord}`;
    if (this._cache.has(cacheKey)) return this._cache.get(cacheKey);
    if (this._controllers.has(path)) {
      this._controllers.get(path).abort();
    }
    const ctrl = new AbortController();
    this._controllers.set(path, ctrl);
    const timer = setTimeout(() => ctrl.abort(), this.timeoutMs);
    try {
      const res = await fetch(`${this.baseUrl}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify({ word: safeWord }),
        signal: ctrl.signal
      });
      if (!res.ok) return [];
      const data = await res.json();
      const raw = data?.[field] ?? [];
      const words = raw.map((item) => typeof item === "string" ? item : item?.[0]).filter((s2) => typeof s2 === "string" && s2.trim());
      this._putCache(cacheKey, words);
      return words;
    } catch {
      return [];
    } finally {
      clearTimeout(timer);
      if (this._controllers.get(path) === ctrl) {
        this._controllers.delete(path);
      }
    }
  }
  _putCache(key, value) {
    if (this._cache.size >= this._cacheSize) {
      const first = this._cache.keys().next().value;
      this._cache.delete(first);
    }
    this._cache.set(key, value);
  }
  /**
   * @param {string} input - Mongolian lookup key (or Latin; will be mapped by Hybrid)
   */
  async getCandidates(input) {
    return this._post(this.candidatesPath, input, "candidates");
  }
  async getNextWords(word) {
    return this._post(this.nextWordsPath, word, "nextWords");
  }
};
var HybridCandidateProvider = class extends CandidateProvider {
  /**
   * @param {CandidateProvider} remote
   * @param {CandidateProvider} [local]
   */
  constructor(remote, local = new LocalCandidateProvider()) {
    super();
    this.remote = remote;
    this.local = local;
  }
  async getCandidates(input, context = {}) {
    const remote = await this.remote.getCandidates(input, context);
    if (remote.length) return remote;
    return this.local.getCandidates(input, context);
  }
  async getNextWords(word) {
    return this.remote.getNextWords(word);
  }
};
function createDefaultProvider(options = {}) {
  const remote = new RemoteCandidateProvider(options);
  if (options.hybrid === false) return remote;
  return new HybridCandidateProvider(remote);
}

// src/core/ime.js
var ImeCore = class {
  /** @param {ImeCoreOptions} options */
  constructor(options) {
    if (!options?.adapter) throw new Error("ImeCore requires an adapter");
    this.adapter = options.adapter;
    this.provider = options.provider ?? new LocalCandidateProvider();
    this.emit = options.emit ?? (() => {
    });
    this._session = createCandidateSession();
    this.state = createInitialState({
      mode: options.mode ?? "mongol",
      profile: options.profile ?? "desktop",
      pageSize: options.pageSize ?? 5
    });
  }
  getState() {
    return { ...this.state, pageCandidates: pageCandidates(this.state) };
  }
  setState(patch) {
    this.state = { ...this.state, ...patch };
    this.emit("state", this.getState());
  }
  enable() {
    this.setState({ enabled: true });
  }
  disable() {
    this.cancelComposition();
    this.setState({ enabled: false });
  }
  setMode(mode) {
    this.cancelComposition();
    this.setState({ mode });
    this.emit("mgl-ime-mode-change", { mode });
  }
  setProfile(profile) {
    this.setState({ profile });
  }
  setProvider(provider) {
    this.provider = provider;
  }
  setAdapter(adapter) {
    this.cancelComposition();
    this.adapter = adapter;
  }
  /**
   * Sync predicate used by desktop keydown to call preventDefault
   * before any await — mirrors _handleKey without side effects.
   * @param {{ key?: string, code?: string, shiftKey?: boolean, ctrlKey?: boolean }} ev
   */
  willHandleKey(ev) {
    if (!this.state.enabled) return false;
    const latinMode = this.state.mode === "latin";
    const { key, code, shiftKey, ctrlKey } = ev;
    const hasComp = this.state.composition.length > 0 || this.state.candidates.length > 0;
    if (ctrlKey && (key === " " || code === "Space")) return true;
    if (ctrlKey) return false;
    if (key === "_" || key === "\u2014" || key === "\u2013" || key === "\uFF0D" || shiftKey && (key === "-" || code === "Minus")) {
      return true;
    }
    if (latinMode && key && /^[\x20-\x7E]$/.test(key)) return true;
    if (key === "Escape" && hasComp) return true;
    if (directCharFromKey({ key, code, shiftKey, latinMode }) != null) {
      return true;
    }
    if (hasComp && !shiftKey && (key === "-" || code === "Minus")) return true;
    if (hasComp && (key === "=" || key === "+" || code === "Equal")) return true;
    if (!latinMode && key && isCompositionChar(key)) return true;
    if (!latinMode && (key === "Backspace" || code === "Backspace")) return true;
    if (hasComp && (key === "ArrowLeft" || key === "ArrowRight")) return false;
    if (!latinMode && (key === " " || code === "Space")) return true;
    if (key && /^[1-5]$/.test(key) && hasComp) return true;
    if (hasComp && (key === "ArrowDown" || key === "PageDown")) return true;
    if (hasComp && (key === "ArrowUp" || key === "PageUp")) return true;
    if (key === "Enter") return true;
    return false;
  }
  // ─── Composition / preview ─────────────────────────────────
  async updateComposition(buffer) {
    const preview = previewFromBuffer(buffer);
    const prevLen = this.state.previewLen;
    this.adapter.replaceBeforeCaret?.(prevLen, preview);
    const interim = preview ? [preview] : [];
    this.setState({
      composition: buffer,
      preview,
      previewLen: Array.from(preview).length,
      composing: buffer.length > 0,
      pageIndex: 0,
      selectedCandidate: 0,
      candidates: interim,
      candidateVisible: interim.length > 0
    });
    this.emit("mgl-ime-composition-update", { composition: buffer, preview });
    void this.queryCandidates(preview || buffer, "typing");
  }
  async queryCandidates(input, trigger = "typing") {
    const gen = this._session.next();
    if (!input) {
      this.setState(withCandidates(this.state, []));
      return;
    }
    try {
      const list = await this.provider.getCandidates(input, {
        trigger,
        composition: this.state.composition
      });
      if (this._session.isStale(gen)) return;
      this.setState(withCandidates(this.state, list));
      this.emit("mgl-ime-candidates", { candidates: list, trigger });
    } catch {
      if (this._session.isStale(gen)) return;
      const fallback = previewFromBuffer(this.state.composition) || input;
      this.setState(withCandidates(this.state, fallback ? [fallback] : []));
    }
  }
  async queryNextWords(word) {
    const gen = this._session.next();
    if (!word || !this.provider.getNextWords) {
      this.setState(withCandidates(this.state, []));
      return;
    }
    try {
      const list = await this.provider.getNextWords(word);
      if (this._session.isStale(gen)) return;
      this.setState(withCandidates(this.state, list));
      this.emit("mgl-ime-candidates", { candidates: list, trigger: "commit" });
    } catch {
      if (this._session.isStale(gen)) return;
      this.setState(withCandidates(this.state, []));
    }
  }
  /**
   * Commit selected / preview text into the editor.
   * @param {string} text
   * @param {{ addSpaceAfter?: boolean }} [opts]
   */
  async commit(text, opts = {}) {
    const { addSpaceAfter = false } = opts;
    let base = (text ?? "").replace(/^ +/, "");
    const mvsPrefix = base.startsWith("\u180E");
    const ctx = this.adapter.getTextBeforeCaret?.() ?? "";
    const dropPrevSpace = mvsPrefix && this.state.previewLen === 0 && ctx.length > 0 && ctx[ctx.length - 1] === " ";
    const deleteLen = this.state.previewLen + (dropPrevSpace ? 1 : 0);
    const finalText = addSpaceAfter ? `${base} ` : base;
    const wordForPredict = text.trim();
    this.adapter.replaceBeforeCaret?.(deleteLen, finalText);
    this.setState(clearCompositionFields(this.state));
    this.emit("mgl-ime-commit", { text: finalText });
    this.emit("mgl-ime-composition-end", { text: finalText });
    this.emit("mgl-ime-input", { text: finalText });
    if (wordForPredict) {
      await this.queryNextWords(wordForPredict);
    }
  }
  cancelComposition() {
    if (this.state.previewLen > 0) {
      this.adapter.replaceBeforeCaret?.(this.state.previewLen, "");
    }
    this._session.next();
    this.setState(clearCompositionFields(this.state));
    this.emit("mgl-ime-composition-end", { text: "", cancelled: true });
  }
  // ─── Candidate navigation ──────────────────────────────────
  nextPage() {
    this.setState(shiftPage(this.state, 1));
  }
  previousPage() {
    this.setState(shiftPage(this.state, -1));
  }
  nextCandidate() {
    const max = this.state.candidates.length - 1;
    if (max < 0) return;
    const next = Math.min(this.state.selectedCandidate + 1, max);
    const pageIndex = Math.floor(next / this.state.pageSize);
    this.setState({ selectedCandidate: next, pageIndex });
  }
  previousCandidate() {
    if (!this.state.candidates.length) return;
    const next = Math.max(this.state.selectedCandidate - 1, 0);
    const pageIndex = Math.floor(next / this.state.pageSize);
    this.setState({ selectedCandidate: next, pageIndex });
  }
  async selectCandidate(index, opts = {}) {
    const word = this.state.candidates[index];
    if (!word) return;
    await this.commit(word, { addSpaceAfter: opts.addSpaceAfter ?? true });
  }
  async selectPageCandidate(pageLocalIndex, opts = {}) {
    const word = candidateAtPageIndex(this.state, pageLocalIndex);
    if (!word) return;
    await this.commit(word, { addSpaceAfter: opts.addSpaceAfter ?? true });
  }
  async commitCurrent(opts = {}) {
    const word = currentCandidate(this.state) || (this.state.composition ? translate(this.state.composition) : null);
    if (!word) return;
    await this.commit(word, opts);
  }
  // ─── Unified command / key handling ────────────────────────
  /**
   * Handle a normalized command from desktop or virtual keyboard.
   * @param {{ type: string, key?: string, command?: string, shiftKey?: boolean, ctrlKey?: boolean, code?: string }} ev
   * @returns {Promise<boolean>} handled?
   */
  async handleEvent(ev) {
    if (!this.state.enabled) return false;
    if (ev.type === "command") {
      return this._handleCommand(ev.command, ev);
    }
    if (ev.type === "key") {
      return this._handleKey(ev);
    }
    return false;
  }
  async _handleCommand(command, ev = {}) {
    switch (command) {
      case "backspace":
        return this._backspace();
      case "delete":
        this.adapter.deleteForward();
        return true;
      case "space":
        return this._space();
      case "enter":
        return this._enter();
      case "escape":
        if (this.state.composition || this.state.candidates.length) {
          this.cancelComposition();
          return true;
        }
        return false;
      case "candidate-next":
        this.nextPage();
        return true;
      case "candidate-prev":
        this.previousPage();
        return true;
      case "shift":
        return false;
      case "mode":
        this.setMode(this.state.mode === "mongol" ? "latin" : "mongol");
        return true;
      case "suffix":
        return this._showSuffixes();
      case "nnbsp":
        await this._injectDirect("\u202F");
        return true;
      case "insert":
        if (ev.key) return this._insertDirectMobile(ev.key);
        return false;
      case "insert-plain":
        if (ev.key) return this._insertPlain(ev.key);
        return false;
      default:
        return false;
    }
  }
  async _handleKey(ev) {
    const latinMode = this.state.mode === "latin";
    const { key, code, shiftKey, ctrlKey } = ev;
    const hasComp = this.state.composition.length > 0 || this.state.candidates.length > 0;
    if (ctrlKey && (key === " " || code === "Space")) {
      this.setState({ enabled: !this.state.enabled });
      return true;
    }
    if (ctrlKey) return false;
    if (key === "_" || key === "\u2014" || key === "\u2013" || key === "\uFF0D" || shiftKey && (key === "-" || code === "Minus")) {
      return this._showSuffixes();
    }
    if (latinMode && key && /^[\x20-\x7E]$/.test(key)) {
      this.adapter.insertText(key);
      return true;
    }
    if (key === "Escape") {
      return this._handleCommand("escape");
    }
    const direct = directCharFromKey({ key, code, shiftKey, latinMode });
    if (direct != null) {
      await this._injectDirect(direct);
      return true;
    }
    if (hasComp && !shiftKey && (key === "-" || code === "Minus")) {
      this.previousPage();
      return true;
    }
    if (hasComp && (key === "=" || key === "+" || code === "Equal")) {
      this.nextPage();
      return true;
    }
    if (!latinMode && key && isCompositionChar(key)) {
      if (!this.state.composing) {
        this.emit("mgl-ime-composition-start", {});
      }
      const nb = appendToBuffer(this.state.composition, key);
      await this.updateComposition(nb);
      return true;
    }
    if (!latinMode && (key === "Backspace" || code === "Backspace")) {
      return this._backspace();
    }
    if (hasComp && (key === "ArrowLeft" || key === "ArrowRight")) {
      await this.commitCurrent({ addSpaceAfter: false });
      return false;
    }
    if (!latinMode && (key === " " || code === "Space")) {
      return this._space();
    }
    if (key && /^[1-5]$/.test(key) && hasComp) {
      await this.selectPageCandidate(Number(key) - 1, { addSpaceAfter: true });
      return true;
    }
    if (hasComp && (key === "ArrowDown" || key === "PageDown")) {
      this.nextPage();
      return true;
    }
    if (hasComp && (key === "ArrowUp" || key === "PageUp")) {
      this.previousPage();
      return true;
    }
    if (key === "Enter") {
      return this._enter();
    }
    return false;
  }
  async _backspace() {
    if (this.state.composition) {
      const nb = backspaceBuffer(this.state.composition);
      await this.updateComposition(nb);
      return true;
    }
    const ctx = this.adapter.getTextBeforeCaret?.() ?? "";
    const word = trailingMongolWord(ctx);
    if (word) {
      this.adapter.replaceBeforeCaret?.(Array.from(word).length, "");
      this.setState({
        ...withCandidates(this.state, []),
        pendingSuffixDelete: false
      });
      return true;
    }
    this.adapter.deleteBackward();
    this.setState({
      ...withCandidates(this.state, []),
      pendingSuffixDelete: false
    });
    return true;
  }
  async _space() {
    const hasComp = this.state.composition.length > 0 || this.state.candidates.length > 0;
    if (hasComp) {
      await this.commitCurrent({ addSpaceAfter: true });
      return true;
    }
    this.adapter.insertText(" ");
    this.setState({ pendingSuffixDelete: false });
    return true;
  }
  async _enter() {
    const hasComp = this.state.composition.length > 0 || this.state.candidates.length > 0;
    if (hasComp) {
      await this.commitCurrent({ addSpaceAfter: false });
      return true;
    }
    this.adapter.insertText("\n");
    return true;
  }
  async _injectDirect(ch) {
    if (this.state.composition || this.state.candidates.length) {
      await this.commitCurrent({ addSpaceAfter: false });
    }
    this.adapter.replaceBeforeCaret?.(this.state.previewLen, ch);
    this.setState(clearCompositionFields(this.state));
  }
  /**
   * Insert emoji / other literal text without candidate lookup.
   * Commits an active phonetic composition first; leaves next-word /
   * suffix lists alone (they are cleared after insert).
   * @param {string} ch
   */
  async _insertPlain(ch) {
    if (this.state.composition) {
      await this.commitCurrent({ addSpaceAfter: false });
    }
    this.adapter.insertText(ch);
    this.setState(clearCompositionFields(this.state));
    this.emit("mgl-ime-input", { text: ch });
    return true;
  }
  /** Mobile: insert Mongol char and refresh candidates from last word. */
  async _insertDirectMobile(ch) {
    this.adapter.insertText(ch);
    this.setState({ pendingSuffixDelete: false });
    if (this.state.mode === "latin") {
      if (this.state.candidates.length) this.setState(clearCompositionFields(this.state));
      return true;
    }
    const ctx = this.adapter.getTextBeforeCaret?.() ?? this.adapter.getText();
    const last = getLastWord(ctx);
    if (last) await this.queryCandidates(last, "typing");
    return true;
  }
  /**
   * Show suffix candidates — mirrors m-v-k `:suffix-candidates`.
   * Does NOT mutate the buffer; only sets pendingSuffixDelete so the next
   * pick deletes the trailing space / separator before inserting the suffix.
   */
  async _showSuffixes() {
    if (this.state.previewLen > 0) {
      this.adapter.replaceBeforeCaret?.(this.state.previewLen, "");
    }
    this.setState({
      ...clearCompositionFields(this.state),
      pendingSuffixDelete: true
    });
    const raw = this.adapter.getTextBeforeCaret?.() ?? "";
    const query = raw.replace(/\s+$/u, "");
    const list = getSuffixCandidates(query);
    this._session.next();
    this.setState(withCandidates(this.state, list));
    this.emit("mgl-ime-candidates", { candidates: list, trigger: "suffix" });
    return true;
  }
  /**
   * Mobile candidate pick — mirrors m-v-k `on-candidates-clicked`.
   * Suffix path: delete one char (trailing space) then insert suffix + space.
   * Otherwise replace the last word.
   * @param {string} text
   */
  async pickCandidateMobile(text) {
    const withSpace = `${text} `;
    const suffixDelete = this.state.pendingSuffixDelete;
    const mvs = String.fromCodePoint(Mongol.mvs);
    const isSuffix = suffixDelete || isKnownSuffix(text) || text.startsWith(mvs);
    this.setState({ pendingSuffixDelete: false });
    if (isSuffix) {
      this.adapter.deleteBackward();
      this.adapter.insertText(withSpace);
    } else {
      const ctx = this.adapter.getTextBeforeCaret?.() ?? "";
      const last = getLastWord(ctx);
      if (last) {
        this.adapter.replaceBeforeCaret?.(Array.from(last).length, withSpace);
      } else {
        this.adapter.insertText(withSpace);
      }
    }
    this.emit("mgl-ime-commit", { text: withSpace });
    await this.queryNextWords(text.trim());
  }
  destroy() {
    this.cancelComposition();
    this._session.next();
  }
};

// src/utils/caret-rect.js
function measureCaretRect(range, fallbackEl) {
  if (range) {
    const rects = range.getClientRects();
    for (let i = 0; i < rects.length; i++) {
      const r = rects[i];
      if (r.width || r.height) return r;
    }
    const union = range.getBoundingClientRect();
    if (union.width || union.height) return union;
    try {
      const mirror = range.cloneRange();
      const span = document.createElement("span");
      span.textContent = "\u200B";
      mirror.insertNode(span);
      const r = span.getBoundingClientRect();
      span.parentNode?.removeChild(span);
      if (r.width || r.height || r.top || r.left) return r;
    } catch {
    }
  }
  return fallbackEl?.getBoundingClientRect?.() ?? null;
}

// src/adapters/custom.js
function createCustomAdapter(methods) {
  const adapter = {
    getText: () => "",
    getSelection: () => ({ start: 0, end: 0 }),
    setSelection: () => {
    },
    insertText: () => {
    },
    deleteBackward: () => {
    },
    deleteForward: () => {
    },
    replaceSelection: (text) => adapter.insertText(text),
    ...methods
  };
  if (!adapter.replaceBeforeCaret) {
    adapter.replaceBeforeCaret = (deleteLen, text) => {
      const full = adapter.getText();
      const sel = adapter.getSelection();
      const start = Math.max(0, sel.start - deleteLen);
      const cps = Array.from(full);
      const before = cps.slice(0, start).join("");
      const after = cps.slice(sel.end).join("");
      if (typeof methods.getText !== "function") {
        for (let i = 0; i < deleteLen; i++) adapter.deleteBackward();
        adapter.insertText(text);
        return;
      }
      adapter.setSelection({ start, end: sel.end });
      adapter.replaceSelection(text);
      void before;
      void after;
    };
  }
  if (!adapter.getTextBeforeCaret) {
    adapter.getTextBeforeCaret = () => {
      const text = adapter.getText();
      const { start } = adapter.getSelection();
      return Array.from(text).slice(0, start).join("");
    };
  }
  return (
    /** @type {EditorAdapter} */
    adapter
  );
}

// src/adapters/contenteditable.js
function ContentEditableAdapter(el) {
  if (!el) throw new Error("ContentEditableAdapter requires an element");
  const getRange = () => {
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return null;
    const range = sel.getRangeAt(0);
    if (!el.contains(range.commonAncestorContainer)) return null;
    return range;
  };
  const offsetsFromRange = (range) => {
    const pre = range.cloneRange();
    pre.selectNodeContents(el);
    pre.setEnd(range.startContainer, range.startOffset);
    const start = pre.toString().length;
    const end = start + range.toString().length;
    return { start, end };
  };
  const setOffsets = (start, end) => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let pos = 0;
    let startNode = null;
    let startOff = 0;
    let endNode = null;
    let endOff = 0;
    let node;
    while (node = walker.nextNode()) {
      const len = node.textContent.length;
      if (!startNode && pos + len >= start) {
        startNode = node;
        startOff = start - pos;
      }
      if (!endNode && pos + len >= end) {
        endNode = node;
        endOff = end - pos;
        break;
      }
      pos += len;
    }
    if (!startNode) {
      el.focus();
      return;
    }
    if (!endNode) {
      endNode = startNode;
      endOff = startOff;
    }
    const range = document.createRange();
    range.setStart(startNode, Math.min(startOff, startNode.textContent.length));
    range.setEnd(endNode, Math.min(endOff, endNode.textContent.length));
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  };
  const insertAtCaret = (text) => {
    el.focus();
    const range = getRange();
    if (!range) {
      el.appendChild(document.createTextNode(text));
      return;
    }
    range.deleteContents();
    const node = document.createTextNode(text);
    range.insertNode(node);
    range.setStartAfter(node);
    range.collapse(true);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  };
  return createCustomAdapter({
    getElement: () => el,
    focus: () => el.focus(),
    blur: () => el.blur(),
    getText: () => el.textContent ?? "",
    getSelection: () => {
      const range = getRange();
      if (!range) {
        const len = (el.textContent ?? "").length;
        return { start: len, end: len };
      }
      return offsetsFromRange(range);
    },
    setSelection: ({ start, end }) => setOffsets(start, end ?? start),
    insertText: (text) => insertAtCaret(text ?? ""),
    replaceSelection: (text) => insertAtCaret(text ?? ""),
    deleteBackward: () => {
      el.focus();
      const range = getRange();
      if (!range) return;
      if (!range.collapsed) {
        range.deleteContents();
        return;
      }
      const { start } = offsetsFromRange(range);
      if (start <= 0) return;
      const text = el.textContent ?? "";
      const before = text.slice(0, start);
      const after = text.slice(start);
      const nextBefore = deleteLastGrapheme(before);
      const deleted = before.length - nextBefore.length;
      el.textContent = nextBefore + after;
      setOffsets(start - deleted, start - deleted);
    },
    deleteForward: () => {
      el.focus();
      const range = getRange();
      if (!range) return;
      if (!range.collapsed) {
        range.deleteContents();
        return;
      }
      const { start } = offsetsFromRange(range);
      const text = el.textContent ?? "";
      if (start >= text.length) return;
      const after = text.slice(start);
      const parts = graphemes(after);
      parts.shift();
      el.textContent = text.slice(0, start) + parts.join("");
      setOffsets(start, start);
    },
    replaceBeforeCaret: (deleteLen, text) => {
      const full = el.textContent ?? "";
      const range = getRange();
      const { start, end } = range ? offsetsFromRange(range) : { start: full.length, end: full.length };
      const before = full.slice(0, start);
      const after = full.slice(end);
      const beforeCps = Array.from(before);
      const del = Math.min(deleteLen ?? 0, beforeCps.length);
      const nextBefore = beforeCps.slice(0, beforeCps.length - del).join("");
      const insert = text ?? "";
      el.textContent = nextBefore + insert + after;
      const caret = (nextBefore + insert).length;
      setOffsets(caret, caret);
    },
    getTextBeforeCaret: () => {
      const full = el.textContent ?? "";
      const range = getRange();
      if (!range) return full;
      const { start } = offsetsFromRange(range);
      return full.slice(0, start);
    },
    selectAll: () => {
      el.focus();
      const range = document.createRange();
      range.selectNodeContents(el);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    },
    getCaretRect: () => measureCaretRect(getRange(), el)
  });
}

// src/adapters/textarea.js
function TextareaAdapter(el) {
  if (!el) throw new Error("TextareaAdapter requires a textarea");
  return createCustomAdapter({
    getElement: () => el,
    focus: () => el.focus(),
    blur: () => el.blur(),
    getText: () => el.value ?? "",
    getSelection: () => ({
      start: el.selectionStart ?? 0,
      end: el.selectionEnd ?? 0
    }),
    setSelection: ({ start, end }) => {
      el.setSelectionRange(start, end ?? start);
    },
    insertText: (text) => {
      const start = el.selectionStart;
      const end = el.selectionEnd;
      const v = el.value;
      el.value = v.slice(0, start) + text + v.slice(end);
      const caret = start + text.length;
      el.setSelectionRange(caret, caret);
      el.dispatchEvent(new Event("input", { bubbles: true }));
    },
    replaceSelection: (text) => {
      const start = el.selectionStart;
      const end = el.selectionEnd;
      el.value = el.value.slice(0, start) + text + el.value.slice(end);
      const caret = start + text.length;
      el.setSelectionRange(caret, caret);
      el.dispatchEvent(new Event("input", { bubbles: true }));
    },
    deleteBackward: () => {
      const start = el.selectionStart;
      const end = el.selectionEnd;
      if (start !== end) {
        el.value = el.value.slice(0, start) + el.value.slice(end);
        el.setSelectionRange(start, start);
      } else if (start > 0) {
        const before = el.value.slice(0, start);
        const next = deleteLastGrapheme(before);
        const deleted = before.length - next.length;
        el.value = next + el.value.slice(start);
        el.setSelectionRange(start - deleted, start - deleted);
      }
      el.dispatchEvent(new Event("input", { bubbles: true }));
    },
    deleteForward: () => {
      const start = el.selectionStart;
      const end = el.selectionEnd;
      if (start !== end) {
        el.value = el.value.slice(0, start) + el.value.slice(end);
        el.setSelectionRange(start, start);
      } else {
        const after = el.value.slice(start);
        const parts = graphemes(after);
        parts.shift();
        el.value = el.value.slice(0, start) + parts.join("");
        el.setSelectionRange(start, start);
      }
      el.dispatchEvent(new Event("input", { bubbles: true }));
    },
    replaceBeforeCaret: (deleteLen, text) => {
      const start = el.selectionStart ?? 0;
      const end = el.selectionEnd ?? start;
      const before = el.value.slice(0, start);
      const after = el.value.slice(end);
      const beforeCps = Array.from(before);
      const del = Math.min(deleteLen ?? 0, beforeCps.length);
      const nextBefore = beforeCps.slice(0, beforeCps.length - del).join("");
      const insert = text ?? "";
      el.value = nextBefore + insert + after;
      const caret = (nextBefore + insert).length;
      el.setSelectionRange(caret, caret);
      el.dispatchEvent(new Event("input", { bubbles: true }));
    },
    getTextBeforeCaret: () => el.value.slice(0, el.selectionStart),
    selectAll: () => el.select(),
    getCaretRect: () => el.getBoundingClientRect()
  });
}

// src/adapters/input.js
function InputAdapter(el) {
  if (!el) throw new Error("InputAdapter requires an input element");
  return TextareaAdapter(
    /** @type {any} */
    el
  );
}

// src/profiles/detect.js
function isTouchDevice() {
  if (typeof window === "undefined") return false;
  return "ontouchstart" in window || (navigator.maxTouchPoints ?? 0) > 0 || (navigator.msMaxTouchPoints ?? 0) > 0;
}
function isMobileUA() {
  if (typeof navigator === "undefined") return false;
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile/i.test(
    navigator.userAgent
  );
}
function detectProfile(profile = "auto") {
  if (profile === "desktop" || profile === "mobile") return profile;
  if (isMobileUA()) return "mobile";
  if (isTouchDevice() && typeof window !== "undefined" && window.innerWidth < 900) {
    return "mobile";
  }
  return "desktop";
}
function resolveKeyboardMode(keyboardMode, profile) {
  if (keyboardMode === "system" || keyboardMode === "virtual") return keyboardMode;
  return profile === "mobile" ? "virtual" : "system";
}

// src/profiles/desktop.js
function attachDesktopController(core, options = {}) {
  const target = options.target ?? window;
  const editorEl = options.editorEl ?? null;
  const shouldHandle = options.shouldHandle ?? (() => true);
  let shiftAlone = false;
  let chain = Promise.resolve();
  let inFlight = 0;
  const handle = (ev) => Promise.resolve(core.handleEvent(ev)).catch((err) => {
    console.error("[mgl-web-ime]", err);
  });
  const onKeyDown = (e) => {
    if (!shouldHandle()) return;
    if (!core.state.enabled) return;
    if (e.isComposing || e.key === "Process") return;
    const ev = {
      type: "key",
      key: e.key,
      code: e.code,
      shiftKey: e.shiftKey,
      ctrlKey: e.ctrlKey || e.metaKey,
      altKey: e.altKey
    };
    if (!core.willHandleKey(ev)) return;
    e.preventDefault();
    e.stopPropagation();
    if (inFlight === 0) {
      inFlight++;
      chain = handle(ev).finally(() => {
        inFlight--;
      });
    } else {
      inFlight++;
      chain = chain.then(() => handle(ev)).finally(() => {
        inFlight--;
      });
    }
  };
  const onBeforeInput = (e) => {
    if (!shouldHandle() || !core.state.enabled) return;
    if (core.state.mode === "latin") return;
    if (e.isComposing) return;
    const type = e.inputType || "";
    if (type.startsWith("insert")) {
      e.preventDefault();
    }
  };
  const onKeyDownShift = (e) => {
    if (e.key === "Shift") shiftAlone = true;
    else shiftAlone = false;
  };
  const onKeyUp = (e) => {
    if (!shouldHandle() || !core.state.enabled) return;
    if (e.key === "Shift" && shiftAlone) {
      shiftAlone = false;
      core.setMode(core.state.mode === "mongol" ? "latin" : "mongol");
    }
  };
  target.addEventListener("keydown", onKeyDownShift, true);
  target.addEventListener("keydown", onKeyDown, true);
  target.addEventListener("keyup", onKeyUp, true);
  editorEl?.addEventListener("beforeinput", onBeforeInput, true);
  return {
    profile: "desktop",
    virtualKeyboard: false,
    candidatePopup: true,
    detach() {
      target.removeEventListener("keydown", onKeyDownShift, true);
      target.removeEventListener("keydown", onKeyDown, true);
      target.removeEventListener("keyup", onKeyUp, true);
      editorEl?.removeEventListener("beforeinput", onBeforeInput, true);
    }
  };
}

// src/profiles/mobile.js
function attachMobileController(core, options = {}) {
  const editorEl = options.editorEl ?? core.adapter.getElement?.();
  if (editorEl) {
    editorEl.setAttribute("inputmode", "none");
    editorEl.setAttribute("virtualkeyboardpolicy", "manual");
    if ("readOnly" in editorEl) {
    }
  }
  return {
    profile: "mobile",
    virtualKeyboard: true,
    candidateBar: true,
    /**
     * Forward virtual-keyboard events into core.
     * @param {{ type: string, key?: string, command?: string }} ev
     */
    async onKeyboardEvent(ev) {
      if (ev.type === "key" && ev.key) {
        return core.handleEvent({ type: "command", command: "insert", key: ev.key });
      }
      if (ev.type === "command") {
        if (ev.command === "layout") {
          const next = ev.latin ? "latin" : "mongol";
          if (core.state.mode !== next) core.setMode(next);
          return true;
        }
        if (ev.command === "shift") return false;
        return core.handleEvent(ev);
      }
      return false;
    },
    detach() {
      if (editorEl) {
        editorEl.removeAttribute("inputmode");
        editorEl.removeAttribute("virtualkeyboardpolicy");
      }
    }
  };
}

// src/keyboard/layout.js
var MN_INDEX_LAYOUT = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ng"],
  ["-", "z", "x", "c", "v", "b", "n", "m", "_"]
];
var LAYOUTS = {
  mongol: [
    ["\u1834\u180A", "\u1838\u180A", "\u1821", "\u1837\u180A", "\u1832\u180A", "\u1836\u180A", "\u1826\u180A", "\u1822", "\u1825", "\u182B\u180A"],
    ["\u1820", "\u1830\u180A", "\u1833", "\u1839\u180A", "\u182D\u180A", "\u182C\u180A", "\u1835\u180A", "\u183A\u180A", "\u182F\u180A", "\u1829"],
    ["shift", "\u183D\u180A", "\u1831\u180A", "\u1823", "\u1824\u180A", "\u182A\u180A", "\u1828\u180A", "\u182E\u180A", "backspace"],
    ["special", "emoji", "abc", "suffix", "\u1802", "space", "\u1803", "enter"]
  ],
  "mongol-special": [
    ["\u1811", "\u1812", "\u1813", "\u1814", "\u1815", "\u1816", "\u1817", "\u1818", "\u1819", "\u1810"],
    ["@", "#", "\u20AC", "_", "&", "\uFF0D", "+", "\uFF08", "\uFF09", "/"],
    ["other-special", "\u203B", "\u1801", "\uFE11", "\uFE13", "\uFF1B", "\uFF01", "\uFF1F", "backspace"],
    ["special", "emoji", "abc", ",", "space", ".", "enter"]
  ],
  "mongol-other-special": [
    ["\uFF5E", '"', "|", "\xB7", "\u221A", "\u220F", "\xF7", "\u1805", "\xB6", "\u25B3"],
    ["\xA3", "\xA5", "$", "\xA2", "\u2049", "\u2048", "=", "\u2774", "\u2775", "\\"],
    ["other-special", "\u1804", "\u1806", "\u2026", "\u1801", "\uFF3B", "\uFF3D", "backspace"],
    ["special", "emoji", "abc", ",", "space", ".", "enter"]
  ],
  latin: [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    ["shift", "z", "x", "c", "v", "b", "n", "m", "backspace"],
    ["special", "emoji", "abc", ",", "space", ".", "enter"]
  ],
  "latin-special": [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["@", "#", "\u20AC", "_", "&", "-", "+", "(", ")", "/"],
    ["other-special", "*", '"', "'", ":", ";", "!", "?", "backspace"],
    ["special", "emoji", "abc", ",", "space", ".", "enter"]
  ]
};
var ACTION_KEYS = /* @__PURE__ */ new Set([
  "shift",
  "backspace",
  "enter",
  "space",
  "special",
  "other-special",
  "abc",
  "suffix",
  "emoji"
]);
function normalizeKey(item, pos = {}) {
  if (ACTION_KEYS.has(item)) {
    return { type: "action", action: item, label: item };
  }
  const value = Array.from(item)[0] ?? item;
  const cp = value.codePointAt(0);
  const mongolLetter = cp >= 6176 && cp <= 6210;
  const mongol = cp >= 6144 && cp <= 6319;
  let id = null;
  if (mongolLetter && (pos.layoutName === "mongol" || pos.layoutName == null) && pos.rowIndex != null && pos.colIndex != null) {
    id = MN_INDEX_LAYOUT[pos.rowIndex]?.[pos.colIndex] ?? null;
  } else if (!mongol) {
    id = value.toLowerCase();
  }
  return {
    type: "key",
    value,
    label: item,
    id,
    mongol
  };
}
function getLayout(name = "mongol") {
  return LAYOUTS[name] ?? LAYOUTS.mongol;
}
function resolveLayoutName({ base = "mongol", special = false, otherSpecial = false, latin = false }) {
  if (latin) {
    if (otherSpecial) return "latin-special";
    if (special) return "latin-special";
    return "latin";
  }
  if (otherSpecial) return "mongol-other-special";
  if (special) return "mongol-special";
  return base;
}

// src/keyboard/key.js
function actionToCommand(action) {
  switch (action) {
    case "backspace":
      return "backspace";
    case "enter":
      return "enter";
    case "space":
      return "space";
    case "suffix":
      return "suffix";
    case "shift":
      return "shift";
    default:
      return action;
  }
}

// src/keyboard/emoji.js
var MOBILE_EMOJI_COLS = 8;
var MOBILE_EMOJI_ROWS = 3;
var MOBILE_EMOJI_PAGE_SIZE = MOBILE_EMOJI_COLS * MOBILE_EMOJI_ROWS;
var REGIONAL_A = 127462;
function flag(cc) {
  return String.fromCodePoint(
    ...[...cc.toUpperCase()].map((c) => REGIONAL_A + c.charCodeAt(0) - 65)
  );
}
var FLAG_REGIONS = [
  "AC",
  "AD",
  "AE",
  "AF",
  "AG",
  "AI",
  "AL",
  "AM",
  "AO",
  "AQ",
  "AR",
  "AS",
  "AT",
  "AU",
  "AW",
  "AX",
  "AZ",
  "BA",
  "BB",
  "BD",
  "BE",
  "BF",
  "BG",
  "BH",
  "BI",
  "BJ",
  "BL",
  "BM",
  "BN",
  "BO",
  "BQ",
  "BR",
  "BS",
  "BT",
  "BV",
  "BW",
  "BY",
  "BZ",
  "CA",
  "CC",
  "CD",
  "CF",
  "CG",
  "CH",
  "CI",
  "CK",
  "CL",
  "CM",
  "CN",
  "CO",
  "CP",
  "CR",
  "CU",
  "CV",
  "CW",
  "CX",
  "CY",
  "CZ",
  "DE",
  "DG",
  "DJ",
  "DK",
  "DM",
  "DO",
  "DZ",
  "EA",
  "EC",
  "EE",
  "EG",
  "EH",
  "ER",
  "ES",
  "ET",
  "EU",
  "FI",
  "FJ",
  "FK",
  "FM",
  "FO",
  "FR",
  "GA",
  "GB",
  "GD",
  "GE",
  "GF",
  "GG",
  "GH",
  "GI",
  "GL",
  "GM",
  "GN",
  "GP",
  "GQ",
  "GR",
  "GS",
  "GT",
  "GU",
  "GW",
  "GY",
  "HK",
  "HM",
  "HN",
  "HR",
  "HT",
  "HU",
  "IC",
  "ID",
  "IE",
  "IL",
  "IM",
  "IN",
  "IO",
  "IQ",
  "IR",
  "IS",
  "IT",
  "JE",
  "JM",
  "JO",
  "JP",
  "KE",
  "KG",
  "KH",
  "KI",
  "KM",
  "KN",
  "KP",
  "KR",
  "KW",
  "KY",
  "KZ",
  "LA",
  "LB",
  "LC",
  "LI",
  "LK",
  "LR",
  "LS",
  "LT",
  "LU",
  "LV",
  "LY",
  "MA",
  "MC",
  "MD",
  "ME",
  "MF",
  "MG",
  "MH",
  "MK",
  "ML",
  "MM",
  "MN",
  "MO",
  "MP",
  "MQ",
  "MR",
  "MS",
  "MT",
  "MU",
  "MV",
  "MW",
  "MX",
  "MY",
  "MZ",
  "NA",
  "NC",
  "NE",
  "NF",
  "NG",
  "NI",
  "NL",
  "NO",
  "NP",
  "NR",
  "NU",
  "NZ",
  "OM",
  "PA",
  "PE",
  "PF",
  "PG",
  "PH",
  "PK",
  "PL",
  "PM",
  "PN",
  "PR",
  "PS",
  "PT",
  "PW",
  "PY",
  "QA",
  "RE",
  "RO",
  "RS",
  "RU",
  "RW",
  "SA",
  "SB",
  "SC",
  "SD",
  "SE",
  "SG",
  "SH",
  "SI",
  "SJ",
  "SK",
  "SL",
  "SM",
  "SN",
  "SO",
  "SR",
  "SS",
  "ST",
  "SV",
  "SX",
  "SY",
  "SZ",
  "TA",
  "TC",
  "TD",
  "TF",
  "TG",
  "TH",
  "TJ",
  "TK",
  "TL",
  "TM",
  "TN",
  "TO",
  "TR",
  "TT",
  "TV",
  "TW",
  "TZ",
  "UA",
  "UG",
  "UM",
  "US",
  "UY",
  "UZ",
  "VA",
  "VC",
  "VE",
  "VG",
  "VI",
  "VN",
  "VU",
  "WF",
  "WS",
  "XK",
  "YE",
  "YT",
  "ZA",
  "ZM",
  "ZW"
];
var EMOJI_CATEGORIES = [
  {
    id: "smileys",
    label: "\u{1F600}",
    items: [
      "\u{1F600}",
      "\u{1F603}",
      "\u{1F604}",
      "\u{1F601}",
      "\u{1F606}",
      "\u{1F605}",
      "\u{1F923}",
      "\u{1F602}",
      "\u{1F642}",
      "\u{1F643}",
      "\u{1F609}",
      "\u{1F60A}",
      "\u{1F607}",
      "\u{1F970}",
      "\u{1F60D}",
      "\u{1F929}",
      "\u{1F618}",
      "\u{1F617}",
      "\u263A\uFE0F",
      "\u{1F61A}",
      "\u{1F619}",
      "\u{1F972}",
      "\u{1F60B}",
      "\u{1F61B}",
      "\u{1F61C}",
      "\u{1F92A}",
      "\u{1F61D}",
      "\u{1F911}",
      "\u{1F917}",
      "\u{1F92D}",
      "\u{1FAE2}",
      "\u{1FAE3}",
      "\u{1F92B}",
      "\u{1F914}",
      "\u{1FAE1}",
      "\u{1F910}",
      "\u{1F928}",
      "\u{1F610}",
      "\u{1F611}",
      "\u{1F636}",
      "\u{1FAE5}",
      "\u{1F636}\u200D\u{1F32B}\uFE0F",
      "\u{1F60F}",
      "\u{1F612}",
      "\u{1F644}",
      "\u{1F62C}",
      "\u{1F62E}\u200D\u{1F4A8}",
      "\u{1F925}",
      "\u{1F60C}",
      "\u{1F614}",
      "\u{1F62A}",
      "\u{1F924}",
      "\u{1F634}",
      "\u{1F637}",
      "\u{1F912}",
      "\u{1F915}",
      "\u{1F922}",
      "\u{1F92E}",
      "\u{1F927}",
      "\u{1F975}",
      "\u{1F976}",
      "\u{1F974}",
      "\u{1F635}",
      "\u{1F635}\u200D\u{1F4AB}",
      "\u{1F92F}",
      "\u{1F920}",
      "\u{1F973}",
      "\u{1F978}",
      "\u{1F60E}",
      "\u{1F913}",
      "\u{1F9D0}",
      "\u{1F615}",
      "\u{1FAE4}",
      "\u{1F61F}",
      "\u{1F641}",
      "\u2639\uFE0F",
      "\u{1F62E}",
      "\u{1F62F}",
      "\u{1F632}",
      "\u{1F633}",
      "\u{1F97A}",
      "\u{1F979}",
      "\u{1F626}",
      "\u{1F627}",
      "\u{1F628}",
      "\u{1F630}",
      "\u{1F625}",
      "\u{1F622}",
      "\u{1F62D}",
      "\u{1F631}",
      "\u{1F616}",
      "\u{1F623}",
      "\u{1F61E}",
      "\u{1F613}",
      "\u{1F629}",
      "\u{1F62B}",
      "\u{1F971}",
      "\u{1F624}",
      "\u{1F621}",
      "\u{1F620}",
      "\u{1F92C}",
      "\u{1F608}",
      "\u{1F47F}",
      "\u{1F480}",
      "\u2620\uFE0F",
      "\u{1F4A9}",
      "\u{1F921}",
      "\u{1F479}",
      "\u{1F47A}",
      "\u{1F47B}",
      "\u{1F47D}",
      "\u{1F47E}",
      "\u{1F916}",
      "\u{1F63A}",
      "\u{1F638}",
      "\u{1F639}",
      "\u{1F63B}",
      "\u{1F63C}",
      "\u{1F63D}",
      "\u{1F640}",
      "\u{1F63F}",
      "\u{1F63E}",
      "\u{1F648}",
      "\u{1F649}",
      "\u{1F64A}",
      "\u{1F48C}",
      "\u{1F498}",
      "\u{1F49D}",
      "\u{1F496}",
      "\u{1F497}",
      "\u{1F493}",
      "\u{1F49E}",
      "\u{1F495}",
      "\u{1F49F}",
      "\u2763\uFE0F",
      "\u{1F494}",
      "\u2764\uFE0F\u200D\u{1F525}",
      "\u2764\uFE0F\u200D\u{1FA79}",
      "\u2764\uFE0F",
      "\u{1FA77}",
      "\u{1F9E1}",
      "\u{1F49B}",
      "\u{1F49A}",
      "\u{1F499}",
      "\u{1FA75}",
      "\u{1F49C}",
      "\u{1F90E}",
      "\u{1F5A4}",
      "\u{1FA76}",
      "\u{1F90D}",
      "\u{1F48B}",
      "\u{1F4AF}",
      "\u{1F4A2}",
      "\u{1F4A5}",
      "\u{1F4AB}",
      "\u{1F4A6}",
      "\u{1F4A8}",
      "\u{1F573}\uFE0F",
      "\u{1F4AC}",
      "\u{1F441}\uFE0F\u200D\u{1F5E8}\uFE0F",
      "\u{1F5E8}\uFE0F",
      "\u{1F5EF}\uFE0F",
      "\u{1F4AD}",
      "\u{1F4A4}"
    ]
  },
  {
    id: "gestures",
    label: "\u{1F44B}",
    items: [
      "\u{1F44B}",
      "\u{1F91A}",
      "\u{1F590}\uFE0F",
      "\u270B",
      "\u{1F596}",
      "\u{1FAF1}",
      "\u{1FAF2}",
      "\u{1FAF3}",
      "\u{1FAF4}",
      "\u{1FAF7}",
      "\u{1FAF8}",
      "\u{1F44C}",
      "\u{1F90C}",
      "\u{1F90F}",
      "\u270C\uFE0F",
      "\u{1F91E}",
      "\u{1FAF0}",
      "\u{1F91F}",
      "\u{1F918}",
      "\u{1F919}",
      "\u{1F448}",
      "\u{1F449}",
      "\u{1F446}",
      "\u{1F595}",
      "\u{1F447}",
      "\u261D\uFE0F",
      "\u{1FAF5}",
      "\u{1F44D}",
      "\u{1F44E}",
      "\u270A",
      "\u{1F44A}",
      "\u{1F91B}",
      "\u{1F91C}",
      "\u{1F44F}",
      "\u{1F64C}",
      "\u{1FAF6}",
      "\u{1F450}",
      "\u{1F932}",
      "\u{1F91D}",
      "\u{1F64F}",
      "\u270D\uFE0F",
      "\u{1F485}",
      "\u{1F933}",
      "\u{1F4AA}",
      "\u{1F9BE}",
      "\u{1F9BF}",
      "\u{1F9B5}",
      "\u{1F9B6}",
      "\u{1F442}",
      "\u{1F9BB}",
      "\u{1F443}",
      "\u{1F9E0}",
      "\u{1FAC0}",
      "\u{1FAC1}",
      "\u{1F9B7}",
      "\u{1F9B4}",
      "\u{1F440}",
      "\u{1F441}\uFE0F",
      "\u{1F445}",
      "\u{1F444}",
      "\u{1FAE6}",
      "\u{1F476}",
      "\u{1F467}",
      "\u{1F9D2}",
      "\u{1F466}",
      "\u{1F469}",
      "\u{1F9D1}",
      "\u{1F468}",
      "\u{1F469}\u200D\u{1F9B1}",
      "\u{1F9D1}\u200D\u{1F9B1}",
      "\u{1F468}\u200D\u{1F9B1}",
      "\u{1F469}\u200D\u{1F9B0}",
      "\u{1F9D1}\u200D\u{1F9B0}",
      "\u{1F468}\u200D\u{1F9B0}",
      "\u{1F471}\u200D\u2640\uFE0F",
      "\u{1F471}",
      "\u{1F471}\u200D\u2642\uFE0F",
      "\u{1F469}\u200D\u{1F9B3}",
      "\u{1F9D1}\u200D\u{1F9B3}",
      "\u{1F468}\u200D\u{1F9B3}",
      "\u{1F469}\u200D\u{1F9B2}",
      "\u{1F9D1}\u200D\u{1F9B2}",
      "\u{1F468}\u200D\u{1F9B2}",
      "\u{1F9D4}\u200D\u2640\uFE0F",
      "\u{1F9D4}",
      "\u{1F9D4}\u200D\u2642\uFE0F",
      "\u{1F475}",
      "\u{1F9D3}",
      "\u{1F474}",
      "\u{1F472}",
      "\u{1F473}\u200D\u2640\uFE0F",
      "\u{1F473}",
      "\u{1F473}\u200D\u2642\uFE0F",
      "\u{1F9D5}",
      "\u{1F46E}\u200D\u2640\uFE0F",
      "\u{1F46E}",
      "\u{1F46E}\u200D\u2642\uFE0F",
      "\u{1F477}\u200D\u2640\uFE0F",
      "\u{1F477}",
      "\u{1F477}\u200D\u2642\uFE0F",
      "\u{1F482}\u200D\u2640\uFE0F",
      "\u{1F482}",
      "\u{1F482}\u200D\u2642\uFE0F",
      "\u{1F575}\uFE0F\u200D\u2640\uFE0F",
      "\u{1F575}\uFE0F",
      "\u{1F575}\uFE0F\u200D\u2642\uFE0F",
      "\u{1F469}\u200D\u2695\uFE0F",
      "\u{1F9D1}\u200D\u2695\uFE0F",
      "\u{1F468}\u200D\u2695\uFE0F",
      "\u{1F469}\u200D\u{1F33E}",
      "\u{1F9D1}\u200D\u{1F33E}",
      "\u{1F468}\u200D\u{1F33E}",
      "\u{1F469}\u200D\u{1F373}",
      "\u{1F9D1}\u200D\u{1F373}",
      "\u{1F468}\u200D\u{1F373}",
      "\u{1F469}\u200D\u{1F393}",
      "\u{1F9D1}\u200D\u{1F393}",
      "\u{1F468}\u200D\u{1F393}",
      "\u{1F469}\u200D\u{1F3A4}",
      "\u{1F9D1}\u200D\u{1F3A4}",
      "\u{1F468}\u200D\u{1F3A4}",
      "\u{1F469}\u200D\u{1F3EB}",
      "\u{1F9D1}\u200D\u{1F3EB}",
      "\u{1F468}\u200D\u{1F3EB}",
      "\u{1F469}\u200D\u{1F3ED}",
      "\u{1F9D1}\u200D\u{1F3ED}",
      "\u{1F468}\u200D\u{1F3ED}",
      "\u{1F469}\u200D\u{1F4BB}",
      "\u{1F9D1}\u200D\u{1F4BB}",
      "\u{1F468}\u200D\u{1F4BB}",
      "\u{1F469}\u200D\u{1F4BC}",
      "\u{1F9D1}\u200D\u{1F4BC}",
      "\u{1F468}\u200D\u{1F4BC}",
      "\u{1F469}\u200D\u{1F527}",
      "\u{1F9D1}\u200D\u{1F527}",
      "\u{1F468}\u200D\u{1F527}",
      "\u{1F469}\u200D\u{1F52C}",
      "\u{1F9D1}\u200D\u{1F52C}",
      "\u{1F468}\u200D\u{1F52C}",
      "\u{1F469}\u200D\u{1F3A8}",
      "\u{1F9D1}\u200D\u{1F3A8}",
      "\u{1F468}\u200D\u{1F3A8}",
      "\u{1F469}\u200D\u{1F692}",
      "\u{1F9D1}\u200D\u{1F692}",
      "\u{1F468}\u200D\u{1F692}",
      "\u{1F469}\u200D\u2708\uFE0F",
      "\u{1F9D1}\u200D\u2708\uFE0F",
      "\u{1F468}\u200D\u2708\uFE0F",
      "\u{1F469}\u200D\u{1F680}",
      "\u{1F9D1}\u200D\u{1F680}",
      "\u{1F468}\u200D\u{1F680}",
      "\u{1F469}\u200D\u2696\uFE0F",
      "\u{1F9D1}\u200D\u2696\uFE0F",
      "\u{1F468}\u200D\u2696\uFE0F",
      "\u{1F470}\u200D\u2640\uFE0F",
      "\u{1F470}",
      "\u{1F470}\u200D\u2642\uFE0F",
      "\u{1F935}\u200D\u2640\uFE0F",
      "\u{1F935}",
      "\u{1F935}\u200D\u2642\uFE0F",
      "\u{1F478}",
      "\u{1FAC5}",
      "\u{1F934}",
      "\u{1F977}",
      "\u{1F9B8}\u200D\u2640\uFE0F",
      "\u{1F9B8}",
      "\u{1F9B8}\u200D\u2642\uFE0F",
      "\u{1F9B9}\u200D\u2640\uFE0F",
      "\u{1F9B9}",
      "\u{1F9B9}\u200D\u2642\uFE0F",
      "\u{1F936}",
      "\u{1F9D1}\u200D\u{1F384}",
      "\u{1F385}",
      "\u{1F9D9}\u200D\u2640\uFE0F",
      "\u{1F9D9}",
      "\u{1F9D9}\u200D\u2642\uFE0F",
      "\u{1F9DD}\u200D\u2640\uFE0F",
      "\u{1F9DD}",
      "\u{1F9DD}\u200D\u2642\uFE0F",
      "\u{1F9DB}\u200D\u2640\uFE0F",
      "\u{1F9DB}",
      "\u{1F9DB}\u200D\u2642\uFE0F",
      "\u{1F9DF}\u200D\u2640\uFE0F",
      "\u{1F9DF}",
      "\u{1F9DF}\u200D\u2642\uFE0F",
      "\u{1F9DE}\u200D\u2640\uFE0F",
      "\u{1F9DE}",
      "\u{1F9DE}\u200D\u2642\uFE0F",
      "\u{1F9DC}\u200D\u2640\uFE0F",
      "\u{1F9DC}",
      "\u{1F9DC}\u200D\u2642\uFE0F",
      "\u{1F9DA}\u200D\u2640\uFE0F",
      "\u{1F9DA}",
      "\u{1F9DA}\u200D\u2642\uFE0F",
      "\u{1F47C}",
      "\u{1F930}",
      "\u{1FAC4}",
      "\u{1FAC3}",
      "\u{1F931}",
      "\u{1F469}\u200D\u{1F37C}",
      "\u{1F9D1}\u200D\u{1F37C}",
      "\u{1F468}\u200D\u{1F37C}",
      "\u{1F647}\u200D\u2640\uFE0F",
      "\u{1F647}",
      "\u{1F647}\u200D\u2642\uFE0F",
      "\u{1F481}\u200D\u2640\uFE0F",
      "\u{1F481}",
      "\u{1F481}\u200D\u2642\uFE0F",
      "\u{1F645}\u200D\u2640\uFE0F",
      "\u{1F645}",
      "\u{1F645}\u200D\u2642\uFE0F",
      "\u{1F646}\u200D\u2640\uFE0F",
      "\u{1F646}",
      "\u{1F646}\u200D\u2642\uFE0F",
      "\u{1F64B}\u200D\u2640\uFE0F",
      "\u{1F64B}",
      "\u{1F64B}\u200D\u2642\uFE0F",
      "\u{1F9CF}\u200D\u2640\uFE0F",
      "\u{1F9CF}",
      "\u{1F9CF}\u200D\u2642\uFE0F",
      "\u{1F926}\u200D\u2640\uFE0F",
      "\u{1F926}",
      "\u{1F926}\u200D\u2642\uFE0F",
      "\u{1F937}\u200D\u2640\uFE0F",
      "\u{1F937}",
      "\u{1F937}\u200D\u2642\uFE0F",
      "\u{1F64E}\u200D\u2640\uFE0F",
      "\u{1F64E}",
      "\u{1F64E}\u200D\u2642\uFE0F",
      "\u{1F64D}\u200D\u2640\uFE0F",
      "\u{1F64D}",
      "\u{1F64D}\u200D\u2642\uFE0F",
      "\u{1F487}\u200D\u2640\uFE0F",
      "\u{1F487}",
      "\u{1F487}\u200D\u2642\uFE0F",
      "\u{1F486}\u200D\u2640\uFE0F",
      "\u{1F486}",
      "\u{1F486}\u200D\u2642\uFE0F",
      "\u{1F9D6}\u200D\u2640\uFE0F",
      "\u{1F9D6}",
      "\u{1F9D6}\u200D\u2642\uFE0F",
      "\u{1F483}",
      "\u{1F57A}",
      "\u{1F46F}\u200D\u2640\uFE0F",
      "\u{1F46F}",
      "\u{1F46F}\u200D\u2642\uFE0F",
      "\u{1F574}\uFE0F",
      "\u{1F469}\u200D\u{1F9BD}",
      "\u{1F9D1}\u200D\u{1F9BD}",
      "\u{1F468}\u200D\u{1F9BD}",
      "\u{1F469}\u200D\u{1F9BC}",
      "\u{1F9D1}\u200D\u{1F9BC}",
      "\u{1F468}\u200D\u{1F9BC}",
      "\u{1F6B6}\u200D\u2640\uFE0F",
      "\u{1F6B6}",
      "\u{1F6B6}\u200D\u2642\uFE0F",
      "\u{1F469}\u200D\u{1F9AF}",
      "\u{1F9D1}\u200D\u{1F9AF}",
      "\u{1F468}\u200D\u{1F9AF}",
      "\u{1F9CE}\u200D\u2640\uFE0F",
      "\u{1F9CE}",
      "\u{1F9CE}\u200D\u2642\uFE0F",
      "\u{1F3C3}\u200D\u2640\uFE0F",
      "\u{1F3C3}",
      "\u{1F3C3}\u200D\u2642\uFE0F",
      "\u{1F9CD}\u200D\u2640\uFE0F",
      "\u{1F9CD}",
      "\u{1F9CD}\u200D\u2642\uFE0F",
      "\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F468}",
      "\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F469}",
      "\u{1F491}",
      "\u{1F468}\u200D\u2764\uFE0F\u200D\u{1F468}",
      "\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F48B}\u200D\u{1F468}",
      "\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F48B}\u200D\u{1F469}",
      "\u{1F48F}",
      "\u{1F468}\u200D\u2764\uFE0F\u200D\u{1F48B}\u200D\u{1F468}",
      "\u{1F46A}",
      "\u{1F468}\u200D\u{1F469}\u200D\u{1F466}",
      "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}",
      "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}",
      "\u{1F468}\u200D\u{1F469}\u200D\u{1F466}\u200D\u{1F466}",
      "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F467}",
      "\u{1F468}\u200D\u{1F468}\u200D\u{1F466}",
      "\u{1F468}\u200D\u{1F468}\u200D\u{1F467}",
      "\u{1F468}\u200D\u{1F468}\u200D\u{1F467}\u200D\u{1F466}",
      "\u{1F468}\u200D\u{1F468}\u200D\u{1F466}\u200D\u{1F466}",
      "\u{1F468}\u200D\u{1F468}\u200D\u{1F467}\u200D\u{1F467}",
      "\u{1F469}\u200D\u{1F469}\u200D\u{1F466}",
      "\u{1F469}\u200D\u{1F469}\u200D\u{1F467}",
      "\u{1F469}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}",
      "\u{1F469}\u200D\u{1F469}\u200D\u{1F466}\u200D\u{1F466}",
      "\u{1F469}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F467}",
      "\u{1FAA2}",
      "\u{1F9F6}",
      "\u{1F9F5}",
      "\u{1FAA1}",
      "\u{1F9E5}",
      "\u{1F97C}",
      "\u{1F9BA}",
      "\u{1F45A}",
      "\u{1F455}",
      "\u{1F456}",
      "\u{1FA72}",
      "\u{1FA73}",
      "\u{1F454}",
      "\u{1F457}",
      "\u{1F459}",
      "\u{1FA71}",
      "\u{1F458}",
      "\u{1F97B}",
      "\u{1FA74}",
      "\u{1F97F}",
      "\u{1F460}",
      "\u{1F461}",
      "\u{1F462}",
      "\u{1F45E}",
      "\u{1F45F}",
      "\u{1F97E}",
      "\u{1F9E6}",
      "\u{1F9E4}",
      "\u{1F9E3}",
      "\u{1F3A9}",
      "\u{1F9E2}",
      "\u{1F452}",
      "\u{1F393}",
      "\u26D1\uFE0F",
      "\u{1FA96}",
      "\u{1F451}",
      "\u{1F48D}",
      "\u{1F45D}",
      "\u{1F45B}",
      "\u{1F45C}",
      "\u{1F4BC}",
      "\u{1F392}",
      "\u{1F9F3}",
      "\u{1F453}",
      "\u{1F576}\uFE0F",
      "\u{1F97D}",
      "\u{1F302}"
    ]
  },
  {
    id: "animals",
    label: "\u{1F436}",
    items: [
      "\u{1F436}",
      "\u{1F431}",
      "\u{1F42D}",
      "\u{1F439}",
      "\u{1F430}",
      "\u{1F98A}",
      "\u{1F43B}",
      "\u{1F43C}",
      "\u{1F43B}\u200D\u2744\uFE0F",
      "\u{1F428}",
      "\u{1F42F}",
      "\u{1F981}",
      "\u{1F42E}",
      "\u{1F437}",
      "\u{1F43D}",
      "\u{1F438}",
      "\u{1F435}",
      "\u{1F648}",
      "\u{1F649}",
      "\u{1F64A}",
      "\u{1F412}",
      "\u{1F414}",
      "\u{1F427}",
      "\u{1F426}",
      "\u{1F424}",
      "\u{1F423}",
      "\u{1F425}",
      "\u{1F986}",
      "\u{1F985}",
      "\u{1F989}",
      "\u{1F987}",
      "\u{1F43A}",
      "\u{1F417}",
      "\u{1F434}",
      "\u{1F984}",
      "\u{1F41D}",
      "\u{1FAB1}",
      "\u{1F41B}",
      "\u{1F98B}",
      "\u{1F40C}",
      "\u{1F41E}",
      "\u{1F41C}",
      "\u{1FAB0}",
      "\u{1FAB2}",
      "\u{1FAB3}",
      "\u{1F99F}",
      "\u{1F997}",
      "\u{1F577}\uFE0F",
      "\u{1F578}\uFE0F",
      "\u{1F982}",
      "\u{1F422}",
      "\u{1F40D}",
      "\u{1F98E}",
      "\u{1F996}",
      "\u{1F995}",
      "\u{1F419}",
      "\u{1F991}",
      "\u{1F990}",
      "\u{1F99E}",
      "\u{1F980}",
      "\u{1FAB8}",
      "\u{1F421}",
      "\u{1F420}",
      "\u{1F41F}",
      "\u{1F42C}",
      "\u{1F433}",
      "\u{1F40B}",
      "\u{1F988}",
      "\u{1F9AD}",
      "\u{1F40A}",
      "\u{1F405}",
      "\u{1F406}",
      "\u{1F993}",
      "\u{1F98D}",
      "\u{1F9A7}",
      "\u{1F9A3}",
      "\u{1F418}",
      "\u{1F99B}",
      "\u{1F98F}",
      "\u{1F42A}",
      "\u{1F42B}",
      "\u{1F992}",
      "\u{1F998}",
      "\u{1F9AC}",
      "\u{1F403}",
      "\u{1F402}",
      "\u{1F404}",
      "\u{1F40E}",
      "\u{1F416}",
      "\u{1F40F}",
      "\u{1F411}",
      "\u{1F999}",
      "\u{1F410}",
      "\u{1F98C}",
      "\u{1F415}",
      "\u{1F429}",
      "\u{1F9AE}",
      "\u{1F415}\u200D\u{1F9BA}",
      "\u{1F408}",
      "\u{1F408}\u200D\u2B1B",
      "\u{1FAB6}",
      "\u{1FABD}",
      "\u{1F413}",
      "\u{1F983}",
      "\u{1F9A4}",
      "\u{1F99A}",
      "\u{1F99C}",
      "\u{1F9A2}",
      "\u{1F9A9}",
      "\u{1F54A}\uFE0F",
      "\u{1F407}",
      "\u{1F99D}",
      "\u{1F9A8}",
      "\u{1F9A1}",
      "\u{1F9AB}",
      "\u{1F9A6}",
      "\u{1F9A5}",
      "\u{1F401}",
      "\u{1F400}",
      "\u{1F43F}\uFE0F",
      "\u{1F994}",
      "\u{1F43E}",
      "\u{1F409}",
      "\u{1F432}",
      "\u{1F335}",
      "\u{1F384}",
      "\u{1F332}",
      "\u{1F333}",
      "\u{1F334}",
      "\u{1FAB5}",
      "\u{1F331}",
      "\u{1F33F}",
      "\u2618\uFE0F",
      "\u{1F340}",
      "\u{1F38D}",
      "\u{1FAB4}",
      "\u{1F38B}",
      "\u{1F343}",
      "\u{1F342}",
      "\u{1F341}",
      "\u{1FABA}",
      "\u{1FAB9}",
      "\u{1F344}",
      "\u{1F41A}",
      "\u{1FAA8}",
      "\u{1F33E}",
      "\u{1F490}",
      "\u{1F337}",
      "\u{1F339}",
      "\u{1F940}",
      "\u{1F33A}",
      "\u{1F338}",
      "\u{1F33C}",
      "\u{1F33B}",
      "\u{1F31E}",
      "\u{1F31D}",
      "\u{1F31B}",
      "\u{1F31C}",
      "\u{1F31A}",
      "\u{1F315}",
      "\u{1F316}",
      "\u{1F317}",
      "\u{1F318}",
      "\u{1F311}",
      "\u{1F312}",
      "\u{1F313}",
      "\u{1F314}",
      "\u{1F319}",
      "\u{1F30E}",
      "\u{1F30D}",
      "\u{1F30F}",
      "\u{1FA90}",
      "\u{1F4AB}",
      "\u2B50",
      "\u{1F31F}",
      "\u2728",
      "\u26A1",
      "\u2604\uFE0F",
      "\u{1F4A5}",
      "\u{1F525}",
      "\u{1F32A}\uFE0F",
      "\u{1F308}",
      "\u2600\uFE0F",
      "\u{1F324}\uFE0F",
      "\u26C5",
      "\u{1F325}\uFE0F",
      "\u2601\uFE0F",
      "\u{1F326}\uFE0F",
      "\u{1F327}\uFE0F",
      "\u26C8\uFE0F",
      "\u{1F329}\uFE0F",
      "\u{1F328}\uFE0F",
      "\u2744\uFE0F",
      "\u2603\uFE0F",
      "\u26C4",
      "\u{1F32C}\uFE0F",
      "\u{1F4A8}",
      "\u{1F4A7}",
      "\u{1F4A6}",
      "\u{1FAE7}",
      "\u2614",
      "\u2602\uFE0F",
      "\u{1F30A}",
      "\u{1F32B}\uFE0F"
    ]
  },
  {
    id: "food",
    label: "\u{1F34E}",
    items: [
      "\u{1F34F}",
      "\u{1F34E}",
      "\u{1F350}",
      "\u{1F34A}",
      "\u{1F34B}",
      "\u{1F34C}",
      "\u{1F349}",
      "\u{1F347}",
      "\u{1F353}",
      "\u{1FAD0}",
      "\u{1F348}",
      "\u{1F352}",
      "\u{1F351}",
      "\u{1F96D}",
      "\u{1F34D}",
      "\u{1F965}",
      "\u{1F95D}",
      "\u{1F345}",
      "\u{1F346}",
      "\u{1F951}",
      "\u{1F966}",
      "\u{1FADB}",
      "\u{1F96C}",
      "\u{1F952}",
      "\u{1F336}\uFE0F",
      "\u{1FAD1}",
      "\u{1F33D}",
      "\u{1F955}",
      "\u{1FAD2}",
      "\u{1F9C4}",
      "\u{1F9C5}",
      "\u{1F954}",
      "\u{1F360}",
      "\u{1FAD8}",
      "\u{1F950}",
      "\u{1F96F}",
      "\u{1F35E}",
      "\u{1F956}",
      "\u{1F968}",
      "\u{1F9C0}",
      "\u{1F95A}",
      "\u{1F373}",
      "\u{1F9C8}",
      "\u{1F95E}",
      "\u{1F9C7}",
      "\u{1F953}",
      "\u{1F969}",
      "\u{1F357}",
      "\u{1F356}",
      "\u{1F9B4}",
      "\u{1F32D}",
      "\u{1F354}",
      "\u{1F35F}",
      "\u{1F355}",
      "\u{1FAD3}",
      "\u{1F96A}",
      "\u{1F959}",
      "\u{1F9C6}",
      "\u{1F32E}",
      "\u{1F32F}",
      "\u{1FAD4}",
      "\u{1F957}",
      "\u{1F958}",
      "\u{1FAD5}",
      "\u{1F96B}",
      "\u{1F35D}",
      "\u{1F35C}",
      "\u{1F372}",
      "\u{1F35B}",
      "\u{1F363}",
      "\u{1F371}",
      "\u{1F95F}",
      "\u{1F9AA}",
      "\u{1F364}",
      "\u{1F359}",
      "\u{1F35A}",
      "\u{1F358}",
      "\u{1F365}",
      "\u{1F960}",
      "\u{1F96E}",
      "\u{1F362}",
      "\u{1F361}",
      "\u{1F367}",
      "\u{1F368}",
      "\u{1F366}",
      "\u{1F967}",
      "\u{1F9C1}",
      "\u{1F370}",
      "\u{1F382}",
      "\u{1F36E}",
      "\u{1F36D}",
      "\u{1F36C}",
      "\u{1F36B}",
      "\u{1F37F}",
      "\u{1F369}",
      "\u{1F36A}",
      "\u{1F330}",
      "\u{1F95C}",
      "\u{1F36F}",
      "\u{1F95B}",
      "\u{1F37C}",
      "\u{1FAD6}",
      "\u2615",
      "\u{1F375}",
      "\u{1F9C3}",
      "\u{1F964}",
      "\u{1F9CB}",
      "\u{1F376}",
      "\u{1F37A}",
      "\u{1F37B}",
      "\u{1F942}",
      "\u{1F377}",
      "\u{1F943}",
      "\u{1F378}",
      "\u{1F379}",
      "\u{1F9C9}",
      "\u{1F37E}",
      "\u{1F9CA}",
      "\u{1F944}",
      "\u{1F374}",
      "\u{1F37D}\uFE0F",
      "\u{1F963}",
      "\u{1F961}",
      "\u{1F962}",
      "\u{1F9C2}"
    ]
  },
  {
    id: "travel",
    label: "\u2708\uFE0F",
    items: [
      "\u{1F697}",
      "\u{1F695}",
      "\u{1F699}",
      "\u{1F68C}",
      "\u{1F68E}",
      "\u{1F3CE}\uFE0F",
      "\u{1F693}",
      "\u{1F691}",
      "\u{1F692}",
      "\u{1F690}",
      "\u{1F6FB}",
      "\u{1F69A}",
      "\u{1F69B}",
      "\u{1F69C}",
      "\u{1F9AF}",
      "\u{1F9BD}",
      "\u{1F9BC}",
      "\u{1F6F4}",
      "\u{1F6B2}",
      "\u{1F6F5}",
      "\u{1F3CD}\uFE0F",
      "\u{1F6FA}",
      "\u{1F6A8}",
      "\u{1F694}",
      "\u{1F68D}",
      "\u{1F698}",
      "\u{1F696}",
      "\u{1F6DE}",
      "\u{1F6A1}",
      "\u{1F6A0}",
      "\u{1F69F}",
      "\u{1F683}",
      "\u{1F68B}",
      "\u{1F69E}",
      "\u{1F69D}",
      "\u{1F684}",
      "\u{1F685}",
      "\u{1F688}",
      "\u{1F682}",
      "\u{1F686}",
      "\u{1F687}",
      "\u{1F68A}",
      "\u{1F689}",
      "\u2708\uFE0F",
      "\u{1F6EB}",
      "\u{1F6EC}",
      "\u{1F6E9}\uFE0F",
      "\u{1F4BA}",
      "\u{1F6F0}\uFE0F",
      "\u{1F680}",
      "\u{1F6F8}",
      "\u{1F681}",
      "\u{1F6F6}",
      "\u26F5",
      "\u{1F6A4}",
      "\u{1F6E5}\uFE0F",
      "\u{1F6F3}\uFE0F",
      "\u26F4\uFE0F",
      "\u{1F6A2}",
      "\u{1F6DF}",
      "\u2693",
      "\u{1FA9D}",
      "\u26FD",
      "\u{1F6A7}",
      "\u{1F6A6}",
      "\u{1F6A5}",
      "\u{1F68F}",
      "\u{1F5FA}\uFE0F",
      "\u{1F5FF}",
      "\u{1F5FD}",
      "\u{1F5FC}",
      "\u{1F3F0}",
      "\u{1F3EF}",
      "\u{1F3DF}\uFE0F",
      "\u{1F3A1}",
      "\u{1F3A2}",
      "\u{1F3A0}",
      "\u26F2",
      "\u26F1\uFE0F",
      "\u{1F3D6}\uFE0F",
      "\u{1F3DD}\uFE0F",
      "\u{1F3DC}\uFE0F",
      "\u{1F30B}",
      "\u26F0\uFE0F",
      "\u{1F3D4}\uFE0F",
      "\u{1F5FB}",
      "\u{1F3D5}\uFE0F",
      "\u26FA",
      "\u{1F3E0}",
      "\u{1F3E1}",
      "\u{1F3D8}\uFE0F",
      "\u{1F3DA}\uFE0F",
      "\u{1F3D7}\uFE0F",
      "\u{1F3ED}",
      "\u{1F3E2}",
      "\u{1F3EC}",
      "\u{1F3E3}",
      "\u{1F3E4}",
      "\u{1F3E5}",
      "\u{1F3E6}",
      "\u{1F3E8}",
      "\u{1F3EA}",
      "\u{1F3EB}",
      "\u{1F3E9}",
      "\u{1F492}",
      "\u{1F3DB}\uFE0F",
      "\u26EA",
      "\u{1F54C}",
      "\u{1F54D}",
      "\u{1F6D5}",
      "\u{1F54B}",
      "\u26E9\uFE0F",
      "\u{1F6E4}\uFE0F",
      "\u{1F6E3}\uFE0F",
      "\u{1F5FE}",
      "\u{1F391}",
      "\u{1F3DE}\uFE0F",
      "\u{1F305}",
      "\u{1F304}",
      "\u{1F320}",
      "\u{1F387}",
      "\u{1F386}",
      "\u{1F307}",
      "\u{1F306}",
      "\u{1F3D9}\uFE0F",
      "\u{1F303}",
      "\u{1F30C}",
      "\u{1F309}",
      "\u{1F301}"
    ]
  },
  {
    id: "activities",
    label: "\u26BD",
    items: [
      "\u26BD",
      "\u{1F3C0}",
      "\u{1F3C8}",
      "\u26BE",
      "\u{1F94E}",
      "\u{1F3BE}",
      "\u{1F3D0}",
      "\u{1F3C9}",
      "\u{1F94F}",
      "\u{1F3B1}",
      "\u{1FA80}",
      "\u{1F3D3}",
      "\u{1F3F8}",
      "\u{1F3D2}",
      "\u{1F3D1}",
      "\u{1F94D}",
      "\u{1F3CF}",
      "\u{1FA83}",
      "\u{1F945}",
      "\u26F3",
      "\u{1FA81}",
      "\u{1F3F9}",
      "\u{1F3A3}",
      "\u{1F93F}",
      "\u{1F94A}",
      "\u{1F94B}",
      "\u{1F3BD}",
      "\u{1F6F9}",
      "\u{1F6FC}",
      "\u{1F6F7}",
      "\u26F8\uFE0F",
      "\u{1F94C}",
      "\u{1F3BF}",
      "\u26F7\uFE0F",
      "\u{1F3C2}",
      "\u{1FA82}",
      "\u{1F3CB}\uFE0F\u200D\u2640\uFE0F",
      "\u{1F3CB}\uFE0F",
      "\u{1F3CB}\uFE0F\u200D\u2642\uFE0F",
      "\u{1F93C}\u200D\u2640\uFE0F",
      "\u{1F93C}",
      "\u{1F93C}\u200D\u2642\uFE0F",
      "\u{1F938}\u200D\u2640\uFE0F",
      "\u{1F938}",
      "\u{1F938}\u200D\u2642\uFE0F",
      "\u26F9\uFE0F\u200D\u2640\uFE0F",
      "\u26F9\uFE0F",
      "\u26F9\uFE0F\u200D\u2642\uFE0F",
      "\u{1F93A}",
      "\u{1F93E}\u200D\u2640\uFE0F",
      "\u{1F93E}",
      "\u{1F93E}\u200D\u2642\uFE0F",
      "\u{1F3CC}\uFE0F\u200D\u2640\uFE0F",
      "\u{1F3CC}\uFE0F",
      "\u{1F3CC}\uFE0F\u200D\u2642\uFE0F",
      "\u{1F3C7}",
      "\u{1F9D8}\u200D\u2640\uFE0F",
      "\u{1F9D8}",
      "\u{1F9D8}\u200D\u2642\uFE0F",
      "\u{1F3C4}\u200D\u2640\uFE0F",
      "\u{1F3C4}",
      "\u{1F3C4}\u200D\u2642\uFE0F",
      "\u{1F3CA}\u200D\u2640\uFE0F",
      "\u{1F3CA}",
      "\u{1F3CA}\u200D\u2642\uFE0F",
      "\u{1F93D}\u200D\u2640\uFE0F",
      "\u{1F93D}",
      "\u{1F93D}\u200D\u2642\uFE0F",
      "\u{1F6A3}\u200D\u2640\uFE0F",
      "\u{1F6A3}",
      "\u{1F6A3}\u200D\u2642\uFE0F",
      "\u{1F9D7}\u200D\u2640\uFE0F",
      "\u{1F9D7}",
      "\u{1F9D7}\u200D\u2642\uFE0F",
      "\u{1F6B5}\u200D\u2640\uFE0F",
      "\u{1F6B5}",
      "\u{1F6B5}\u200D\u2642\uFE0F",
      "\u{1F6B4}\u200D\u2640\uFE0F",
      "\u{1F6B4}",
      "\u{1F6B4}\u200D\u2642\uFE0F",
      "\u{1F3C6}",
      "\u{1F947}",
      "\u{1F948}",
      "\u{1F949}",
      "\u{1F3C5}",
      "\u{1F396}\uFE0F",
      "\u{1F3F5}\uFE0F",
      "\u{1F397}\uFE0F",
      "\u{1F3AB}",
      "\u{1F39F}\uFE0F",
      "\u{1F3AA}",
      "\u{1F939}\u200D\u2640\uFE0F",
      "\u{1F939}",
      "\u{1F939}\u200D\u2642\uFE0F",
      "\u{1F3AD}",
      "\u{1FA70}",
      "\u{1F3A8}",
      "\u{1F3AC}",
      "\u{1F3A4}",
      "\u{1F3A7}",
      "\u{1F3BC}",
      "\u{1F3B9}",
      "\u{1F941}",
      "\u{1FA98}",
      "\u{1F3B7}",
      "\u{1F3BA}",
      "\u{1FA97}",
      "\u{1F3B8}",
      "\u{1FA95}",
      "\u{1F3BB}",
      "\u{1FA88}",
      "\u{1F3B2}",
      "\u265F\uFE0F",
      "\u{1F3AF}",
      "\u{1F3B3}",
      "\u{1F3AE}",
      "\u{1F3B0}",
      "\u{1F9E9}"
    ]
  },
  {
    id: "objects",
    label: "\u{1F4A1}",
    items: [
      "\u231A",
      "\u{1F4F1}",
      "\u{1F4F2}",
      "\u{1F4BB}",
      "\u2328\uFE0F",
      "\u{1F5A5}\uFE0F",
      "\u{1F5A8}\uFE0F",
      "\u{1F5B1}\uFE0F",
      "\u{1F5B2}\uFE0F",
      "\u{1F579}\uFE0F",
      "\u{1F5DC}\uFE0F",
      "\u{1F4BD}",
      "\u{1F4BE}",
      "\u{1F4BF}",
      "\u{1F4C0}",
      "\u{1F4FC}",
      "\u{1F4F7}",
      "\u{1F4F8}",
      "\u{1F4F9}",
      "\u{1F3A5}",
      "\u{1F4FD}\uFE0F",
      "\u{1F39E}\uFE0F",
      "\u{1F4DE}",
      "\u260E\uFE0F",
      "\u{1F4DF}",
      "\u{1F4E0}",
      "\u{1F4FA}",
      "\u{1F4FB}",
      "\u{1F399}\uFE0F",
      "\u{1F39A}\uFE0F",
      "\u{1F39B}\uFE0F",
      "\u{1F9ED}",
      "\u23F1\uFE0F",
      "\u23F2\uFE0F",
      "\u23F0",
      "\u{1F570}\uFE0F",
      "\u231B",
      "\u23F3",
      "\u{1F4E1}",
      "\u{1F50B}",
      "\u{1FAAB}",
      "\u{1F50C}",
      "\u{1F4A1}",
      "\u{1F526}",
      "\u{1F56F}\uFE0F",
      "\u{1FA94}",
      "\u{1F9EF}",
      "\u{1F6E2}\uFE0F",
      "\u{1F4B8}",
      "\u{1F4B5}",
      "\u{1F4B4}",
      "\u{1F4B6}",
      "\u{1F4B7}",
      "\u{1FA99}",
      "\u{1F4B0}",
      "\u{1F4B3}",
      "\u{1F48E}",
      "\u2696\uFE0F",
      "\u{1FA9C}",
      "\u{1F9F0}",
      "\u{1FA9B}",
      "\u{1F527}",
      "\u{1F528}",
      "\u2692\uFE0F",
      "\u{1F6E0}\uFE0F",
      "\u26CF\uFE0F",
      "\u{1FA9A}",
      "\u{1F529}",
      "\u2699\uFE0F",
      "\u{1FAA4}",
      "\u{1F9F1}",
      "\u26D3\uFE0F",
      "\u{1F9F2}",
      "\u{1F52B}",
      "\u{1F4A3}",
      "\u{1F9E8}",
      "\u{1FA93}",
      "\u{1F52A}",
      "\u{1F5E1}\uFE0F",
      "\u2694\uFE0F",
      "\u{1F6E1}\uFE0F",
      "\u{1F6AC}",
      "\u26B0\uFE0F",
      "\u{1FAA6}",
      "\u26B1\uFE0F",
      "\u{1F3FA}",
      "\u{1F52E}",
      "\u{1F4FF}",
      "\u{1F9FF}",
      "\u{1FAAC}",
      "\u{1F488}",
      "\u2697\uFE0F",
      "\u{1F52D}",
      "\u{1F52C}",
      "\u{1F573}\uFE0F",
      "\u{1FA79}",
      "\u{1FA7A}",
      "\u{1FA7B}",
      "\u{1FA7C}",
      "\u{1F48A}",
      "\u{1F489}",
      "\u{1FA78}",
      "\u{1F9EC}",
      "\u{1F9A0}",
      "\u{1F9EB}",
      "\u{1F9EA}",
      "\u{1F321}\uFE0F",
      "\u{1F9F9}",
      "\u{1FAA0}",
      "\u{1F9FA}",
      "\u{1F9FB}",
      "\u{1F6BD}",
      "\u{1F6B0}",
      "\u{1F6BF}",
      "\u{1F6C1}",
      "\u{1F6C0}",
      "\u{1F9FC}",
      "\u{1FAA5}",
      "\u{1FA92}",
      "\u{1F9FD}",
      "\u{1FAA3}",
      "\u{1F9F4}",
      "\u{1F6CE}\uFE0F",
      "\u{1F511}",
      "\u{1F5DD}\uFE0F",
      "\u{1F6AA}",
      "\u{1FA91}",
      "\u{1F6CB}\uFE0F",
      "\u{1F6CF}\uFE0F",
      "\u{1F6CC}",
      "\u{1F9F8}",
      "\u{1FA86}",
      "\u{1F5BC}\uFE0F",
      "\u{1FA9E}",
      "\u{1FA9F}",
      "\u{1F6CD}\uFE0F",
      "\u{1F6D2}",
      "\u{1F381}",
      "\u{1F388}",
      "\u{1F38F}",
      "\u{1F380}",
      "\u{1FA84}",
      "\u{1FA85}",
      "\u{1F38A}",
      "\u{1F389}",
      "\u{1F38E}",
      "\u{1F3EE}",
      "\u{1F390}",
      "\u{1F9E7}",
      "\u2709\uFE0F",
      "\u{1F4E9}",
      "\u{1F4E8}",
      "\u{1F4E7}",
      "\u{1F48C}",
      "\u{1F4E5}",
      "\u{1F4E4}",
      "\u{1F4E6}",
      "\u{1F3F7}\uFE0F",
      "\u{1FAA7}",
      "\u{1F4EA}",
      "\u{1F4EB}",
      "\u{1F4EC}",
      "\u{1F4ED}",
      "\u{1F4EE}",
      "\u{1F4EF}",
      "\u{1F4DC}",
      "\u{1F4C3}",
      "\u{1F4C4}",
      "\u{1F4D1}",
      "\u{1F9FE}",
      "\u{1F4CA}",
      "\u{1F4C8}",
      "\u{1F4C9}",
      "\u{1F5D2}\uFE0F",
      "\u{1F5D3}\uFE0F",
      "\u{1F4C6}",
      "\u{1F4C5}",
      "\u{1F5D1}\uFE0F",
      "\u{1F4C7}",
      "\u{1F5C3}\uFE0F",
      "\u{1F5F3}\uFE0F",
      "\u{1F5C4}\uFE0F",
      "\u{1F4CB}",
      "\u{1F4C1}",
      "\u{1F4C2}",
      "\u{1F5C2}\uFE0F",
      "\u{1F5DE}\uFE0F",
      "\u{1F4F0}",
      "\u{1F4D3}",
      "\u{1F4D4}",
      "\u{1F4D2}",
      "\u{1F4D5}",
      "\u{1F4D7}",
      "\u{1F4D8}",
      "\u{1F4D9}",
      "\u{1F4DA}",
      "\u{1F4D6}",
      "\u{1F516}",
      "\u{1F9F7}",
      "\u{1F517}",
      "\u{1F4CE}",
      "\u{1F587}\uFE0F",
      "\u{1F4D0}",
      "\u{1F4CF}",
      "\u{1F9EE}",
      "\u{1F4CC}",
      "\u{1F4CD}",
      "\u2702\uFE0F",
      "\u{1F58A}\uFE0F",
      "\u{1F58B}\uFE0F",
      "\u2712\uFE0F",
      "\u{1F58C}\uFE0F",
      "\u{1F58D}\uFE0F",
      "\u{1F4DD}",
      "\u270F\uFE0F",
      "\u{1F50D}",
      "\u{1F50E}",
      "\u{1F50F}",
      "\u{1F510}",
      "\u{1F512}",
      "\u{1F513}"
    ]
  },
  {
    id: "symbols",
    label: "\u2733\uFE0F",
    items: [
      "\u2764\uFE0F",
      "\u{1F9E1}",
      "\u{1F49B}",
      "\u{1F49A}",
      "\u{1F499}",
      "\u{1F49C}",
      "\u{1F5A4}",
      "\u{1F90D}",
      "\u{1F90E}",
      "\u{1F494}",
      "\u2763\uFE0F",
      "\u{1F495}",
      "\u{1F49E}",
      "\u{1F493}",
      "\u{1F497}",
      "\u{1F496}",
      "\u{1F498}",
      "\u{1F49D}",
      "\u{1F49F}",
      "\u262E\uFE0F",
      "\u271D\uFE0F",
      "\u262A\uFE0F",
      "\u{1F549}\uFE0F",
      "\u2638\uFE0F",
      "\u2721\uFE0F",
      "\u{1F52F}",
      "\u{1F54E}",
      "\u262F\uFE0F",
      "\u2626\uFE0F",
      "\u{1F6D0}",
      "\u26CE",
      "\u2648",
      "\u2649",
      "\u264A",
      "\u264B",
      "\u264C",
      "\u264D",
      "\u264E",
      "\u264F",
      "\u2650",
      "\u2651",
      "\u2652",
      "\u2653",
      "\u{1F194}",
      "\u269B\uFE0F",
      "\u{1F251}",
      "\u2622\uFE0F",
      "\u2623\uFE0F",
      "\u{1F4F4}",
      "\u{1F4F3}",
      "\u{1F236}",
      "\u{1F21A}",
      "\u{1F238}",
      "\u{1F23A}",
      "\u{1F237}\uFE0F",
      "\u2734\uFE0F",
      "\u{1F19A}",
      "\u{1F4AE}",
      "\u{1F250}",
      "\u3299\uFE0F",
      "\u3297\uFE0F",
      "\u{1F234}",
      "\u{1F235}",
      "\u{1F239}",
      "\u{1F232}",
      "\u{1F170}\uFE0F",
      "\u{1F171}\uFE0F",
      "\u{1F18E}",
      "\u{1F191}",
      "\u{1F17E}\uFE0F",
      "\u{1F198}",
      "\u274C",
      "\u2B55",
      "\u{1F6D1}",
      "\u26D4",
      "\u{1F4DB}",
      "\u{1F6AB}",
      "\u{1F4AF}",
      "\u{1F4A2}",
      "\u2668\uFE0F",
      "\u{1F6B7}",
      "\u{1F6AF}",
      "\u{1F6B3}",
      "\u{1F6B1}",
      "\u{1F51E}",
      "\u{1F4F5}",
      "\u{1F6AD}",
      "\u2757",
      "\u2755",
      "\u2753",
      "\u2754",
      "\u203C\uFE0F",
      "\u2049\uFE0F",
      "\u{1F505}",
      "\u{1F506}",
      "\u303D\uFE0F",
      "\u26A0\uFE0F",
      "\u{1F6B8}",
      "\u{1F531}",
      "\u269C\uFE0F",
      "\u{1F530}",
      "\u267B\uFE0F",
      "\u2705",
      "\u{1F22F}",
      "\u{1F4B9}",
      "\u2747\uFE0F",
      "\u2733\uFE0F",
      "\u274E",
      "\u{1F310}",
      "\u{1F4A0}",
      "\u24C2\uFE0F",
      "\u{1F300}",
      "\u{1F4A4}",
      "\u{1F3E7}",
      "\u{1F6BE}",
      "\u267F",
      "\u{1F17F}\uFE0F",
      "\u{1F6D7}",
      "\u{1F233}",
      "\u{1F202}\uFE0F",
      "\u{1F6C2}",
      "\u{1F6C3}",
      "\u{1F6C4}",
      "\u{1F6C5}",
      "\u{1F6B9}",
      "\u{1F6BA}",
      "\u{1F6BC}",
      "\u{1F6BB}",
      "\u{1F6AE}",
      "\u{1F3A6}",
      "\u{1F4F6}",
      "\u{1F201}",
      "\u{1F523}",
      "\u2139\uFE0F",
      "\u{1F524}",
      "\u{1F521}",
      "\u{1F520}",
      "\u{1F196}",
      "\u{1F197}",
      "\u{1F199}",
      "\u{1F192}",
      "\u{1F195}",
      "\u{1F193}",
      "0\uFE0F\u20E3",
      "1\uFE0F\u20E3",
      "2\uFE0F\u20E3",
      "3\uFE0F\u20E3",
      "4\uFE0F\u20E3",
      "5\uFE0F\u20E3",
      "6\uFE0F\u20E3",
      "7\uFE0F\u20E3",
      "8\uFE0F\u20E3",
      "9\uFE0F\u20E3",
      "\u{1F51F}",
      "\u{1F522}",
      "#\uFE0F\u20E3",
      "*\uFE0F\u20E3",
      "\u23CF\uFE0F",
      "\u25B6\uFE0F",
      "\u23F8\uFE0F",
      "\u23EF\uFE0F",
      "\u23F9\uFE0F",
      "\u23FA\uFE0F",
      "\u23ED\uFE0F",
      "\u23EE\uFE0F",
      "\u23E9",
      "\u23EA",
      "\u23EB",
      "\u23EC",
      "\u25C0\uFE0F",
      "\u{1F53C}",
      "\u{1F53D}",
      "\u27A1\uFE0F",
      "\u2B05\uFE0F",
      "\u2B06\uFE0F",
      "\u2B07\uFE0F",
      "\u2197\uFE0F",
      "\u2198\uFE0F",
      "\u2199\uFE0F",
      "\u2196\uFE0F",
      "\u2195\uFE0F",
      "\u2194\uFE0F",
      "\u21AA\uFE0F",
      "\u21A9\uFE0F",
      "\u2934\uFE0F",
      "\u2935\uFE0F",
      "\u{1F500}",
      "\u{1F501}",
      "\u{1F502}",
      "\u{1F504}",
      "\u{1F503}",
      "\u{1F3B5}",
      "\u{1F3B6}",
      "\u2795",
      "\u2796",
      "\u2797",
      "\u2716\uFE0F",
      "\u{1F7F0}",
      "\u267E\uFE0F",
      "\u{1F4B2}",
      "\u{1F4B1}",
      "\u2122\uFE0F",
      "\xA9\uFE0F",
      "\xAE\uFE0F",
      "\u3030\uFE0F",
      "\u27B0",
      "\u27BF",
      "\u{1F51A}",
      "\u{1F519}",
      "\u{1F51B}",
      "\u{1F51D}",
      "\u{1F51C}",
      "\u2714\uFE0F",
      "\u2611\uFE0F",
      "\u{1F518}",
      "\u{1F534}",
      "\u{1F7E0}",
      "\u{1F7E1}",
      "\u{1F7E2}",
      "\u{1F535}",
      "\u{1F7E3}",
      "\u26AB",
      "\u26AA",
      "\u{1F7E4}",
      "\u{1F53A}",
      "\u{1F53B}",
      "\u{1F538}",
      "\u{1F539}",
      "\u{1F536}",
      "\u{1F537}",
      "\u{1F533}",
      "\u{1F532}",
      "\u25AA\uFE0F",
      "\u25AB\uFE0F",
      "\u25FE",
      "\u25FD",
      "\u25FC\uFE0F",
      "\u25FB\uFE0F",
      "\u{1F7E5}",
      "\u{1F7E7}",
      "\u{1F7E8}",
      "\u{1F7E9}",
      "\u{1F7E6}",
      "\u{1F7EA}",
      "\u2B1B",
      "\u2B1C",
      "\u{1F7EB}",
      "\u{1F508}",
      "\u{1F507}",
      "\u{1F509}",
      "\u{1F50A}",
      "\u{1F514}",
      "\u{1F515}",
      "\u{1F4E3}",
      "\u{1F4E2}",
      "\u{1F4AC}",
      "\u{1F4AD}",
      "\u{1F5EF}\uFE0F",
      "\u2660\uFE0F",
      "\u2663\uFE0F",
      "\u2665\uFE0F",
      "\u2666\uFE0F",
      "\u{1F0CF}",
      "\u{1F3B4}",
      "\u{1F004}",
      "\u{1F550}",
      "\u{1F551}",
      "\u{1F552}",
      "\u{1F553}",
      "\u{1F554}",
      "\u{1F555}",
      "\u{1F556}",
      "\u{1F557}",
      "\u{1F558}",
      "\u{1F559}",
      "\u{1F55A}",
      "\u{1F55B}",
      "\u{1F55C}",
      "\u{1F55D}",
      "\u{1F55E}",
      "\u{1F55F}",
      "\u{1F560}",
      "\u{1F561}",
      "\u{1F562}",
      "\u{1F563}",
      "\u{1F564}",
      "\u{1F565}",
      "\u{1F566}",
      "\u{1F567}"
    ]
  },
  {
    id: "flags",
    label: "\u{1F3F3}\uFE0F",
    items: [
      "\u{1F3C1}",
      "\u{1F6A9}",
      "\u{1F38C}",
      "\u{1F3F4}",
      "\u{1F3F3}\uFE0F",
      "\u{1F3F3}\uFE0F\u200D\u{1F308}",
      "\u{1F3F3}\uFE0F\u200D\u26A7\uFE0F",
      "\u{1F3F4}\u200D\u2620\uFE0F",
      "\u{1F1FA}\u{1F1F3}",
      ...FLAG_REGIONS.map(flag),
      "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
      "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
      "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
    ]
  }
];
function getEmojiCategory(id = "smileys") {
  return EMOJI_CATEGORIES.find((c) => c.id === id) ?? EMOJI_CATEGORIES[0];
}
function pageEmoji(items, page = 0, pageSize = MOBILE_EMOJI_PAGE_SIZE) {
  const list = items ?? [];
  const size = Math.max(1, pageSize);
  const pages = Math.max(1, Math.ceil(list.length / size) || 1);
  const p = Math.max(0, Math.min(page, pages - 1));
  return {
    items: list.slice(p * size, p * size + size),
    page: p,
    pages,
    pageSize: size
  };
}
function getEmojiPage(categoryId, page = 0, pageSize = MOBILE_EMOJI_PAGE_SIZE) {
  const category = getEmojiCategory(categoryId);
  return { category, ...pageEmoji(category.items, page, pageSize) };
}

// src/keyboard/keyboard.js
var VirtualKeyboard = class {
  /**
   * @param {object} [options]
   * @param {(ev: object) => void} [options.onEvent]
   * @param {string} [options.layout]
   */
  constructor(options = {}) {
    this.onEvent = options.onEvent ?? (() => {
    });
    this.baseLayout = options.layout ?? "mongol";
    this.shift = false;
    this.special = false;
    this.otherSpecial = false;
    this.latin = false;
    this.emoji = false;
    this.emojiCategory = "smileys";
    this.emojiPage = 0;
    this.visible = false;
  }
  getEmojiPage() {
    return getEmojiPage(this.emojiCategory, this.emojiPage, MOBILE_EMOJI_PAGE_SIZE);
  }
  setEmojiCategory(id) {
    const next = getEmojiCategory(id).id;
    this.emojiCategory = next;
    this.emojiPage = 0;
  }
  nextEmojiPage() {
    const { pages } = this.getEmojiPage();
    if (this.emojiPage < pages - 1) this.emojiPage += 1;
  }
  prevEmojiPage() {
    if (this.emojiPage > 0) this.emojiPage -= 1;
  }
  _leaveEmoji() {
    this.emoji = false;
    this.emojiPage = 0;
  }
  getLayoutRows() {
    const name = resolveLayoutName({
      base: this.baseLayout,
      special: this.special,
      otherSpecial: this.otherSpecial,
      latin: this.latin
    });
    return getLayout(name).map(
      (row, rowIndex) => row.map(
        (item, colIndex) => normalizeKey(item, { rowIndex, colIndex, layoutName: name })
      )
    );
  }
  show() {
    this.visible = true;
  }
  hide() {
    this.visible = false;
  }
  toggle() {
    this.visible = !this.visible;
  }
  /**
   * @param {{ type: string, value?: string, action?: string }} key
   */
  press(key) {
    if (key.type === "key") {
      let value = key.value;
      if (this.shift && !key.mongol && value) {
        value = value.toUpperCase();
        this.shift = false;
      }
      this.onEvent({ type: "key", key: value });
      return;
    }
    const action = key.action;
    switch (action) {
      case "shift":
        this.shift = !this.shift;
        this.onEvent({ type: "command", command: "shift", shift: this.shift });
        break;
      case "special":
        this.special = !this.special;
        this.otherSpecial = false;
        this._leaveEmoji();
        this.onEvent({
          type: "command",
          command: "layout",
          latin: this.latin,
          special: this.special,
          otherSpecial: this.otherSpecial
        });
        break;
      case "other-special":
        this.otherSpecial = !this.otherSpecial;
        this._leaveEmoji();
        this.onEvent({
          type: "command",
          command: "layout",
          latin: this.latin,
          special: this.special,
          otherSpecial: this.otherSpecial
        });
        break;
      case "abc":
        this.latin = !this.latin;
        this.special = false;
        this.otherSpecial = false;
        this._leaveEmoji();
        this.onEvent({
          type: "command",
          command: "layout",
          latin: this.latin,
          special: this.special,
          otherSpecial: this.otherSpecial
        });
        break;
      case "emoji":
        this.emoji = !this.emoji;
        if (this.emoji) {
          this.special = false;
          this.otherSpecial = false;
          this.emojiPage = 0;
        }
        this.onEvent({
          type: "command",
          command: "layout",
          latin: this.latin,
          special: this.special,
          otherSpecial: this.otherSpecial,
          emoji: this.emoji
        });
        break;
      default:
        this.onEvent({ type: "command", command: actionToCommand(action) });
    }
  }
};

// src/keyboard/popup-candidates.js
var EN_POPUP_KEYS = {
  a: [
    { text: "\xAA", capsText: "\xAA" },
    { text: "\xE6", capsText: "\xC6" },
    { text: "\xE0", capsText: "\xC0" },
    { text: "\xE1", capsText: "\xC1" },
    { text: "\xE2", capsText: "\xC2" },
    { text: "\xE4", capsText: "\xC4" },
    { text: "\u0101", capsText: "\u0100" },
    { text: "\xE5", capsText: "\xC5" }
  ],
  c: [
    { text: "\u0107", capsText: "\u0106" },
    { text: "\u010D", capsText: "\u010C" },
    { text: "\u0109", capsText: "\u0108" },
    { text: "\u010B", capsText: "\u010A" },
    { text: "\xE7", capsText: "\xC7" }
  ],
  e: [
    { text: "\xEB", capsText: "\xCB" },
    { text: "\xE9", capsText: "\xC9" },
    { text: "\xE8", capsText: "\xC8" },
    { text: "\xEA", capsText: "\xCA" },
    { text: "\u0119", capsText: "\u0118" },
    { text: "\u0113", capsText: "\u0112" },
    { text: "\u0117", capsText: "\u0116" }
  ],
  i: [
    { text: "\u012F", capsText: "\u012E" },
    { text: "\u012B", capsText: "\u012A" },
    { text: "\xEF", capsText: "\xCF" },
    { text: "\xEC", capsText: "\xCC" },
    { text: "\xEE", capsText: "\xCE" },
    { text: "\xED", capsText: "\xCD" }
  ],
  n: [
    { text: "\xF1", capsText: "\xD1" },
    { text: "\u0144", capsText: "\u0143" },
    { text: "\u01F9", capsText: "\u01F8" },
    { text: "\u0148", capsText: "\u0147" }
  ],
  o: [
    { text: "\u0153", capsText: "\u0152" },
    { text: "\xF8", capsText: "\xD8" },
    { text: "\xBA", capsText: "\u1D3C" },
    { text: "\u014D", capsText: "\u014C" },
    { text: "\xF6", capsText: "\xD6" },
    { text: "\xF2", capsText: "\xD2" },
    { text: "\xF4", capsText: "\xD4" },
    { text: "\xF5", capsText: "\xD5" },
    { text: "\xF3", capsText: "\xD3" }
  ],
  s: [
    { text: "\u015D", capsText: "\u015C" },
    { text: "\u015B", capsText: "\u015A" },
    { text: "\xDF", capsText: "\xDF" }
  ],
  u: [
    { text: "\u016B", capsText: "\u016A" },
    { text: "\xF9", capsText: "\xD9" },
    { text: "\xFA", capsText: "\xDA" },
    { text: "\xFB", capsText: "\xDB" },
    { text: "\xFC", capsText: "\xDC" }
  ]
};
function forE(ctx) {
  const out = [];
  const prev = getPreviousChar(ctx);
  if (!isInitial(ctx) && prev != null && isMvsPrecedingChar(prev) && prev !== Mongol.qa && prev !== Mongol.ga) {
    out.push({
      text: fromCodes(Mongol.mvs, Mongol.e),
      display: fromCodes(Mongol.nirugu, prev, Mongol.mvs, Mongol.e)
    });
  }
  if (!isInitial(ctx)) {
    out.push({
      text: fromCodes(Mongol.e, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.e, Mongol.fvs1)
    });
  }
  return out;
}
function forT(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.ta, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.ta, Mongol.fvs1, Mongol.nirugu)
    }
  ];
}
function forY(ctx) {
  if (!isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.ya, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.ya, Mongol.fvs1, Mongol.nirugu)
    }
  ];
}
function forU(ctx) {
  if (isInitial(ctx)) {
    return [{ text: fromCodes(Mongol.ue, Mongol.fvs1) }];
  }
  return [
    {
      text: fromCodes(Mongol.ue, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.ue, Mongol.fvs1, Mongol.nirugu)
    },
    {
      text: fromCodes(Mongol.ue, Mongol.fvs2),
      display: fromCodes(Mongol.nirugu, Mongol.ue, Mongol.fvs2, Mongol.nirugu)
    }
  ];
}
function forI(ctx) {
  const out = [];
  if (!isInitial(ctx)) {
    out.push({
      text: fromCodes(Mongol.i, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.i, Mongol.fvs1, Mongol.nirugu)
    });
  }
  if (!isInitial(ctx) && isVowel(getPreviousChar(ctx))) {
    out.push({
      text: fromCodes(Mongol.i, Mongol.fvs2),
      display: fromCodes(Mongol.nirugu, Mongol.i, Mongol.nirugu)
    });
  }
  return out;
}
function forO(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.oe, Mongol.fvs2),
      display: fromCodes(Mongol.nirugu, Mongol.oe, Mongol.fvs2, Mongol.nirugu)
    },
    {
      text: fromCodes(Mongol.oe, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.oe, Mongol.fvs1)
    }
  ];
}
function forA(ctx) {
  if (isInitial(ctx)) {
    return [{ text: fromCodes(Mongol.a, Mongol.fvs1) }];
  }
  const out = [];
  const prev = getPreviousChar(ctx);
  if (isMvsPrecedingChar(prev)) {
    out.push({
      text: fromCodes(Mongol.mvs, Mongol.a),
      display: fromCodes(Mongol.nirugu, prev, Mongol.mvs, Mongol.a)
    });
  }
  out.push({
    text: fromCodes(Mongol.a, Mongol.fvs1),
    display: fromCodes(Mongol.nirugu, Mongol.a, Mongol.fvs1, Mongol.nirugu)
  });
  return out;
}
function forS(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.sa, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.sa, Mongol.fvs1)
    }
  ];
}
function forD(ctx) {
  const prev = getPreviousChar(ctx);
  if (prev === Mongol.mvs) {
    return [{ text: fromCodes(Mongol.da, Mongol.da) }];
  }
  if (isInitial(ctx)) {
    return [
      {
        text: fromCodes(Mongol.da, Mongol.fvs1) + fromCodes(Mongol.da)
      }
    ];
  }
  return [
    {
      text: fromCodes(Mongol.da, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.da, Mongol.fvs1)
    }
  ];
}
function forG(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.ga, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.ga, Mongol.fvs1)
    },
    {
      text: fromCodes(Mongol.ga, Mongol.fvs2),
      display: fromCodes(Mongol.nirugu, Mongol.ga, Mongol.fvs2)
    },
    {
      text: fromCodes(Mongol.ga, Mongol.fvs3),
      display: fromCodes(Mongol.nirugu, Mongol.ga, Mongol.fvs3, Mongol.nirugu)
    }
  ];
}
function forC(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.o, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.o, Mongol.fvs1, Mongol.nirugu)
    }
  ];
}
function forV(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.u, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.u, Mongol.fvs1, Mongol.nirugu)
    }
  ];
}
function forN(ctx) {
  if (isInitial(ctx)) return [];
  return [
    {
      text: fromCodes(Mongol.na, Mongol.nirugu),
      display: fromCodes(Mongol.nirugu, Mongol.na, Mongol.nirugu)
    },
    {
      text: fromCodes(Mongol.na, Mongol.fvs1),
      display: fromCodes(Mongol.nirugu, Mongol.na, Mongol.fvs1, Mongol.nirugu)
    },
    {
      text: fromCodes(Mongol.na, Mongol.fvs2),
      display: fromCodes(Mongol.nirugu, Mongol.na, Mongol.fvs2, Mongol.nirugu)
    }
  ];
}
function mongolPopupCandidates(ctx, id) {
  if (!id) return [];
  switch (id) {
    case "q":
      return [{ text: fromCodes(Mongol.chi) }];
    case "w":
      return [];
    case "e":
      return forE(ctx);
    case "r":
      return [{ text: fromCodes(Mongol.zra) }];
    case "t":
      return forT(ctx);
    case "y":
      return forY(ctx);
    case "u":
      return forU(ctx);
    case "i":
      return forI(ctx);
    case "o":
      return forO(ctx);
    case "p":
      return [];
    case "a":
      return forA(ctx);
    case "s":
      return forS(ctx);
    case "d":
      return forD(ctx);
    case "f":
      return [];
    case "g":
      return forG(ctx);
    case "h":
      return [{ text: fromCodes(Mongol.haa) }];
    case "j":
      return [{ text: fromCodes(Mongol.zhi) }];
    case "k":
      return [];
    case "l":
      return [{ text: fromCodes(Mongol.lha) }];
    case "ng":
      return [];
    case "z":
      return [{ text: fromCodes(Mongol.tsa) }];
    case "x":
      return [];
    case "c":
      return forC(ctx);
    case "v":
      return forV(ctx);
    case "b":
      return [];
    case "n":
      return forN(ctx);
    case "m":
      return [];
    case "!":
      return [{ text: fromCodes(Mongol.exclamationQuestion) }];
    case "?":
      return [{ text: fromCodes(Mongol.questionExclamation) }];
    default:
      return [];
  }
}
function resolvePopupKeys(key, ctx, opts = {}) {
  if (!key || key.type !== "key") return [];
  if (key.mongol && key.id) {
    return mongolPopupCandidates(ctx, key.id);
  }
  const ch = (key.value ?? "").toLowerCase();
  if (ch === "!" || ch === "?") {
    return mongolPopupCandidates(ctx, ch);
  }
  const list = EN_POPUP_KEYS[ch];
  if (!list?.length) return [];
  if (opts.shift) {
    return list.map((k) => ({
      text: k.capsText ?? k.text.toUpperCase(),
      display: k.capsText ?? k.text.toUpperCase()
    }));
  }
  return list.map((k) => ({ text: k.text, display: k.text }));
}
function popupIndexFromDx(dx, count, itemWidth = 36) {
  if (!count) return 0;
  const offset = Math.trunc(dx / itemWidth);
  return Math.max(0, Math.min(count - 1, offset));
}

// src/utils/popup-position.js
var DEFAULT_GAP = 8;
var DEFAULT_MARGIN = 8;
var MAX_CARET_EXTENT = 36;
function normalizeCaret(rect) {
  const left = rect.left;
  const top = rect.top;
  let right = rect.right ?? left + (rect.width ?? 0);
  let bottom = rect.bottom ?? top + (rect.height ?? 0);
  if (right - left > MAX_CARET_EXTENT) right = left + MAX_CARET_EXTENT;
  if (bottom - top > MAX_CARET_EXTENT) bottom = top + MAX_CARET_EXTENT;
  return { left, top, right, bottom };
}
function placeNearCaret(rect, panel, viewport, opts = {}) {
  const gap = opts.gap ?? DEFAULT_GAP;
  const margin = opts.margin ?? DEFAULT_MARGIN;
  const placement = opts.placement ?? "auto";
  const pWidth = panel.width > 0 ? panel.width : 200;
  const pHeight = panel.height > 0 ? panel.height : 60;
  const vw = viewport.width;
  const vh = viewport.height;
  const caret = normalizeCaret(rect);
  const anchors = {
    "below-right": { left: caret.right + gap, top: caret.bottom + gap },
    "below-left": { left: caret.left - gap - pWidth, top: caret.bottom + gap },
    "above-left": { left: caret.left - gap - pWidth, top: caret.top - gap - pHeight },
    "above-right": { left: caret.right + gap, top: caret.top - gap - pHeight }
  };
  const order = placement === "left" ? ["below-left", "above-left", "below-right", "above-right"] : placement === "top" ? ["above-left", "above-right", "below-right", "below-left"] : placement === "right" ? ["below-right", "above-right", "below-left", "above-left"] : ["below-right", "below-left", "above-left", "above-right"];
  const overflow = (left2, top2) => {
    const ox = Math.max(0, margin - left2) + Math.max(0, left2 + pWidth - (vw - margin));
    const oy = Math.max(0, margin - top2) + Math.max(0, top2 + pHeight - (vh - margin));
    return ox + oy;
  };
  const overlapsCaret = (left2, top2) => left2 < caret.right + gap && left2 + pWidth > caret.left - gap && top2 < caret.bottom + gap && top2 + pHeight > caret.top - gap;
  let best = null;
  let bestOverflow = Infinity;
  for (const name of order) {
    const pos = anchors[name];
    if (!pos || overlapsCaret(pos.left, pos.top)) continue;
    const ov = overflow(pos.left, pos.top);
    if (ov === 0) {
      best = pos;
      break;
    }
    if (ov < bestOverflow) {
      best = pos;
      bestOverflow = ov;
    }
  }
  let left = best ? best.left : caret.right + gap;
  let top = best ? best.top : caret.bottom + gap;
  const shiftLeft = vw - margin - pWidth;
  if (left + pWidth > vw - margin && shiftLeft >= caret.right + gap) {
    left = shiftLeft;
  } else if (left < margin && margin + pWidth <= caret.left - gap) {
    left = margin;
  }
  const shiftTop = vh - margin - pHeight;
  if (top + pHeight > vh - margin && shiftTop >= caret.bottom + gap) {
    top = shiftTop;
  } else if (top < margin && margin + pHeight <= caret.top - gap) {
    top = margin;
  }
  return { left, top };
}

// src/components/mgl-candidates.js
function buildTemplate() {
  const TEMPLATE = document.createElement("template");
  TEMPLATE.innerHTML = `
  <style>
    :host {
      display: none;
      position: fixed;
      z-index: 10000;
      font-family: var(--mgl-ime-font, "Oyun Qagan Tig", "Noto Sans Mongolian", "Mongolian Baiti", serif);
      color: var(--mgl-ime-text, #1a1a1a);
      --bg: var(--mgl-ime-candidate-background, #f7f5f0);
      --border: var(--mgl-ime-border, #c8c2b4);
      --active: var(--mgl-ime-key-active, #d4e4f7);
      --accent: var(--mgl-ime-accent, #3d6b9a);
    }
    :host([visible]) { display: block; }
    :host([variant="popup"]) .panel,
    :host([variant="bar"]) .panel {
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: 10px;
      box-shadow: 0 8px 28px rgba(0,0,0,.14);
      padding: 8px 10px 6px;
      max-width: min(92vw, 520px);
    }
    /* Mobile: fixed-width strip above keyboard; swipe horizontally for more */
    :host([variant="bar"]) {
      width: min(92vw, 520px);
      max-width: min(92vw, 520px);
    }
    :host([variant="bar"]) .panel {
      overflow-x: auto;
      overflow-y: hidden;
      -webkit-overflow-scrolling: touch;
      overscroll-behavior-x: contain;
      touch-action: pan-x;
      scrollbar-width: thin;
    }
    :host([variant="bar"]) .panel::-webkit-scrollbar {
      height: 3px;
    }
    :host([variant="bar"]) .row {
      width: max-content;
      flex-wrap: nowrap;
    }
    :host([variant="bar"]) .item {
      flex-shrink: 0;
    }
    :host([variant="bar"]) .meta {
      display: none;
    }
    .row {
      display: flex;
      flex-direction: row;
      align-items: flex-start;
      gap: 0;
    }
    .item {
      display: flex;
      flex-direction: column;
      align-items: center;
      min-width: 44px;
      padding: 4px 10px;
      cursor: pointer;
      border-radius: 8px;
      border: none;
      background: transparent;
      color: inherit;
      font: inherit;
    }
    .item[aria-selected="true"],
    .item:hover { background: var(--active); }

    .idx {
      writing-mode: horizontal-tb;
      font-size: 11px;
      font-weight: 600;
      width: 18px; height: 18px;
      border-radius: 9px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: color-mix(in srgb, var(--accent) 22%, transparent);
      color: var(--accent);
      margin-bottom: 4px;
      flex-shrink: 0;
    }

    .word {
      writing-mode: vertical-lr;
      text-orientation: mixed;
      font-size: var(--mgl-ime-candidate-size, 22px);
      line-height: 1.2;
      max-height: 7em;
      overflow: hidden;
    }
    .meta {
      writing-mode: horizontal-tb;
      font-size: 11px;
      opacity: .55;
      text-align: center;
      margin-top: 4px;
    }
    .empty { display: none; }
  </style>
  <div class="panel" part="panel">
    <div class="row" part="list" role="listbox"></div>
    <div class="meta" part="meta"></div>
  </div>
`;
  return TEMPLATE;
}
var _template;
var Base = typeof HTMLElement !== "undefined" ? HTMLElement : class {
};
var MglCandidates = class extends Base {
  constructor() {
    super();
    if (!_template) _template = buildTemplate();
    this.attachShadow({ mode: "open" }).appendChild(_template.content.cloneNode(true));
    this._candidates = [];
    this._pageIndex = 0;
    this._pageSize = 5;
    this._selected = 0;
    this._list = this.shadowRoot.querySelector(".row");
    this._meta = this.shadowRoot.querySelector(".meta");
  }
  static get observedAttributes() {
    return ["variant", "visible", "placement"];
  }
  connectedCallback() {
    if (!this.hasAttribute("variant")) this.setAttribute("variant", "popup");
  }
  get visible() {
    return this.hasAttribute("visible");
  }
  set visible(v) {
    if (v) this.setAttribute("visible", "");
    else this.removeAttribute("visible");
  }
  /**
   * @param {object} state
   */
  update(state = {}) {
    const prev = this._candidates;
    this._candidates = state.candidates ?? [];
    this._pageIndex = state.pageIndex ?? 0;
    this._pageSize = state.pageSize ?? 5;
    this._selected = state.selectedCandidate ?? 0;
    const isBar = this.getAttribute("variant") === "bar";
    const list = isBar ? this._candidates : this._candidates.slice(
      this._pageIndex * this._pageSize,
      this._pageIndex * this._pageSize + this._pageSize
    );
    const listChanged = prev.length !== this._candidates.length || prev.some((w, i) => w !== this._candidates[i]);
    this.visible = list.length > 0 && state.candidateVisible !== false;
    this._render(list, { absoluteIndex: isBar });
    if (isBar) {
      this._meta.textContent = "";
      if (listChanged) {
        const panel = this.shadowRoot.querySelector(".panel");
        if (panel) panel.scrollLeft = 0;
      }
    } else {
      const pages = Math.ceil(this._candidates.length / this._pageSize) || 0;
      this._meta.textContent = pages > 1 ? `${this._pageIndex + 1}/${pages}` : "";
    }
  }
  /**
   * Place the desktop popup at the caret's bottom-right when it fits, then
   * bottom-left or top-left. Never overlap the caret — viewport clamping must
   * not slide the panel over the insertion point.
   * @param {{left:number, top:number, bottom?:number, right?:number, width?:number, height?:number}} rect
   */
  positionNear(rect, placement = "auto") {
    if (this.getAttribute("variant") === "bar") return;
    const panel = this.shadowRoot.querySelector(".panel");
    const pRect = panel ? panel.getBoundingClientRect() : null;
    const { left, top } = placeNearCaret(
      rect,
      { width: pRect?.width ?? 0, height: pRect?.height ?? 0 },
      { width: window.innerWidth, height: window.innerHeight },
      { placement }
    );
    this.style.right = "auto";
    this.style.bottom = "auto";
    this.style.left = `${left}px`;
    this.style.top = `${top}px`;
  }
  /**
   * @param {string[]} page
   * @param {{ absoluteIndex?: boolean }} [opts]
   */
  _render(page, opts = {}) {
    this._list.innerHTML = "";
    const isBar = this.getAttribute("variant") === "bar";
    page.forEach((word, i) => {
      const abs = opts.absoluteIndex ? i : this._pageIndex * this._pageSize + i;
      const btn = document.createElement("button");
      btn.type = "button";
      btn.tabIndex = -1;
      btn.className = "item";
      btn.setAttribute("role", "option");
      btn.setAttribute("aria-selected", String(abs === this._selected));
      btn.innerHTML = `<span class="idx">${i + 1}</span><span class="word"></span>`;
      btn.querySelector(".word").textContent = word;
      let committed = false;
      const commitCandidate = (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (committed) return;
        committed = true;
        this.dispatchEvent(
          new CustomEvent("mgl-candidate-select", {
            detail: { index: abs, word },
            bubbles: true,
            composed: true
          })
        );
      };
      btn.addEventListener("mousedown", commitCandidate);
      if (isBar) {
        let startX = 0;
        let startY = 0;
        let moved = false;
        btn.addEventListener(
          "touchstart",
          (e) => {
            const t = e.touches[0];
            startX = t.clientX;
            startY = t.clientY;
            moved = false;
          },
          { passive: true }
        );
        btn.addEventListener(
          "touchmove",
          (e) => {
            const t = e.touches[0];
            if (Math.abs(t.clientX - startX) > 10 || Math.abs(t.clientY - startY) > 10) {
              moved = true;
            }
          },
          { passive: true }
        );
        btn.addEventListener(
          "touchend",
          (e) => {
            if (moved) return;
            commitCandidate(e);
          },
          { passive: false }
        );
      } else {
        btn.addEventListener("touchstart", commitCandidate, { passive: false });
      }
      this._list.appendChild(btn);
    });
  }
};
if (typeof customElements !== "undefined" && !customElements.get("mgl-candidates")) {
  customElements.define("mgl-candidates", MglCandidates);
}

// src/components/mgl-keyboard.js
var ACTION_LABEL = {
  shift: "\u21E7",
  backspace: "\u232B",
  enter: "\u21B5",
  space: " ",
  special: "123",
  "other-special": "#+=",
  abc: "ABC",
  suffix: "\u1833\u1820\u182D\u1820\u182A\u1824\u1837\u1822",
  emoji: "\u{1F60A}"
};
var LONG_PRESS_MS = 420;
function buildTemplate2() {
  const TEMPLATE = document.createElement("template");
  TEMPLATE.innerHTML = `
  <style>
    :host {
      display: none;
      position: fixed;
      left: 0; right: 0; bottom: 0;
      z-index: 9999;
      font-family: var(--mgl-ime-font, "Oyun Qagan Tig", "Noto Sans Mongolian", "Mongolian Baiti", system-ui, sans-serif);
      color: var(--mgl-ime-text, #1c1c1c);
      --bg: var(--mgl-ime-background, #e8e4dc);
      --key-bg: var(--mgl-ime-key-background, #faf8f4);
      --key-action: var(--mgl-ime-key-action, #d2cdc3);
      --key-active: var(--mgl-ime-key-active, #c5d8ef);
      --border: var(--mgl-ime-border, #bdb6a8);
      --popup-selected: var(--mgl-ime-accent, #3d6b9a);
      padding-bottom: env(safe-area-inset-bottom, 0);
      user-select: none;
      -webkit-user-select: none;
      touch-action: manipulation;
    }
    :host([visible]) { display: block; }
    .wrap {
      background: var(--bg);
      border-top: 1px solid var(--border);
      padding: 6px 4px 10px;
      position: relative;
    }
    .row {
      display: flex;
      justify-content: center;
      align-items: stretch;
      gap: 4px;
      margin: 4px 0;
      height: 52px;
    }
    button.key {
      flex: 1 1 0;
      min-width: 0;
      /* Same height for Mongol / Latin / symbol layouts */
      min-height: 52px;
      height: 52px;
      border: none;
      border-radius: 8px;
      background: var(--key-bg);
      box-shadow: 0 1px 0 rgba(0,0,0,.08);
      font: inherit;
      font-size: 20px;
      color: inherit;
      padding: 0 2px;
      position: relative;
      box-sizing: border-box;
    }
    button.key.action {
      background: var(--key-action);
      flex: 1.35 1 0;
      font-size: 13px;
      font-weight: 600;
      letter-spacing: .02em;
    }
    button.key.space { flex: 3.2 1 0; }
    button.key:active,
    button.key.pressed { background: var(--key-active); }
    button.key.mongol {
      writing-mode: vertical-lr;
      text-orientation: mixed;
      font-size: 22px;
    }
    .hint {
      position: absolute;
      top: 3px; left: 4px;
      font-size: 9px;
      opacity: .45;
      writing-mode: horizontal-tb;
      pointer-events: none;
    }
    .label-action { writing-mode: horizontal-tb; }

    .popup {
      display: none;
      position: fixed;
      z-index: 10050;
      padding: 4px;
      background: var(--key-bg);
      border-radius: 10px;
      box-shadow: 0 3px 10px rgba(0,0,0,.28);
      pointer-events: none;
    }
    .popup[open] { display: flex; }
    .popup-item {
      min-width: 36px;
      min-height: 44px;
      padding: 8px 10px;
      border-radius: 6px;
      display: flex;
      align-items: center;
      justify-content: center;
      font: inherit;
      font-size: 22px;
      color: inherit;
    }
    .popup-item.mongol {
      writing-mode: vertical-lr;
      text-orientation: mixed;
    }
    .popup-item.selected {
      background: var(--popup-selected);
      color: #fff;
    }

    /* Match letter keyboard: 4 rows \xD7 (52px + 8px vertical margin) */
    .emoji-panel {
      display: flex;
      flex-direction: column;
      gap: 4px;
      height: 240px;
      box-sizing: border-box;
    }
    .emoji-cats {
      display: flex;
      gap: 4px;
      flex: 0 0 36px;
      height: 36px;
      overflow-x: auto;
      -webkit-overflow-scrolling: touch;
      scrollbar-width: none;
    }
    .emoji-cats::-webkit-scrollbar { display: none; }
    .emoji-cats button {
      flex: 0 0 36px;
      height: 36px;
      border: none;
      border-radius: 8px;
      background: var(--key-action);
      font-size: 18px;
      line-height: 1;
      font-family: "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
      color: inherit;
      padding: 0;
    }
    .emoji-cats button.active { background: var(--key-active); }
    .emoji-grid {
      display: grid;
      grid-template-columns: repeat(8, 1fr);
      grid-template-rows: repeat(3, minmax(0, 1fr));
      gap: 4px;
      flex: 1 1 auto;
      min-height: 0;
    }
    .emoji-grid button {
      border: none;
      border-radius: 8px;
      background: var(--key-bg);
      box-shadow: 0 1px 0 rgba(0,0,0,.08);
      font-size: 22px;
      line-height: 1;
      font-family: "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
      color: inherit;
      padding: 0;
    }
    .emoji-grid button:active { background: var(--key-active); }
    .emoji-nav {
      display: flex;
      gap: 4px;
      flex: 0 0 52px;
      height: 52px;
      align-items: stretch;
    }
    .emoji-nav button {
      flex: 1 1 0;
      border: none;
      border-radius: 8px;
      background: var(--key-action);
      font: inherit;
      font-size: 16px;
      font-weight: 600;
      color: inherit;
    }
    .emoji-nav button:active { background: var(--key-active); }
    .emoji-nav button:disabled { opacity: .4; }
    .emoji-nav .page {
      flex: 1.1 1 0;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 13px;
      font-weight: 600;
      writing-mode: horizontal-tb;
    }
  </style>
  <div class="wrap" part="keyboard"></div>
  <div class="popup" part="popup" aria-hidden="true"></div>
`;
  return TEMPLATE;
}
var _template2;
var Base2 = typeof HTMLElement !== "undefined" ? HTMLElement : class {
};
var MglKeyboard = class extends Base2 {
  constructor() {
    super();
    if (!_template2) _template2 = buildTemplate2();
    this.attachShadow({ mode: "open" }).appendChild(_template2.content.cloneNode(true));
    this._wrap = this.shadowRoot.querySelector(".wrap");
    this._popup = this.shadowRoot.querySelector(".popup");
    this.getEditingContext = null;
    this._press = null;
    this._needsRender = false;
    this._vk = new VirtualKeyboard({
      onEvent: (ev) => {
        this.dispatchEvent(
          new CustomEvent("mgl-keyboard-event", {
            detail: ev,
            bubbles: true,
            composed: true
          })
        );
        this._needsRender = true;
        if (!this._press) this._flushRender();
      }
    });
  }
  static get observedAttributes() {
    return ["visible", "layout"];
  }
  attributeChangedCallback(name, _o, v) {
    if (name === "layout" && v) {
      this._vk.baseLayout = v;
      this.render();
    }
  }
  get visible() {
    return this.hasAttribute("visible");
  }
  set visible(v) {
    if (v) this.setAttribute("visible", "");
    else this.removeAttribute("visible");
  }
  show() {
    this.visible = true;
    this._vk.show();
    this.render();
    this.dispatchEvent(
      new CustomEvent("mgl-ime-keyboard-show", { bubbles: true, composed: true })
    );
  }
  hide() {
    this._cancelPress();
    this._vk.emoji = false;
    this.visible = false;
    this._vk.hide();
    this.dispatchEvent(
      new CustomEvent("mgl-ime-keyboard-hide", { bubbles: true, composed: true })
    );
  }
  connectedCallback() {
    this.render();
  }
  disconnectedCallback() {
    this._cancelPress();
  }
  _emitKeyValue(value) {
    this._vk.onEvent({ type: "key", key: value });
    if (this._vk.shift) this._vk.shift = false;
    this._needsRender = true;
    if (!this._press) this._flushRender();
  }
  _emitPlain(value) {
    this.dispatchEvent(
      new CustomEvent("mgl-keyboard-event", {
        detail: { type: "command", command: "insert-plain", key: value },
        bubbles: true,
        composed: true
      })
    );
  }
  /** Keep editor focused — same as letter keys. */
  _guardTap(e, fn) {
    if (e.button != null && e.button !== 0) return;
    e.preventDefault();
    fn();
  }
  _flushRender() {
    if (!this._needsRender) return;
    this._needsRender = false;
    this.render();
  }
  _hidePopup() {
    this._popup.removeAttribute("open");
    this._popup.innerHTML = "";
    this._popup.setAttribute("aria-hidden", "true");
  }
  /**
   * @param {HTMLElement} btn
   * @param {import("../keyboard/popup-candidates.js").PopupKey[]} keys
   * @param {boolean} mongol
   * @param {number} selected
   */
  _showPopup(btn, keys, mongol, selected) {
    this._popup.innerHTML = "";
    keys.forEach((k, i) => {
      const el = document.createElement("div");
      el.className = "popup-item" + (mongol ? " mongol" : "");
      if (i === selected) el.classList.add("selected");
      el.textContent = k.display ?? k.text;
      this._popup.appendChild(el);
    });
    const rect = btn.getBoundingClientRect();
    this._popup.setAttribute("open", "");
    this._popup.setAttribute("aria-hidden", "false");
    const pRect = this._popup.getBoundingClientRect();
    const vw = window.innerWidth;
    let left = rect.left;
    if (rect.left + rect.width / 2 > vw / 2) {
      left = rect.right - pRect.width;
    }
    left = Math.max(8, Math.min(left, vw - pRect.width - 8));
    const top = Math.max(8, rect.top - pRect.height - 10);
    this._popup.style.left = `${left}px`;
    this._popup.style.top = `${top}px`;
  }
  /** @param {number} selected */
  _updatePopupSelection(selected) {
    [...this._popup.children].forEach((el, i) => {
      el.classList.toggle("selected", i === selected);
    });
  }
  _cancelPress() {
    if (this._press?.timer) clearTimeout(this._press.timer);
    if (this._press?.btn) this._press.btn.classList.remove("pressed");
    this._press = null;
    this._hidePopup();
    this._flushRender();
  }
  /**
   * @param {PointerEvent} e
   * @param {object} key
   * @param {HTMLButtonElement} btn
   */
  _onPointerDown(e, key, btn) {
    if (e.button != null && e.button !== 0) return;
    e.preventDefault();
    btn.setPointerCapture?.(e.pointerId);
    btn.classList.add("pressed");
    this._cancelPress();
    this._press = {
      key,
      btn,
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      dx: 0,
      popup: false,
      selected: 0,
      /** @type {import("../keyboard/popup-candidates.js").PopupKey[]} */
      popupKeys: [],
      timer: null
    };
    if (key.type === "action") {
      this._vk.press(key);
      this._needsRender = true;
      this._cancelPress();
      return;
    }
    this._press.timer = setTimeout(() => {
      if (!this._press || this._press.key !== key) return;
      const ctx = this.getEditingContext?.() ?? null;
      const popupKeys = resolvePopupKeys(key, ctx, { shift: this._vk.shift });
      if (!popupKeys.length) return;
      this._press.popup = true;
      this._press.popupKeys = popupKeys;
      this._press.selected = 0;
      this._showPopup(btn, popupKeys, !!key.mongol, 0);
    }, LONG_PRESS_MS);
  }
  /**
   * @param {PointerEvent} e
   */
  _onPointerMove(e) {
    const p = this._press;
    if (!p || !p.popup) return;
    p.dx = e.clientX - p.startX;
    const idx = popupIndexFromDx(p.dx, p.popupKeys.length);
    if (idx !== p.selected) {
      p.selected = idx;
      this._updatePopupSelection(idx);
    }
  }
  /**
   * @param {PointerEvent} e
   */
  _onPointerUp(e) {
    const p = this._press;
    if (!p) return;
    if (p.timer) clearTimeout(p.timer);
    if (p.popup && p.popupKeys.length) {
      const chosen = p.popupKeys[p.selected] ?? p.popupKeys[0];
      if (chosen?.text) {
        this._emitKeyValue(chosen.text);
      }
    } else if (p.key.type === "key") {
      this._vk.press(p.key);
    }
    p.btn.classList.remove("pressed");
    try {
      p.btn.releasePointerCapture?.(e.pointerId);
    } catch {
    }
    this._press = null;
    this._hidePopup();
    this._flushRender();
  }
  _renderEmojiPanel() {
    const panel = document.createElement("div");
    panel.className = "emoji-panel";
    const cats = document.createElement("div");
    cats.className = "emoji-cats";
    EMOJI_CATEGORIES.forEach((cat) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = cat.label;
      if (cat.id === this._vk.emojiCategory) btn.classList.add("active");
      btn.addEventListener(
        "pointerdown",
        (e) => this._guardTap(e, () => {
          this._vk.setEmojiCategory(cat.id);
          this.render();
        })
      );
      cats.appendChild(btn);
    });
    panel.appendChild(cats);
    const { items, page, pages } = this._vk.getEmojiPage();
    const grid = document.createElement("div");
    grid.className = "emoji-grid";
    items.forEach((emoji) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = emoji;
      btn.addEventListener(
        "pointerdown",
        (e) => this._guardTap(e, () => this._emitPlain(emoji))
      );
      grid.appendChild(btn);
    });
    panel.appendChild(grid);
    const nav = document.createElement("div");
    nav.className = "emoji-nav";
    const back = document.createElement("button");
    back.type = "button";
    back.textContent = this._vk.latin ? "ABC" : "mgl";
    back.addEventListener(
      "pointerdown",
      (e) => this._guardTap(e, () => this._vk.press({ type: "action", action: "emoji" }))
    );
    nav.appendChild(back);
    const prev = document.createElement("button");
    prev.type = "button";
    prev.textContent = "\u25C0";
    prev.disabled = page <= 0;
    prev.addEventListener(
      "pointerdown",
      (e) => this._guardTap(e, () => {
        this._vk.prevEmojiPage();
        this.render();
      })
    );
    nav.appendChild(prev);
    const meta = document.createElement("div");
    meta.className = "page";
    meta.textContent = `${page + 1}/${pages}`;
    nav.appendChild(meta);
    const next = document.createElement("button");
    next.type = "button";
    next.textContent = "\u25B6";
    next.disabled = page >= pages - 1;
    next.addEventListener(
      "pointerdown",
      (e) => this._guardTap(e, () => {
        this._vk.nextEmojiPage();
        this.render();
      })
    );
    nav.appendChild(next);
    const del = document.createElement("button");
    del.type = "button";
    del.textContent = ACTION_LABEL.backspace;
    del.addEventListener(
      "pointerdown",
      (e) => this._guardTap(e, () => this._vk.press({ type: "action", action: "backspace" }))
    );
    nav.appendChild(del);
    panel.appendChild(nav);
    this._wrap.appendChild(panel);
  }
  render() {
    this._wrap.innerHTML = "";
    if (this._vk.emoji) {
      this._renderEmojiPanel();
      return;
    }
    const rows = this._vk.getLayoutRows();
    const isMongolLayout = !this._vk.latin && !this._vk.special && !this._vk.otherSpecial;
    rows.forEach((row) => {
      const rowEl = document.createElement("div");
      rowEl.className = "row";
      row.forEach((key) => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "key";
        if (key.type === "action") {
          btn.classList.add("action");
          if (key.action === "space") btn.classList.add("space");
          const label = document.createElement("span");
          label.className = "label-action";
          if (key.action === "abc") {
            label.textContent = this._vk.latin ? "mgl" : "ABC";
          } else if (key.action === "special" && (this._vk.special || this._vk.otherSpecial)) {
            label.textContent = this._vk.latin ? "ABC" : "mgl";
          } else {
            label.textContent = ACTION_LABEL[key.action] ?? key.action;
          }
          if (key.action === "suffix") {
            label.style.writingMode = "vertical-lr";
            label.style.fontSize = "14px";
          }
          if (key.action === "emoji") {
            label.style.fontFamily = '"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif';
            label.style.fontSize = "18px";
          }
          btn.appendChild(label);
        } else {
          if (key.mongol) btn.classList.add("mongol");
          if (isMongolLayout && key.id && !["ng", "-", "_"].includes(key.id)) {
            const hint = document.createElement("span");
            hint.className = "hint";
            hint.textContent = key.id;
            btn.appendChild(hint);
          }
          const label = document.createElement("span");
          label.textContent = key.label;
          btn.appendChild(label);
        }
        btn.addEventListener("pointerdown", (ev) => this._onPointerDown(ev, key, btn));
        btn.addEventListener("pointermove", (ev) => this._onPointerMove(ev));
        btn.addEventListener("pointerup", (ev) => this._onPointerUp(ev));
        btn.addEventListener("pointercancel", () => this._cancelPress());
        rowEl.appendChild(btn);
      });
      this._wrap.appendChild(rowEl);
    });
  }
};
if (typeof customElements !== "undefined" && !customElements.get("mgl-keyboard")) {
  customElements.define("mgl-keyboard", MglKeyboard);
}

// src/components/mgl-ime-toggle.js
function buildTemplate3() {
  const TEMPLATE = document.createElement("template");
  TEMPLATE.innerHTML = `
  <style>
    :host { display: inline-flex; gap: 6px; font-family: system-ui, sans-serif; }
    button {
      border: 1px solid var(--mgl-ime-border, #bdb6a8);
      background: var(--mgl-ime-key-background, #faf8f4);
      border-radius: 8px;
      padding: 6px 10px;
      font-size: 13px;
      cursor: pointer;
    }
    button[aria-pressed="true"] {
      background: var(--mgl-ime-key-active, #c5d8ef);
    }
    button[data-act="emoji"] {
      font-family: "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
    }
  </style>
  <button type="button" part="enable" data-act="enable">IME</button>
  <button type="button" part="mode" data-act="mode">MN</button>
  <button type="button" part="keyboard" data-act="keyboard" hidden>\u2328</button>
  <button type="button" part="emoji" data-act="emoji" hidden>\u{1F60A}</button>
`;
  return TEMPLATE;
}
var _template3;
var Base3 = typeof HTMLElement !== "undefined" ? HTMLElement : class {
};
var MglImeToggle = class extends Base3 {
  constructor() {
    super();
    if (!_template3) _template3 = buildTemplate3();
    this.attachShadow({ mode: "open" }).appendChild(_template3.content.cloneNode(true));
    this._enableBtn = this.shadowRoot.querySelector('[data-act="enable"]');
    this._modeBtn = this.shadowRoot.querySelector('[data-act="mode"]');
    this._kbBtn = this.shadowRoot.querySelector('[data-act="keyboard"]');
    this._emojiBtn = this.shadowRoot.querySelector('[data-act="emoji"]');
  }
  connectedCallback() {
    this.shadowRoot.addEventListener("click", (e) => {
      const act = e.target?.dataset?.act;
      if (!act) return;
      this.dispatchEvent(
        new CustomEvent("mgl-toggle", {
          detail: { action: act },
          bubbles: true,
          composed: true
        })
      );
    });
  }
  /**
   * @param {{ enabled?: boolean, mode?: string, showKeyboardButton?: boolean, showEmojiButton?: boolean }} state
   */
  sync(state = {}) {
    this._enableBtn.setAttribute("aria-pressed", String(!!state.enabled));
    this._enableBtn.textContent = state.enabled ? "IME ON" : "IME OFF";
    this._modeBtn.textContent = state.mode === "latin" ? "LAT" : "MN";
    this._kbBtn.hidden = !state.showKeyboardButton;
    this._emojiBtn.hidden = !state.showEmojiButton;
  }
};
if (typeof customElements !== "undefined" && !customElements.get("mgl-ime-toggle")) {
  customElements.define("mgl-ime-toggle", MglImeToggle);
}

// src/components/mgl-emoji-picker.js
function buildTemplate4() {
  const TEMPLATE = document.createElement("template");
  TEMPLATE.innerHTML = `
  <style>
    :host {
      display: none;
      position: fixed;
      z-index: 10020;
      font-family: system-ui, sans-serif;
      color: var(--mgl-ime-text, #1c1c1c);
      --bg: var(--mgl-ime-candidate-background, #f7f5f0);
      --border: var(--mgl-ime-border, #bdb6a8);
      --key-bg: var(--mgl-ime-key-background, #faf8f4);
      --active: var(--mgl-ime-key-active, #c5d8ef);
    }
    :host([open]) { display: block; }
    .panel {
      width: min(360px, calc(100vw - 16px));
      height: min(380px, calc(100vh - 24px));
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      box-shadow: 0 10px 32px rgba(0,0,0,.16);
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    .cats {
      display: flex;
      flex: 0 0 44px;
      height: 44px;
      gap: 2px;
      padding: 4px 4px 0;
      box-sizing: border-box;
      border-bottom: 1px solid var(--border);
      overflow: hidden;
    }
    .cats button {
      flex: 1 1 0;
      min-width: 0;
      height: 40px;
      border: none;
      border-radius: 8px 8px 0 0;
      background: transparent;
      font-size: 18px;
      font-family: "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
      cursor: pointer;
      color: inherit;
    }
    .cats button.active { background: var(--key-bg); }
    .grid {
      display: grid;
      grid-template-columns: repeat(8, minmax(0, 1fr));
      gap: 2px;
      padding: 8px;
      flex: 1 1 auto;
      min-height: 0;
      min-width: 0;
      overflow-x: hidden;
      overflow-y: auto;
      background: var(--key-bg);
    }
    .grid button {
      width: 100%;
      min-width: 0;
      height: 36px;
      border: none;
      border-radius: 6px;
      background: transparent;
      font-size: 22px;
      line-height: 1;
      font-family: "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif;
      cursor: pointer;
      color: inherit;
    }
    .grid button:hover { background: var(--active); }
  </style>
  <div class="panel" part="panel">
    <div class="cats" part="cats"></div>
    <div class="grid" part="grid"></div>
  </div>
`;
  return TEMPLATE;
}
var _template4;
var Base4 = typeof HTMLElement !== "undefined" ? HTMLElement : class {
};
var MglEmojiPicker = class extends Base4 {
  constructor() {
    super();
    if (!_template4) _template4 = buildTemplate4();
    this.attachShadow({ mode: "open" }).appendChild(_template4.content.cloneNode(true));
    this._cats = this.shadowRoot.querySelector(".cats");
    this._grid = this.shadowRoot.querySelector(".grid");
    this._category = "smileys";
    this._ignore = null;
    this._onDocPointer = (e) => this._handleDocPointer(e);
    this._onDocKey = (e) => {
      if (e.key === "Escape" && this.open) {
        e.preventDefault();
        this.hide();
      }
    };
  }
  get open() {
    return this.hasAttribute("open");
  }
  set open(v) {
    if (v) this.setAttribute("open", "");
    else this.removeAttribute("open");
  }
  connectedCallback() {
    this._render();
  }
  disconnectedCallback() {
    this._unbindDoc();
  }
  /**
   * @param {{ ignore?: EventTarget|null }} [opts]
   */
  show(opts = {}) {
    this._ignore = opts.ignore ?? null;
    this.open = true;
    this._render();
    requestAnimationFrame(() => this._bindDoc());
    this.dispatchEvent(new CustomEvent("mgl-emoji-open", { bubbles: true, composed: true }));
  }
  hide() {
    if (!this.open) return;
    this.open = false;
    this._unbindDoc();
    this.dispatchEvent(new CustomEvent("mgl-emoji-close", { bubbles: true, composed: true }));
  }
  /**
   * @param {{ ignore?: EventTarget|null }} [opts]
   */
  toggle(opts = {}) {
    if (this.open) this.hide();
    else this.show(opts);
  }
  /**
   * @param {Element|{left:number,top:number,right?:number,bottom?:number,width?:number,height?:number}|null} anchor
   */
  positionNear(anchor) {
    if (!anchor) return;
    const rect = typeof anchor.getBoundingClientRect === "function" ? anchor.getBoundingClientRect() : anchor;
    const panel = this.shadowRoot.querySelector(".panel");
    const pRect = panel?.getBoundingClientRect() ?? { width: 360, height: 320 };
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const margin = 8;
    let left = rect.left;
    if (left + pRect.width > vw - margin) left = vw - margin - pRect.width;
    if (left < margin) left = margin;
    let top = (rect.bottom ?? rect.top + (rect.height ?? 0)) + margin;
    if (top + pRect.height > vh - margin) {
      top = (rect.top ?? 0) - pRect.height - margin;
    }
    if (top < margin) top = margin;
    this.style.left = `${Math.round(left)}px`;
    this.style.top = `${Math.round(top)}px`;
  }
  _bindDoc() {
    document.addEventListener("pointerdown", this._onDocPointer, true);
    document.addEventListener("keydown", this._onDocKey, true);
  }
  _unbindDoc() {
    document.removeEventListener("pointerdown", this._onDocPointer, true);
    document.removeEventListener("keydown", this._onDocKey, true);
  }
  /** @param {PointerEvent} e */
  _handleDocPointer(e) {
    const path = e.composedPath();
    if (path.includes(this)) return;
    if (this._ignore && path.includes(this._ignore)) return;
    this.hide();
  }
  _select(emoji) {
    this.dispatchEvent(
      new CustomEvent("mgl-emoji-select", {
        detail: { emoji },
        bubbles: true,
        composed: true
      })
    );
  }
  _render() {
    const cat = getEmojiCategory(this._category);
    this._category = cat.id;
    this._cats.innerHTML = "";
    EMOJI_CATEGORIES.forEach((c) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = c.label;
      if (c.id === cat.id) btn.classList.add("active");
      btn.addEventListener("mousedown", (e) => e.preventDefault());
      btn.addEventListener("click", () => {
        this._category = c.id;
        this._render();
      });
      this._cats.appendChild(btn);
    });
    this._grid.innerHTML = "";
    cat.items.forEach((emoji) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = emoji;
      btn.addEventListener("mousedown", (e) => e.preventDefault());
      btn.addEventListener("click", () => this._select(emoji));
      this._grid.appendChild(btn);
    });
  }
};
if (typeof customElements !== "undefined" && !customElements.get("mgl-emoji-picker")) {
  customElements.define("mgl-emoji-picker", MglEmojiPicker);
}

// src/components/mgl-ime.js
function resolveTarget(target) {
  if (!target) return null;
  if (typeof target === "string") return document.querySelector(target);
  return target;
}
function adapterForElement(el, custom) {
  if (custom) return custom;
  if (!el) throw new Error("MglIME requires target or adapter");
  if (el instanceof HTMLTextAreaElement) return TextareaAdapter(el);
  if (el instanceof HTMLInputElement) return InputAdapter(el);
  return ContentEditableAdapter(el);
}
var MglIME = class {
  /**
   * @param {object} options
   * @param {string|HTMLElement} [options.target]
   * @param {import("../adapters/custom.js").EditorAdapter} [options.adapter]
   * @param {"auto"|"desktop"|"mobile"} [options.profile]
   * @param {"auto"|"system"|"virtual"} [options.keyboard]
   * @param {string} [options.mode]
   * @param {import("../api/candidate-provider.js").CandidateProvider} [options.provider]
   * @param {object} [options.remote] — RemoteCandidateProvider options
   * @param {string} [options.theme]
   * @param {HTMLElement} [options.mount] — where to attach UI hosts
   * @param {boolean} [options.candidates=true]
   */
  constructor(options = {}) {
    this.options = options;
    this._listeners = /* @__PURE__ */ new Map();
    this._destroyed = false;
    this.profileSetting = options.profile ?? "auto";
    this.keyboardSetting = options.keyboard ?? "auto";
    this.profile = detectProfile(this.profileSetting);
    this.keyboardMode = resolveKeyboardMode(this.keyboardSetting, this.profile);
    this.targetEl = resolveTarget(options.target);
    this.adapter = adapterForElement(this.targetEl, options.adapter);
    this.provider = options.provider ?? createDefaultProvider({
      baseUrl: options.remote?.baseUrl ?? options.baseUrl ?? "http://dev1:3003",
      ...options.remote
    });
    this.core = new ImeCore({
      adapter: this.adapter,
      provider: this.provider,
      mode: options.mode ?? "mongol",
      profile: this.profile,
      emit: (type, detail) => this._emit(type, detail)
    });
    this.mount = options.mount ?? document.body;
    this._setupUI();
    this._attachProfile();
    this._boundState = (state) => this._onState(state);
    this.on("state", this._boundState);
    this._emit("mgl-ime-ready", { profile: this.profile, keyboardMode: this.keyboardMode });
  }
  _setupUI() {
    this.candidatesEl = document.createElement("mgl-candidates");
    this.candidatesEl.setAttribute(
      "variant",
      this.profile === "mobile" ? "bar" : "popup"
    );
    this.mount.appendChild(this.candidatesEl);
    this.keyboardEl = document.createElement("mgl-keyboard");
    this.mount.appendChild(this.keyboardEl);
    this.keyboardEl.getEditingContext = () => {
      try {
        const text = this.adapter.getText?.() ?? "";
        const { start } = this.adapter.getSelection?.() ?? { start: text.length };
        return { text, start };
      } catch {
        return null;
      }
    };
    this.candidatesEl.addEventListener("mgl-candidate-select", async (e) => {
      const { index, word } = e.detail;
      if (this.profile === "mobile") {
        await this.core.pickCandidateMobile(word);
      } else {
        await this.core.selectCandidate(index, { addSpaceAfter: true });
      }
    });
    this.keyboardEl.addEventListener("mgl-keyboard-event", async (e) => {
      if (this._mobile?.onKeyboardEvent) {
        await this._mobile.onKeyboardEvent(e.detail);
      } else {
        await this.core.handleEvent(e.detail);
      }
    });
    this.emojiPickerEl = document.createElement("mgl-emoji-picker");
    this.mount.appendChild(this.emojiPickerEl);
    this.emojiPickerEl.addEventListener("mgl-emoji-select", async (e) => {
      const emoji = e.detail?.emoji;
      if (!emoji) return;
      await this.core.handleEvent({ type: "command", command: "insert-plain", key: emoji });
      this.adapter.focus?.();
    });
    if (this.keyboardMode === "virtual") {
      this.showKeyboard();
    }
  }
  _attachProfile() {
    this._desktop?.detach?.();
    this._mobile?.detach?.();
    this._desktop = null;
    this._mobile = null;
    if (this.profile === "desktop") {
      this._desktop = attachDesktopController(this.core, {
        // Capture on window so we always see keydown before the editor inserts.
        target: window,
        editorEl: this.targetEl,
        shouldHandle: () => {
          if (!this.core.state.enabled) return false;
          if (!this.targetEl) return true;
          return document.activeElement === this.targetEl || this.targetEl.contains?.(document.activeElement);
        }
      });
      this.candidatesEl.setAttribute("variant", "popup");
      this._clearMobileCandidatePosition();
      if (this.keyboardMode !== "virtual") this.hideKeyboard();
    } else {
      this._mobile = attachMobileController(this.core, {
        editorEl: this.targetEl
      });
      this.candidatesEl.setAttribute("variant", "bar");
      this._positionMobileCandidates();
      if (this.keyboardMode === "virtual") this.showKeyboard();
    }
  }
  /** Fixed, horizontally centered, just above the virtual keyboard. */
  _positionMobileCandidates() {
    if (!this.candidatesEl) return;
    const kbH = this.keyboardEl?.offsetHeight || 240;
    const gap = 8;
    const el = this.candidatesEl;
    el.style.position = "fixed";
    el.style.left = "50%";
    el.style.right = "auto";
    el.style.transform = "translateX(-50%)";
    el.style.bottom = `${kbH + gap}px`;
    el.style.top = "auto";
    el.style.width = "";
  }
  /** Clear mobile positioning when switching to desktop. */
  _clearMobileCandidatePosition() {
    if (!this.candidatesEl) return;
    const el = this.candidatesEl;
    el.style.position = "";
    el.style.left = "";
    el.style.right = "";
    el.style.transform = "";
    el.style.bottom = "";
    el.style.top = "";
    el.style.width = "";
  }
  _onState(state) {
    this.candidatesEl?.update(state);
    if (this.profile === "desktop" && state.candidateVisible && state.candidates?.length) {
      this._clearMobileCandidatePosition();
      const rect = this.adapter.getCaretRect?.();
      if (rect) {
        this.candidatesEl.positionNear(rect);
      } else if (this.targetEl) {
        this.candidatesEl.positionNear(this.targetEl.getBoundingClientRect());
      }
      requestAnimationFrame(() => {
        const r = this.adapter.getCaretRect?.();
        if (r) this.candidatesEl.positionNear(r);
      });
    }
    if (this.profile === "mobile") {
      this._positionMobileCandidates();
    }
  }
  // ─── Public API ────────────────────────────────────────────
  enable() {
    this.core.enable();
  }
  disable() {
    this.hideEmojiPicker();
    this.core.disable();
  }
  show() {
    if (this.keyboardMode === "virtual") this.showKeyboard();
    this.candidatesEl.visible = true;
  }
  hide() {
    this.hideKeyboard();
    this.hideEmojiPicker();
    this.candidatesEl.visible = false;
  }
  focus() {
    this.adapter.focus?.();
  }
  blur() {
    this.adapter.blur?.();
  }
  setProfile(profile) {
    this.profileSetting = profile;
    this.profile = detectProfile(profile);
    this.keyboardMode = resolveKeyboardMode(this.keyboardSetting, this.profile);
    this.core.setProfile(this.profile);
    if (this.profile !== "desktop") this.hideEmojiPicker();
    this._attachProfile();
  }
  setMode(mode) {
    this.core.setMode(mode);
  }
  showKeyboard() {
    this.keyboardEl?.show();
    this.core.setState({ keyboardVisible: true });
    if (this.profile === "mobile") {
      requestAnimationFrame(() => this._positionMobileCandidates());
    }
  }
  hideKeyboard() {
    this.keyboardEl?.hide();
    this.core.setState({ keyboardVisible: false });
  }
  setKeyboardMode(mode) {
    this.keyboardSetting = mode;
    this.keyboardMode = resolveKeyboardMode(mode, this.profile);
    if (this.keyboardMode === "virtual") this.showKeyboard();
    else this.hideKeyboard();
  }
  showCandidates() {
    this.candidatesEl.visible = true;
  }
  hideCandidates() {
    this.candidatesEl.visible = false;
  }
  /**
   * @param {Element|{left:number,top:number}|null} [anchor]
   */
  showEmojiPicker(anchor) {
    const el = this.emojiPickerEl;
    if (!el) return;
    el.show({ ignore: anchor instanceof Element ? anchor : null });
    const target = anchor ?? this.adapter.getCaretRect?.() ?? this.targetEl?.getBoundingClientRect?.();
    if (target) {
      requestAnimationFrame(() => el.positionNear(target));
    }
    this.adapter.focus?.();
  }
  hideEmojiPicker() {
    this.emojiPickerEl?.hide();
  }
  /**
   * @param {Element|{left:number,top:number}|null} [anchor]
   */
  toggleEmojiPicker(anchor) {
    if (this.emojiPickerEl?.open) this.hideEmojiPicker();
    else this.showEmojiPicker(anchor);
  }
  nextCandidate() {
    this.core.nextCandidate();
  }
  previousCandidate() {
    this.core.previousCandidate();
  }
  selectCandidate(index) {
    return this.core.selectCandidate(index);
  }
  getState() {
    return this.core.getState();
  }
  on(type, fn) {
    if (!this._listeners.has(type)) this._listeners.set(type, /* @__PURE__ */ new Set());
    this._listeners.get(type).add(fn);
    return () => this.off(type, fn);
  }
  off(type, fn) {
    this._listeners.get(type)?.delete(fn);
  }
  _emit(type, detail) {
    this._listeners.get(type)?.forEach((fn) => {
      try {
        fn(detail);
      } catch (err) {
        console.error(err);
      }
    });
    this._listeners.get("*")?.forEach((fn) => fn(type, detail));
  }
  destroy() {
    if (this._destroyed) return;
    this._destroyed = true;
    this._desktop?.detach?.();
    this._mobile?.detach?.();
    this.core.destroy();
    this.candidatesEl?.remove();
    this.keyboardEl?.remove();
    this.emojiPickerEl?.remove();
    this._listeners.clear();
  }
};
var HtmlBase = typeof HTMLElement !== "undefined" ? HTMLElement : class {
};
var MglImeElement = class extends HtmlBase {
  constructor() {
    super();
    this._ime = null;
    this._booted = false;
  }
  static get observedAttributes() {
    return ["target", "profile", "keyboard", "mode", "theme", "disabled", "base-url"];
  }
  connectedCallback() {
    this._ime?.destroy();
    this._boot();
  }
  disconnectedCallback() {
    this._ime?.destroy();
    this._ime = null;
    this._booted = false;
  }
  attributeChangedCallback(_name, oldValue, newValue) {
    if (!this._booted || !this.isConnected) return;
    if (oldValue === newValue) return;
    this._ime?.destroy();
    this._boot();
  }
  _boot() {
    const target = this.getAttribute("target");
    if (!target && !this._adapter) return;
    this._ime = new MglIME({
      target,
      adapter: this._adapter,
      profile: this.getAttribute("profile") || "auto",
      keyboard: this.getAttribute("keyboard") || "auto",
      mode: this.getAttribute("mode") || "mongol",
      theme: this.getAttribute("theme") || "auto",
      baseUrl: this.getAttribute("base-url") || void 0,
      mount: this.parentElement ?? document.body
    });
    this._booted = true;
    if (this.hasAttribute("disabled")) this._ime.disable();
    const events = [
      "mgl-ime-ready",
      "mgl-ime-input",
      "mgl-ime-composition-start",
      "mgl-ime-composition-update",
      "mgl-ime-composition-end",
      "mgl-ime-candidates",
      "mgl-ime-commit",
      "mgl-ime-mode-change"
    ];
    events.forEach((name) => {
      this._ime.on(name, (detail) => {
        this.dispatchEvent(
          new CustomEvent(name, { detail, bubbles: true, composed: true })
        );
      });
    });
  }
  /** Allow setting a custom adapter from JS before connect. */
  set adapter(a) {
    this._adapter = a;
  }
  get ime() {
    return this._ime;
  }
};
if (typeof customElements !== "undefined" && !customElements.get("mgl-ime")) {
  customElements.define("mgl-ime", MglImeElement);
}
var mgl_ime_default = MglIME;
export {
  CandidateProvider,
  ContentEditableAdapter,
  EMOJI_CATEGORIES,
  EN_POPUP_KEYS,
  HybridCandidateProvider,
  ImeCore,
  InputAdapter,
  LATIN_TO_MONGOL,
  LAYOUTS,
  LocalCandidateProvider,
  MOBILE_EMOJI_PAGE_SIZE,
  MglCandidates,
  MglEmojiPicker,
  MglIME,
  MglImeElement,
  MglImeToggle,
  MglKeyboard,
  RemoteCandidateProvider,
  TextareaAdapter,
  VirtualKeyboard,
  adapterForElement,
  attachDesktopController,
  attachMobileController,
  createCustomAdapter,
  createDefaultProvider,
  createInitialState,
  currentCandidate,
  mgl_ime_default as default,
  detectProfile,
  directCharFromKey,
  getEmojiCategory,
  getEmojiPage,
  getLayout,
  measureCaretRect,
  mongolPopupCandidates,
  normalizeKey,
  pageCandidates,
  pageEmoji,
  placeNearCaret,
  resolveKeyboardMode,
  resolvePopupKeys,
  totalPages,
  translate
};
//# sourceMappingURL=mgl-web-ime.js.map
