// 設定の保存と、ウィンドウ間（帯・設定・分析）の同期。localStorage の storage イベントで他ウィンドウに伝わる。

const KEY = "settings.v1";

// Tauri のイベントでウィンドウ間に変更を伝える（ブラウザで開いたときは storage イベントだけ）
const T = window.__TAURI__;
export const LABEL = T ? T.window.getCurrentWindow().label : "web";
export function emit(name, payload) {
  if (T) T.event.emit(name, { ...payload, from: LABEL }).catch(() => {});
}
export function listen(name, f) {
  if (T) T.event.listen(name, (e) => { if (e.payload.from !== LABEL) f(e.payload); });
}

export const DEFAULTS = {
  mode: "japanese",          // japanese | english | novel | custom
  contentKind: "mix",        // sentences | words | mix
  bgOpacity: 0.4,
  textOpacity: 0.95,
  fontSize: 26,
  uiScale: 0.85,             // 帯全体の大きさ（文字・余白・キーボード・ボタンをまとめて拡大縮小）
  fontTheme: "modern",       // modern | round | textbook | system
  cursorStyle: "underline",  // underline | color | box
  showKeyboard: true,
  keyLayout: "auto",         // auto | jis | us
  dimWhenIdle: true,
  compact: false,
  seenTips: false,
  soundPreset: "thock",      // off | thock | clicky | soft | typewriter | pop
  soundVolume: 0.45,
  missSound: true,
  doneSound: true,
  customLines: [],
  novelId: "neko",           // 小説モードで読む作品
  novelPos: {},              // 作品ごとの読み進めた位置 { neko: 12, ... }
  bestKPM: 0,
};

const listeners = new Set();
let cache = load();

function load() {
  try {
    return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") };
  } catch {
    return { ...DEFAULTS };
  }
}

export function get(k) { return cache[k]; }
export function all() { return { ...cache }; }

export function set(k, v) {
  if (JSON.stringify(cache[k]) === JSON.stringify(v)) return;
  cache = { ...cache, [k]: v };
  localStorage.setItem(KEY, JSON.stringify(cache));
  for (const f of listeners) f(k, v);
  emit("store-changed", { k, v });
}

function applyRemote(k, v) {
  if (JSON.stringify(cache[k]) === JSON.stringify(v)) return;
  cache = { ...cache, [k]: v };
  for (const f of listeners) f(k, v);
}
listen("store-changed", ({ k, v }) => applyRemote(k, v));

/** 変更を購読（自ウィンドウ・他ウィンドウ両方）。戻り値で解除 */
export function subscribe(f) {
  listeners.add(f);
  return () => listeners.delete(f);
}

window.addEventListener("storage", (e) => {
  if (e.key !== KEY) return;
  const next = load();
  for (const k of Object.keys(next)) applyRemote(k, next[k]);
});

// ウィンドウ間の命令（統計のリセットなど）
const busListeners = new Set();
export function send(cmd, payload = null) { emit("bus", { cmd, payload }); }
export function onCommand(f) { busListeners.add(f); }
listen("bus", ({ cmd, payload }) => { for (const f of busListeners) f(cmd, payload); });

export const LABELS = {
  mode: { japanese: "日本語", english: "English", novel: "小説", custom: "カスタム" },
  contentKind: { sentences: "文章", words: "単語", mix: "ミックス" },
  fontTheme: { modern: "モダン", round: "まるっと", textbook: "教科書", system: "システム" },
  cursorStyle: { underline: "下線", color: "文字色", box: "うすい枠" },
  keyLayout: { auto: "自動", jis: "JIS", us: "US" },
  soundPreset: {
    off: "オフ", thock: "コトコト（木）", clicky: "カチカチ（青軸風）",
    soft: "スコスコ（静音）", typewriter: "タイプライター", pop: "ポップ",
  },
};

/** フォントの組み合わせ（インストールされていなければ順に代替） */
export function fontStacks(theme) {
  const mono = '"JetBrains Mono", "JetBrainsMono Nerd Font Mono", "Cascadia Mono", "Cascadia Code", "Fira Code", "SF Mono", Menlo, Consolas, monospace';
  switch (theme) {
    case "round":
      return { jp: '"Hiragino Maru Gothic ProN", "BIZ UDPGothic", "Yu Gothic UI", "Meiryo", sans-serif', jpWeight: 500, mono };
    case "textbook":
      return { jp: 'Klee, "UD Digi Kyokasho NK-R", "UD デジタル 教科書体 NK-R", "Yu Mincho", serif', jpWeight: 600, mono: 'Menlo, Consolas, monospace' };
    case "system":
      return { jp: 'system-ui, -apple-system, "Segoe UI", "Yu Gothic UI", sans-serif', jpWeight: 700, mono: 'ui-monospace, Menlo, Consolas, monospace' };
    default:
      return { jp: '"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", "Meiryo UI", "Meiryo", sans-serif', jpWeight: 700, mono };
  }
}
