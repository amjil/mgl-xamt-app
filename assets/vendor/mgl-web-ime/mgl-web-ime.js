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
  /** Mobile: insert Mongol char and refresh candidates from last word. */
  async _insertDirectMobile(ch) {
    this.adapter.insertText(ch);
    this.setState({ pendingSuffixDelete: false });
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
    getCaretRect: () => {
      const range = getRange();
      if (!range) return el.getBoundingClientRect();
      const rects = range.getClientRects();
      if (rects.length) return rects[0];
      const mirror = range.cloneRange();
      const span = document.createElement("span");
      span.textContent = "\u200B";
      mirror.insertNode(span);
      const r = span.getBoundingClientRect();
      span.parentNode?.removeChild(span);
      return r;
    }
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
    ["special", "abc", "suffix", "\u1802", "space", "\u1803", "enter"]
  ],
  "mongol-special": [
    ["\u1811", "\u1812", "\u1813", "\u1814", "\u1815", "\u1816", "\u1817", "\u1818", "\u1819", "\u1810"],
    ["@", "#", "\u20AC", "_", "&", "\uFF0D", "+", "\uFF08", "\uFF09", "/"],
    ["other-special", "\u203B", "\u1801", "\uFE11", "\uFE13", "\uFF1B", "\uFF01", "\uFF1F", "backspace"],
    ["special", "abc", ",", "space", ".", "enter"]
  ],
  "mongol-other-special": [
    ["\uFF5E", '"', "|", "\xB7", "\u221A", "\u220F", "\xF7", "\u1805", "\xB6", "\u25B3"],
    ["\xA3", "\xA5", "$", "\xA2", "\u2049", "\u2048", "=", "\u2774", "\u2775", "\\"],
    ["other-special", "\u1804", "\u1806", "\u2026", "\u1801", "\uFF3B", "\uFF3D", "backspace"],
    ["special", "abc", ",", "space", ".", "enter"]
  ],
  latin: [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    ["shift", "z", "x", "c", "v", "b", "n", "m", "backspace"],
    ["special", "abc", ",", "space", ".", "enter"]
  ],
  "latin-special": [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["@", "#", "\u20AC", "_", "&", "-", "+", "(", ")", "/"],
    ["other-special", "*", '"', "'", ":", ";", "!", "?", "backspace"],
    ["special", "abc", ",", "space", ".", "enter"]
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
  "suffix"
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
    this.visible = false;
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
        break;
      case "other-special":
        this.otherSpecial = !this.otherSpecial;
        break;
      case "abc":
        this.latin = !this.latin;
        this.special = false;
        this.otherSpecial = false;
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
   * Place popup near caret with collision detection against viewport edges.
   * @param {{left:number, top:number, bottom?:number, right?:number, width?:number, height?:number}} rect
   */
  positionNear(rect, placement = "auto") {
    if (this.getAttribute("variant") === "bar") return;
    const gap = 8;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const panel = this.shadowRoot.querySelector(".panel");
    const pRect = panel ? panel.getBoundingClientRect() : null;
    const pWidth = pRect ? pRect.width : 200;
    const pHeight = pRect ? pRect.height : 60;
    const isVertical = rect.width > rect.height || rect.height < 5;
    let place = placement === "auto" ? isVertical ? "right" : "bottom" : placement;
    if (place === "right" && rect.right + gap + pWidth > vw) {
      place = rect.left - gap - pWidth > 0 ? "left" : "bottom";
    } else if (place === "bottom" && rect.bottom + gap + pHeight > vh) {
      place = rect.top - gap - pHeight > 0 ? "top" : "right";
    }
    let left = 0;
    let top = 0;
    if (place === "right") {
      left = rect.right + gap;
      top = rect.top;
    } else if (place === "left") {
      left = rect.left - gap - pWidth;
      top = rect.top;
    } else if (place === "bottom") {
      left = rect.left;
      top = rect.bottom + gap;
    } else {
      left = rect.left;
      top = rect.top - gap - pHeight;
    }
    left = Math.max(8, Math.min(left, vw - pWidth - 8));
    top = Math.max(8, Math.min(top, vh - pHeight - 8));
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
  suffix: "\u1833\u1820\u182D\u1820\u182A\u1824\u1837\u1822"
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
      gap: 4px;
      margin: 4px 0;
    }
    button.key {
      flex: 1 1 0;
      min-width: 0;
      min-height: 46px;
      border: none;
      border-radius: 8px;
      background: var(--key-bg);
      box-shadow: 0 1px 0 rgba(0,0,0,.08);
      font: inherit;
      font-size: 20px;
      color: inherit;
      padding: 0 2px;
      position: relative;
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
      min-height: 52px;
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
  render() {
    const rows = this._vk.getLayoutRows();
    const isMongolLayout = !this._vk.latin && !this._vk.special && !this._vk.otherSpecial;
    this._wrap.innerHTML = "";
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
          label.textContent = ACTION_LABEL[key.action] ?? key.action;
          if (key.action === "suffix") {
            label.style.writingMode = "vertical-lr";
            label.style.fontSize = "14px";
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
  </style>
  <button type="button" part="enable" data-act="enable">IME</button>
  <button type="button" part="mode" data-act="mode">MN</button>
  <button type="button" part="keyboard" data-act="keyboard" hidden>\u2328</button>
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
   * @param {{ enabled?: boolean, mode?: string, showKeyboardButton?: boolean }} state
   */
  sync(state = {}) {
    this._enableBtn.setAttribute("aria-pressed", String(!!state.enabled));
    this._enableBtn.textContent = state.enabled ? "IME ON" : "IME OFF";
    this._modeBtn.textContent = state.mode === "latin" ? "LAT" : "MN";
    this._kbBtn.hidden = !state.showKeyboardButton;
  }
};
if (typeof customElements !== "undefined" && !customElements.get("mgl-ime-toggle")) {
  customElements.define("mgl-ime-toggle", MglImeToggle);
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
    this.core.disable();
  }
  show() {
    if (this.keyboardMode === "virtual") this.showKeyboard();
    this.candidatesEl.visible = true;
  }
  hide() {
    this.hideKeyboard();
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
  EN_POPUP_KEYS,
  HybridCandidateProvider,
  ImeCore,
  InputAdapter,
  LATIN_TO_MONGOL,
  LAYOUTS,
  LocalCandidateProvider,
  MglCandidates,
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
  getLayout,
  mongolPopupCandidates,
  normalizeKey,
  pageCandidates,
  resolveKeyboardMode,
  resolvePopupKeys,
  totalPages,
  translate
};
//# sourceMappingURL=mgl-web-ime.js.map
