// 帯（メインの半透明ウィンドウ）
import * as store from "./store.js";
import { LABELS, fontStacks } from "./store.js";
import { Analytics, formatDuration } from "./analytics.js";
import { TypingModel } from "./model.js";
import { NOVELS } from "./novels.js";
import { SoundEngine } from "./sound.js";
import { rows, lookup, charFromEvent, FINGER_COLORS, FINGER_NAMES } from "./keyboard.js";

const T = window.__TAURI__;
const invoke = (cmd, args) => (T ? T.core.invoke(cmd, args) : Promise.resolve());
const win = T ? T.window.getCurrentWindow() : null;
const isMac = navigator.platform.toUpperCase().includes("MAC");

const $ = (id) => document.getElementById(id);
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

const analytics = new Analytics();
const model = new TypingModel(analytics);
const sound = new SoundEngine();

let focused = document.hasFocus();
let hovering = false;

// ---------- 描画 ----------

function applyStyle() {
  const s = store.all();
  const f = fontStacks(s.fontTheme);
  const r = document.documentElement.style;
  r.setProperty("--bg-opacity", s.bgOpacity);
  r.setProperty("--text-opacity", s.textOpacity);
  r.setProperty("--fs", `${s.fontSize}px`);
  r.setProperty("--jp", f.jp);
  r.setProperty("--jp-weight", f.jpWeight);
  r.setProperty("--mono", f.mono);
}

function parts([done, cur, rest]) {
  const style = store.get("cursorStyle");
  const c = cur === " " ? "␣" : cur;
  return `<span class="done-part">${esc(done)}</span>` +
    (c ? `<span class="cur ${style}${model.missFlash ? " missed" : ""}">${esc(c)}</span>` : "") +
    `<span class="rest-part">${esc(rest)}</span>`;
}

function stat(k, v) { return `<span class="stat"><span class="k">${k}</span><span class="v">${esc(String(v))}</span></span>`; }

function renderKeyboard() {
  const el = $("kbd");
  if (!store.get("showKeyboard")) { el.innerHTML = ""; return; }
  const layout = store.get("keyLayout");
  const u = Math.max(16, Math.min(24, store.get("fontSize") * 0.72));
  const hit = lookup(layout, model.nextKey);
  const target = hit?.key;
  const shift = hit?.shift;
  const shiftL = shift && target.finger >= 4, shiftR = shift && target.finger < 4;
  const key = (label, finger, w, on) => {
    const c = FINGER_COLORS[finger];
    return `<div class="key${on ? " on" : ""}" style="width:${w}px;height:${u}px;font-size:${u * 0.48}px;` +
      `background:${on ? c : c + "29"};${on ? "" : `border:0.5px solid ${c}59;`}">${esc(label)}</div>`;
  };
  const indent = [0, 0.5, 0.8, 1.3];
  let html = "";
  rows(layout).forEach((row, r) => {
    html += `<div class="r">`;
    html += r === 3 ? key("⇧", 0, u * 1.1, shiftL) : `<div style="width:${u * indent[r]}px"></div>`;
    for (const k of row) html += key(k.label, k.finger, u, target && k.code === target.code);
    if (r === 3) html += key("⇧", 7, u * 1.4, shiftR);
    html += `</div>`;
  });
  html += `<div class="r"><div style="width:${u * 3.4}px"></div>${key("space", 8, u * 5.5, target?.finger === 8)}</div>`;
  html += `<div class="finger" style="color:${target ? FINGER_COLORS[target.finger] : "transparent"}">` +
    `${target ? FINGER_NAMES[target.finger] + (shift ? " + Shift" : "") : "&nbsp;"}</div>`;
  el.innerHTML = html;
}

function render() {
  const s = store.all();
  const card = $("card");
  card.classList.toggle("focused", focused);
  card.classList.toggle("hover", hovering);
  card.classList.toggle("miss", model.missFlash);
  card.classList.toggle("done", model.doneFlash && !model.missFlash);
  card.classList.toggle("dimmed", s.dimWhenIdle && !focused && !hovering);
  card.classList.toggle("compact", s.compact);

  if (s.compact) $("stats").style.display = "none";
  else {
    $("stats").style.display = "";
    let h = stat("KPM", model.kpm) + stat("正確率", model.accuracy.toFixed(1) + "%") + stat("ミス", model.misses);
    if (model.lastLineKPM != null) h += stat("前の行", model.lastLineKPM);
    h += stat("ベスト", model.bestKPM) + stat("今日", formatDuration(analytics.today.activeSec));
    if (model.mode === "novel") h += stat("小説", `${model.novel.title} ${model.novelPos + 1}/${model.novelLines.length}`);
    if (model.topWeakKeys.length) h += stat("苦手", model.topWeakKeys.map((k) => (k === " " ? "␣" : k)).join(" "));
    $("stats").innerHTML = h;
  }

  if (model.showsReading) {
    $("display").style.display = ""; $("kana").style.display = "";
    $("display").textContent = model.sentence.display;
    $("kana").innerHTML = parts(model.kanaParts);
  } else {
    $("display").style.display = "none"; $("kana").style.display = "none";
  }
  $("romaji").innerHTML = parts(model.romajiParts);
  $("bar").style.width = `${model.progress * 100}%`;

  $("next").style.display = s.compact ? "none" : "";
  $("next").textContent = "次: " + model.upcoming.display;

  const hint = $("hint");
  if (!s.seenTips) {
    const mod = isMac ? "⌘" : "Ctrl+";
    hint.innerHTML = `💡 <span>Ctrl+Alt+T でブラウザ ⇄ タイピング切替　右クリックでメニュー　${mod}, で設定</span><button id="tips-ok">OK</button>`;
    $("tips-ok").onclick = () => store.set("seenTips", true);
  } else if (!focused) {
    hint.innerHTML = `<span>⏸ 一時停止中 — クリック or Ctrl+Alt+T で再開</span>`;
  } else hint.innerHTML = "";

  $("modes").innerHTML = Object.entries(LABELS.mode)
    .filter(([m]) => m !== "custom" || model.custom.length)
    .map(([m, l]) => `<button data-mode="${m}" class="${model.mode === m ? "on" : ""}">${l}</button>`).join("");

  renderKeyboard();
}

