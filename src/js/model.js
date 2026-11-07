// タイピングの状態と判定。Swift 版 TypingModel の移植。
import { units as toUnits, parseSentence } from "./romaji.js";
import { VOCAB } from "./vocab.js";
import * as store from "./store.js";
import { NOVELS } from "./novels.js";

const IDLE_CAP = 2.0;
const JP = VOCAB.japanese.map(([display, reading]) => ({ display, reading }));
const EN = VOCAB.english.map((s) => ({ display: s, reading: s }));
const NOVEL_LINES = Object.fromEntries(NOVELS.map((n) => [n.id, n.lines.map(([display, reading]) => ({ display, reading }))]));

function shuffle(a) {
  const b = [...a];
  for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; }
  return b;
}

function wordLine(japanese) {
  if (japanese) {
    const ws = shuffle(VOCAB.jpWords).slice(0, 4);
    return { display: ws.map((w) => w[0]).join("　"), reading: ws.map((w) => w[1]).join("　") };
  }
  const s = shuffle(VOCAB.enWords).slice(0, 7).join(" ");
  return { display: s, reading: s };
}

const same = (a, b) => a && b && a.display === b.display && a.reading === b.reading;

export class TypingModel {
  constructor(analytics) {
    this.analytics = analytics;
    this.onChange = () => {};
    this.onEvent = () => {};
    this.custom = (store.get("customLines") || []).map(parseSentence).filter(Boolean);
    let mode = store.get("mode");
    if (mode === "custom" && !this.custom.length) mode = "japanese";
    this.mode = mode;
    this.bestKPM = store.get("bestKPM") || 0;
    this.upcoming = null;
    this.upcomingKey = "";
    this.missFlash = false;
    this.doneFlash = false;
    this.resetSession(false);
    this.nextSentence();
  }

  // ---- 統計 ----
  get kpm() { return this.activeTime > 1 ? Math.floor((this.correct / this.activeTime) * 60) : 0; }
  get accuracy() { const t = this.correct + this.misses; return t === 0 ? 100 : (this.correct / t) * 100; }
  get topWeakKeys() { return Object.entries(this.weakKeys).sort((a, b) => b[1] - a[1]).slice(0, 3).map((e) => e[0]); }
  get progress() { return this.units.length ? this.index / this.units.length : 0; }

  // ---- 表示用 ----
  guide(i) {
    if (i < this.index) return this.typed[i];
    const u = this.units[i];
    if (i === this.index && this.buffer) return u.options.find((o) => o.startsWith(this.buffer)) || u.options[0];
    return u.options[0];
  }

  /** [打ち終えた部分, 次に打つ1文字, 残り] */
  get romajiParts() {
    if (!this.units.length) return ["", "", ""];
    const done = this.typed.join("") + this.buffer;
    if (this.index >= this.units.length) return [done, "", ""];
    let rest = this.guide(this.index).slice(this.buffer.length);
    for (let i = this.index + 1; i < this.units.length; i++) rest += this.guide(i);
    return [done, rest.slice(0, 1), rest.slice(1)];
  }
  get nextKey() { return this.romajiParts[1]; }

  get kanaParts() {
    const d = this.units.slice(0, this.index).map((u) => u.display).join("");
    const c = this.index < this.units.length ? this.units[this.index].display : "";
    const r = this.units.slice(this.index + 1).map((u) => u.display).join("");
    return [d, c, r];
  }
  get showsReading() { return this.sentence.display !== this.sentence.reading; }
  get caseInsensitive() { return !/[A-Z]/.test(this.sentence.reading); }

  // ---- 入力 ----
  type(raw) {
    if (this.index >= this.units.length) return;
    const ch = this.caseInsensitive ? raw.toLowerCase() : raw;
    const now = performance.now() / 1000;
    let interval = null;
    if (this.lastKeyAt != null) {
      const d = now - this.lastKeyAt;
      interval = d;
      this.activeTime += Math.min(d, IDLE_CAP);
      this.analytics.active(Math.min(d, IDLE_CAP));
    }
    this.lastKeyAt = now;

    const expected = this.nextKey;
    const unit = this.index < this.units.length ? this.units[this.index].display : null;
    if (this.accept(ch)) {
      this.correct += 1;
      this.analytics.hit(ch, interval);
      if (this.index >= this.units.length) this.finishLine(ch);
      else this.onEvent("hit", ch);
    } else {
      this.misses += 1;
      this.lineMisses += 1;
      this.analytics.miss(expected, ch, unit);
      if (expected) this.weakKeys[expected] = (this.weakKeys[expected] || 0) + 1;
      this.missFlash = true;
      this.onEvent("miss", ch);
      setTimeout(() => { this.missFlash = false; this.onChange(); }, 180);
    }
    this.onChange();
  }

  accept(c) {
    if (this.index >= this.units.length) return false;
    const u = this.units[this.index];
    const nb = this.buffer + c;
    const cands = u.options.filter((o) => o.startsWith(nb));
    if (cands.length) {
      this.buffer = nb;
      if (cands.includes(nb) && !cands.some((o) => o.length > nb.length)) this.commit(nb);
      return true;
    }
    // 例:「ん」を n 1つで確定させて次の単位へ
    if (this.buffer && u.options.includes(this.buffer)) {
      this.commit(this.buffer);
      return this.accept(c);
    }
    return false;
  }

