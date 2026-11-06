// キー配列（JIS / US）、指の割り当て、物理キー → 文字の変換

export const FINGER_NAMES = ["左 小指", "左 薬指", "左 中指", "左 人差し指", "右 人差し指", "右 中指", "右 薬指", "右 小指", "親指"];
export const FINGER_COLORS = ["#f27390", "#faa659", "#f2d959", "#73d980", "#66ccd9", "#7399fa", "#b38cfa", "#eb80e6", "#bfbfbf"];

const FINGER_BY_COL = [
  [0, 0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7, 7],
  [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7],
  [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7],
  [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7],
];

const letters = (s, codes) => Array.from(s).map((c, i) => [c, c.toUpperCase(), codes[i]]);
const L1 = ["KeyQ", "KeyW", "KeyE", "KeyR", "KeyT", "KeyY", "KeyU", "KeyI", "KeyO", "KeyP"];
const L2 = ["KeyA", "KeyS", "KeyD", "KeyF", "KeyG", "KeyH", "KeyJ", "KeyK", "KeyL"];
const L3 = ["KeyZ", "KeyX", "KeyC", "KeyV", "KeyB", "KeyN", "KeyM"];
const DIGITS = ["Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9", "Digit0"];

// [通常, Shift, KeyboardEvent.code]
const RAW = {
  jis: [
    [["1", "!"], ["2", "\""], ["3", "#"], ["4", "$"], ["5", "%"], ["6", "&"], ["7", "'"], ["8", "("], ["9", ")"], ["0", ""]]
      .map((k, i) => [...k, DIGITS[i]]).concat([["-", "=", "Minus"], ["^", "~", "Equal"], ["¥", "|", "IntlYen"]]),
    letters("qwertyuiop", L1).concat([["@", "`", "BracketLeft"], ["[", "{", "BracketRight"]]),
    letters("asdfghjkl", L2).concat([[";", "+", "Semicolon"], [":", "*", "Quote"], ["]", "}", "Backslash"]]),
    letters("zxcvbnm", L3).concat([[",", "<", "Comma"], [".", ">", "Period"], ["/", "?", "Slash"], ["_", "_", "IntlRo"]]),
  ],
  us: [
    [["`", "~", "Backquote"]].concat([["1", "!"], ["2", "@"], ["3", "#"], ["4", "$"], ["5", "%"], ["6", "^"], ["7", "&"], ["8", "*"], ["9", "("], ["0", ")"]]
      .map((k, i) => [...k, DIGITS[i]])).concat([["-", "_", "Minus"], ["=", "+", "Equal"]]),
    letters("qwertyuiop", L1).concat([["[", "{", "BracketLeft"], ["]", "}", "BracketRight"], ["\\", "|", "Backslash"]]),
    letters("asdfghjkl", L2).concat([[";", ":", "Semicolon"], ["'", "\"", "Quote"]]),
    letters("zxcvbnm", L3).concat([[",", "<", "Comma"], [".", ">", "Period"], ["/", "?", "Slash"]]),
  ],
};

let detected = (navigator.language || "").startsWith("ja") ? "jis" : "us";

/** 実際のキー入力から JIS/US を推定（JIS 特有のキーが押されたら JIS） */
export function noteKeyCode(code) {
  if (code === "IntlYen" || code === "IntlRo") detected = "jis";
}

// Chromium 系（Windows の WebView2）なら OS のキー配列を問い合わせられる
if (navigator.keyboard && navigator.keyboard.getLayoutMap) {
  navigator.keyboard.getLayoutMap().then((m) => {
    if (m.get("Quote") === ":" || m.get("BracketLeft") === "@" || m.has("IntlYen")) detected = "jis";
    else if (m.get("Quote") === "'") detected = "us";
  }).catch(() => {});
}

export function resolveLayout(setting) {
  return setting === "jis" || setting === "us" ? setting : detected;
}

const cache = {};
/** 配列の行（キー定義の配列） */
export function rows(setting) {
  const name = resolveLayout(setting);
  if (cache[name]) return cache[name];
  const isUS = name === "us";
  cache[name] = RAW[name].map((keys, r) =>
    keys.map(([normal, shifted, code], c) => {
      const col = r === 0 && !isUS ? c + 1 : c;
      const fr = FINGER_BY_COL[r];
      const label = /^[a-z]$/.test(normal) ? normal.toUpperCase() : normal;
      return { normal, shifted, code, finger: fr[Math.min(col, fr.length - 1)], label };
    })
  );
  return cache[name];
}

/** 文字 → { key, shift } */
export function lookup(setting, ch) {
  if (ch === " ") return { key: { normal: " ", shifted: " ", code: "Space", finger: 8, label: "space" }, shift: false };
  for (const row of rows(setting)) for (const k of row) {
    if (k.normal === ch) return { key: k, shift: false };
    if (k.shifted === ch) return { key: k, shift: true };
  }
  return null;
}

/**
 * キーイベントから打った文字を得る。IME が有効で key が "Process" になる場合も
 * 物理キー（code）と配列表から文字を求めるので、日本語入力のままでも練習できる。
 */
export function charFromEvent(e, setting) {
  noteKeyCode(e.code);
  if (e.key && e.key.length === 1 && !e.isComposing && e.key !== "Process") {
    const c = e.key;
    const v = c.charCodeAt(0);
    if (v >= 32 && v < 127) return c;
  }
  if (e.code === "Space") return " ";
  for (const row of rows(setting)) for (const k of row) {
    if (k.code === e.code) {
      const c = e.shiftKey ? k.shifted : k.normal;
      return c && c.charCodeAt(0) < 127 ? c : null;
    }
  }
  return null;
}