let toastTimer;
function toast(msg) {
  const t = $("toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), 2500);
}

// ---------- 高さを内容に合わせる ----------

let lastH = 0;
new ResizeObserver(() => {
  const h = Math.ceil($("card").getBoundingClientRect().height);
  if (Math.abs(h - lastH) > 0.5) { lastH = h; invoke("fit_height", { height: h }); }
}).observe($("card"));

// ---------- 音 ----------

function playKey(c) {
  const finger = lookup(store.get("keyLayout"), c)?.key.finger ?? 8;
  const pan = finger === 8 ? 0 : ((finger - 3.5) / 3.5) * 0.45;
  sound.key(c === " ", pan);
}

model.onChange = render;
model.onEvent = (e, c) => {
  if (e === "hit") playKey(c);
  else if (e === "lineDone") { playKey(c); if (store.get("doneSound")) sound.lineDone(); }
  else if (e === "miss" && store.get("missSound")) sound.miss();
  else if (e === "novelDone") toast(`『${model.novel.title}』を読み終えました！最初に戻ります`);
};

// ---------- 操作 ----------

function setMode(m) {
  if (!model.setMode(m)) { toast(`カスタム文がまだありません（${isMac ? "⌘" : "Ctrl+"}V / ${isMac ? "⌘" : "Ctrl+"}O で読み込み）`); return; }
  toast(m === "novel" ? `小説モード —『${model.novel.title}』${model.novelPos + 1} 行目から` : `${LABELS.mode[m]} モード`);
}

function setNovel(id) {
  store.set("novelId", id);
  if (model.mode !== "novel") model.setMode("novel");
  else model.novelChanged();
  toast(`『${model.novel.title}』${model.novelPos + 1} 行目から`);
}

function restartNovel() {
  model.setNovelPos(0);
  model.novelChanged();
  toast(`『${model.novel.title}』を最初から`);
}

function loadCustom(text) {
  const n = model.loadCustom(text || "");
  toast(n > 0 ? `${n} 行を読み込みました` : "練習できる行がありませんでした");
  render();
}

async function pasteCustom() {
  try {
    const text = T ? await T.clipboardManager.readText() : await navigator.clipboard.readText();
    if (!text) { toast("クリップボードに文章がありません"); return; }
    loadCustom(text);
  } catch { toast("クリップボードを読めませんでした"); }
}

async function openFile() {
  if (!T) return;
  const path = await T.dialog.open({ multiple: false, filters: [{ name: "テキスト", extensions: ["txt", "md", "csv"] }] });
  if (!path) return;
  try { loadCustom(await invoke("read_text_file", { path })); } catch (e) { toast("読み込めませんでした: " + e); }
  win?.setFocus();
}

const openWindow = (kind) => invoke("open_window", { kind });
const hide = () => invoke("hide_main");
const quit = () => { analytics.saveNow(); invoke("quit"); };

document.addEventListener("keydown", (e) => {
  const mod = isMac ? e.metaKey : e.ctrlKey;
  if (mod && !e.altKey) {
    const k = e.key.toLowerCase();
    const actions = {
      "1": () => setMode("japanese"), "2": () => setMode("english"), "3": () => setMode("novel"), "4": () => setMode("custom"),
      ",": () => openWindow("settings"), s: () => openWindow("analytics"), k: () => store.set("compact", !store.get("compact")),
      v: pasteCustom, o: openFile, w: hide, q: quit,
    };
    if (actions[k]) { e.preventDefault(); actions[k](); }
    return;
  }
  if (e.ctrlKey || e.altKey || e.metaKey) return;
  if (e.key === "Escape") { e.preventDefault(); model.restartLine(); render(); return; }
  if (e.key === "Tab") { e.preventDefault(); model.skip(); return; }
  const c = charFromEvent(e, store.get("keyLayout"));
  if (c) { e.preventDefault(); model.type(c); }
});

window.addEventListener("focus", () => { focused = true; render(); });
window.addEventListener("blur", () => { focused = false; render(); });
document.addEventListener("mouseenter", () => { hovering = true; render(); });
// 非アクティブなウィンドウでは mouseenter が来ないことがあるので mousemove でも拾う
document.addEventListener("mousemove", () => { if (!hovering) { hovering = true; render(); } });
document.addEventListener("mouseleave", () => { hovering = false; render(); });

// 背景をドラッグして移動
$("card").addEventListener("mousedown", (e) => {
  if (e.button !== 0 || e.target.closest("button")) return;
  win?.startDragging();
});

$("modes").addEventListener("click", (e) => { const m = e.target.closest("button")?.dataset.mode; if (m) setMode(m); });
$("btn-analytics").onclick = () => openWindow("analytics");
$("btn-settings").onclick = () => openWindow("settings");
$("btn-hide").onclick = quit;

// 右クリックメニュー
document.addEventListener("contextmenu", async (e) => {
  e.preventDefault();
  if (!T) return;
  const { Menu, Submenu, MenuItem, CheckMenuItem, PredefinedMenuItem } = T.menu;
  const s = store.all();
  const mod = isMac ? "Cmd" : "Ctrl";
  const check = (text, checked, action, accelerator) => CheckMenuItem.new({ text, checked, action, accelerator });
  const item = (text, action, accelerator) => MenuItem.new({ text, action, accelerator });
  const modes = await Promise.all(Object.entries(LABELS.mode).map(([m, l], i) =>
    CheckMenuItem.new({ text: l, checked: model.mode === m, enabled: m !== "custom" || model.custom.length > 0, accelerator: `${mod}+${i + 1}`, action: () => setMode(m) })));
  const kinds = await Promise.all(Object.entries(LABELS.contentKind).map(([k, l]) =>
    check(l, s.contentKind === k, () => { store.set("contentKind", k); model.contentKindChanged(); toast(`出題: ${l}`); })));
  const novels = await Promise.all(NOVELS.map((n) =>
    check(`${n.title}（${n.author}）`, model.mode === "novel" && model.novel.id === n.id, () => setNovel(n.id))));
  novels.push(await PredefinedMenuItem.new({ item: "Separator" }), await item("今の作品を最初から読む", restartNovel));
  const sounds = await Promise.all(Object.entries(LABELS.soundPreset).map(([k, l]) =>
    check(l, s.soundPreset === k, () => { store.set("soundPreset", k); sound.preview(); })));
  const menu = await Menu.new({
    items: [
      ...modes,
      await Submenu.new({ text: "出題", items: kinds }),
      await Submenu.new({ text: "小説", items: novels }),
      await PredefinedMenuItem.new({ item: "Separator" }),
      await item("統計・分析…", () => openWindow("analytics"), `${mod}+S`),
      await item("設定…", () => openWindow("settings"), `${mod}+,`),
      await check("コンパクト表示", s.compact, () => store.set("compact", !s.compact), `${mod}+K`),
      await check("キーボードガイド", s.showKeyboard, () => store.set("showKeyboard", !s.showKeyboard)),
      await Submenu.new({ text: "タイプ音", items: sounds }),
      await PredefinedMenuItem.new({ item: "Separator" }),
      await item("テキストファイルで練習…", openFile, `${mod}+O`),
      await item("クリップボードの文章で練習", pasteCustom, `${mod}+V`),
      await PredefinedMenuItem.new({ item: "Separator" }),
      await item("位置をリセット", () => invoke("reset_position")),
      await item("隠す", hide, `${mod}+W`),
      await item("終了", quit, `${mod}+Q`),
    ],
  });
  menu.popup();
});

// ---------- 他ウィンドウとの連携 ----------

store.subscribe((k, v) => {
  if (k === "mode" && v !== model.mode) model.setMode(v);
  if (k === "contentKind") model.contentKindChanged();
  if (k === "novelId") model.novelChanged();
  // 設定ウィンドウで位置を変えたときだけ読み直す（自分で1行進めたときは何もしない）
  if (k === "novelPos" && model.mode === "novel" && model.sentence !== model.novelLines[model.novelPos]) model.novelChanged();
  if (k === "bestKPM") model.bestKPM = v;
  if (k === "soundPreset" || k === "soundVolume") {/* 再生時に読む */}
  applyStyle();
  render();
});

store.onCommand((cmd, payload) => {
  switch (cmd) {
    case "resetSession": model.resetSession(); break;
    case "resetRecords": model.resetRecords(); break;
    case "openFile": openFile(); break;
    case "pasteCustom": pasteCustom(); break;
    case "previewSound": sound.preview(); break;
  }
});
analytics.onChange(() => render());
if (T) T.event.listen("flush", () => analytics.saveNow());
window.addEventListener("beforeunload", () => analytics.saveNow());

applyStyle();
render();