  commit(s) {
    if (this.index < this.units.length) this.analytics.unitDone(this.units[this.index].display);
    this.typed.push(s);
    this.buffer = "";
    this.index += 1;
  }

  finishLine(last) {
    this.lines += 1;
    const keys = this.correct - this.lineStartCorrect;
    const t = this.activeTime - this.lineStartTime;
    if (t > 0.5) {
      const k = Math.floor((keys / t) * 60);
      this.lastLineKPM = k;
      this.analytics.line({
        id: crypto.randomUUID(), date: new Date().toISOString(), kpm: k,
        accuracy: (keys / Math.max(1, keys + this.lineMisses)) * 100,
        keys, misses: this.lineMisses, mode: this.mode, text: this.sentence.display.slice(0, 60),
      });
      // 短すぎる行・ミスが多い行はベスト記録の対象外
      if (keys >= 15 && this.lineMisses <= Math.floor(keys / 10) && k > this.bestKPM) {
        this.bestKPM = k;
        store.set("bestKPM", k);
      }
    }
    this.doneFlash = true;
    this.onEvent("lineDone", last);
    setTimeout(() => { this.doneFlash = false; this.advanceNovel(); this.nextSentence(); this.onChange(); }, 200);
  }

  restartLine() {
    this.index = 0;
    this.buffer = "";
    this.typed = [];
    this.lineStartCorrect = this.correct;
    this.lineStartTime = this.activeTime;
    this.lineMisses = 0;
  }

  skip() { this.advanceNovel(); this.nextSentence(); this.onChange(); }

  resetSession(notify = true) {
    this.correct = 0; this.misses = 0; this.lines = 0; this.activeTime = 0;
    this.lastKeyAt = null; this.weakKeys = {}; this.lastLineKPM = null;
    this.restartLine();
    if (notify) this.onChange();
  }

  resetRecords() {
    this.bestKPM = 0;
    store.set("bestKPM", 0);
    this.analytics.reset();
    this.onChange();
  }

  setMode(mode) {
    if (mode === "custom" && !this.custom.length) return false;
    if (this.mode === mode) return true;
    this.mode = mode;
    store.set("mode", mode);
    this.resetSession(false);
    this.nextSentence();
    this.onChange();
    return true;
  }

  // ---- 小説 ----
  get novel() { return NOVELS.find((n) => n.id === store.get("novelId")) || NOVELS[0]; }
  get novelLines() { return NOVEL_LINES[this.novel.id]; }
  /** 今の行（0始まり）。範囲外なら最初に戻す */
  get novelPos() {
    const p = (store.get("novelPos") || {})[this.novel.id] || 0;
    return p < this.novelLines.length ? p : 0;
  }
  setNovelPos(p) { store.set("novelPos", { ...(store.get("novelPos") || {}), [this.novel.id]: p }); }

  /** 小説モードなら1行進める。最後まで読んだら最初に戻る */
  advanceNovel() {
    if (this.mode !== "novel") return;
    const next = this.novelPos + 1;
    if (next >= this.novelLines.length) { this.setNovelPos(0); this.onEvent("novelDone"); }
    else this.setNovelPos(next);
  }

  /** 作品の変更・位置の変更（設定ウィンドウから）を反映 */
  novelChanged() {
    if (this.mode !== "novel") return;
    this.nextSentence();
    this.onChange();
  }

  // ---- 出題 ----
  get kind() { return store.get("contentKind") || "mix"; }
  get poolKey() { return `${this.mode}-${this.kind}-${this.custom.length}`; }
  get pool() {
    if (this.mode === "japanese") return JP;
    if (this.mode === "english") return EN;
    return this.custom.length ? this.custom : EN;
  }

  randomSentence(ex) {
    if (this.mode !== "custom") {
      const useWords = this.kind === "words" || (this.kind === "mix" && Math.random() < 0.35);
      if (useWords) return wordLine(this.mode === "japanese");
    }
    const p = this.pool;
    if (p.length <= 1) return p[0] || { display: "", reading: "" };
    let s;
    do { s = p[Math.floor(Math.random() * p.length)]; } while (same(s, ex));
    return s;
  }

  nextSentence() {
    if (this.mode === "novel") {
      const L = this.novelLines, p = this.novelPos;
      this.sentence = L[p];
      this.upcoming = L[(p + 1) % L.length];
      this.upcomingKey = "";
      this.units = toUnits(this.sentence.reading);
      this.restartLine();
      return;
    }
    if (this.upcomingKey !== this.poolKey || !this.upcoming) this.upcoming = this.randomSentence(null);
    this.sentence = this.upcoming;
    this.upcoming = this.randomSentence(this.sentence);
    this.upcomingKey = this.poolKey;
    this.units = toUnits(this.sentence.reading);
    this.restartLine();
  }

  contentKindChanged() { this.upcomingKey = ""; this.nextSentence(); this.onChange(); }

  /** 改行区切りのテキストをカスタム問題として読み込む。読み込めた行数を返す */
  loadCustom(text) {
    const raw = text.split(/\r?\n/);
    const ss = raw.map(parseSentence).filter(Boolean);
    if (!ss.length) return 0;
    this.custom = ss;
    store.set("customLines", raw.filter((l) => parseSentence(l)));
    if (this.mode === "custom") { this.resetSession(false); this.upcomingKey = ""; this.nextSentence(); this.onChange(); }
    else this.setMode("custom");
    return ss.length;
  }
}
