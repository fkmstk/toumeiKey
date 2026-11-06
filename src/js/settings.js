// 設定ウィンドウ。値は store に書くだけで、帯は store の変更を受けて即時に反映する。
import * as store from "./store.js";
import { LABELS } from "./store.js";
import { Analytics, formatDuration } from "./analytics.js";

const T = window.__TAURI__;
const isMac = navigator.platform.toUpperCase().includes("MAC");
const $ = (id) => document.getElementById(id);
const analytics = new Analytics();

function seg(key, labels, after) {
  const cur = store.get(key);
  const id = `seg-${key}`;
  setTimeout(() => {
    $(id).onclick = (e) => {
      const v = e.target.closest("button")?.dataset.v;
      if (!v) return;
      store.set(key, v);
      after?.(v);
      render();
    };
  });
  return `<div class="seg" id="${id}">${Object.entries(labels).map(([v, l]) => `<button data-v="${v}" class="${cur === v ? "on" : ""}">${l}</button>`).join("")}</div>`;
}

function range(key, label, min, max, step, fmt = (v) => v, after) {
  const id = `r-${key}`;
  setTimeout(() => {
    $(id).oninput = (e) => { store.set(key, Number(e.target.value)); $(id + "-v").textContent = fmt(Number(e.target.value)); };
    $(id).onchange = () => after?.();
  });
  return `<div class="line"><label>${label}</label><input type="range" id="${id}" min="${min}" max="${max}" step="${step}" value="${store.get(key)}"><span class="val" id="${id}-v">${fmt(store.get(key))}</span></div>`;
}

function toggle(key, label) {
  const id = `t-${key}`;
  setTimeout(() => { $(id).onchange = (e) => store.set(key, e.target.checked); });
  return `<label class="line"><input type="checkbox" id="${id}" ${store.get(key) ? "checked" : ""}> ${label}</label>`;
}

const pct = (v) => `${Math.round(v * 100)}`;

function render() {
  $("look").innerHTML =
    `<div class="line"><label>フォント</label>${seg("fontTheme", LABELS.fontTheme)}</div>` +
    `<div class="line"><label>現在位置の表示</label>${seg("cursorStyle", LABELS.cursorStyle)}</div>` +
    range("fontSize", "文字サイズ", 16, 56, 1) +
    range("bgOpacity", "背景の濃さ", 0, 0.95, 0.01, pct) +
    range("textOpacity", "全体の濃さ", 0.2, 1, 0.01, pct) +
    toggle("dimWhenIdle", "タイピングしていない間は薄くする") +
    toggle("compact", "コンパクト表示（統計と次の文を隠す）");

  $("practice").innerHTML =
    `<div class="line"><label>出題</label>${seg("contentKind", LABELS.contentKind)}</div>` +
    toggle("showKeyboard", "キーボードガイドを表示") +
    `<div class="line"><label>キー配列</label>${seg("keyLayout", LABELS.keyLayout)}</div>` +
    `<div class="btns"><button id="b-file">ファイルから読み込む…</button><button id="b-paste">クリップボードから</button></div>` +
    `<div class="note">カスタム文は1行1問。漢字を含む文は「今日は晴れ|きょうははれ」のように | の後に読みを書く。<br>日本語入力（IME）がオンのままでも、物理キーから文字を判定するので練習できます。</div>`;
  $("b-file").onclick = () => store.send("openFile");
  $("b-paste").onclick = () => store.send("pasteCustom");

  const sel = Object.entries(LABELS.soundPreset).map(([v, l]) => `<option value="${v}" ${store.get("soundPreset") === v ? "selected" : ""}>${l}</option>`).join("");
  $("sound").innerHTML =
    `<div class="line"><label>タイプ音</label><select id="s-preset">${sel}</select></div>` +
    range("soundVolume", "音量", 0, 1, 0.01, pct, () => store.send("previewSound")) +
    toggle("missSound", "ミスしたときの音") +
    toggle("doneSound", "行をクリアしたときのチャイム");
  $("s-preset").onchange = (e) => { store.set("soundPreset", e.target.value); store.send("previewSound"); };

  const t = analytics.today;
  $("records").innerHTML =
    `<div class="kv">今日の練習時間 <b>${formatDuration(t.activeSec)}</b></div>` +
    `<div class="kv">今日の打鍵数 / 行数 <b>${t.keys} / ${t.lines}</b></div>` +
    `<div class="kv">連続練習 <b>${analytics.streak} 日</b></div>` +
    `<div class="kv">ベスト KPM <b>${store.get("bestKPM")}</b></div>` +
    `<div class="btns"><button id="b-an">統計・分析を開く…</button><button id="b-rs">セッションをリセット</button><button id="b-rr" class="danger">記録を消去</button></div>`;
  $("b-an").onclick = () => T?.core.invoke("open_window", { kind: "analytics" });
  $("b-rs").onclick = () => store.send("resetSession");
  $("b-rr").onclick = async () => {
    const ok = T ? await T.dialog.ask("キー別・日別・行ごとの記録とベスト KPM をすべて消去します。元に戻せません。", { title: "記録を消去", kind: "warning" }) : confirm("記録を消去しますか？");
    if (ok) store.send("resetRecords");
  };

  const m = isMac ? "⌘" : "Ctrl+";
  $("keys").textContent =
    `Ctrl+Alt+T   タイピング ⇄ ブラウザのフォーカス切替\nEsc  行の最初から / Tab  スキップ\n` +
    `${m}1 ${m}2 ${m}3   日本語 / English / カスタム\n${m},  設定 / ${m}S  統計・分析 / ${m}K  コンパクト表示\n` +
    `${m}V  クリップボード / ${m}O  ファイル\n${m}W  隠す / ${m}Q  終了\n右クリックでメニュー`;
}

store.subscribe((k) => { if (!document.activeElement || document.activeElement.type !== "range") render(); });
analytics.onChange(render);
render();
