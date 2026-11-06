// 練習の記録（キー別・かな別・打ち間違い・日別・行ごと）。localStorage に保存し、全ウィンドウで共有する。

import { emit, listen } from "./store.js";

const KEY = "analytics.v1";
const MAX_LINES = 3000;
const IDLE_CAP = 2.0;

const emptyStat = () => ({ hits: 0, misses: 0, totalSec: 0, timed: 0 });
const emptyDay = () => ({ keys: 0, misses: 0, activeSec: 0, lines: 0, bestKPM: 0 });
const emptyData = () => ({ keys: {}, units: {}, confusions: {}, days: {}, lines: [] });

export const stat = {
  attempts: (s) => s.hits + s.misses,
  missRate: (s) => (s.hits + s.misses === 0 ? 0 : s.misses / (s.hits + s.misses)),
  avgMs: (s) => (s.timed === 0 ? null : (s.totalSec / s.timed) * 1000),
  add: (a, b) => ({ hits: a.hits + b.hits, misses: a.misses + b.misses, totalSec: a.totalSec + b.totalSec, timed: a.timed + b.timed }),
};
export const day = {
  kpm: (d) => (d.activeSec > 1 ? Math.floor((d.keys / d.activeSec) * 60) : 0),
  accuracy: (d) => (d.keys + d.misses === 0 ? 0 : (d.keys / (d.keys + d.misses)) * 100),
};

export function dayKey(date = new Date()) {
  const y = date.getFullYear(), m = String(date.getMonth() + 1).padStart(2, "0"), d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

const isKanaUnit = (u) => /[぀-ヿ]/.test(u);

export class Analytics {
  constructor() {
    this.data = this.load();
    this.saveTimer = null;
    this.listeners = new Set();
    const reload = () => { this.data = this.load(); this.emit(); };
    window.addEventListener("storage", (e) => { if (e.key === KEY) reload(); });
    listen("analytics-saved", () => setTimeout(reload, 50));
  }

  load() {
    try { return { ...emptyData(), ...JSON.parse(localStorage.getItem(KEY) || "{}") }; } catch { return emptyData(); }
  }
  onChange(f) { this.listeners.add(f); }
  emit() { for (const f of this.listeners) f(); }

  get todayKey() { return dayKey(); }
  todayDay() { return (this.data.days[this.todayKey] ||= emptyDay()); }

  hit(key, interval) {
    if (!key) return;
    const k = key.toLowerCase();
    const s = (this.data.keys[k] ||= emptyStat());
    s.hits += 1;
    if (interval != null && interval < IDLE_CAP) { s.totalSec += interval; s.timed += 1; }
    this.todayDay().keys += 1;
    this.scheduleSave();
  }

  miss(expected, typed, unit) {
    if (expected) {
      const k = expected.toLowerCase();
      (this.data.keys[k] ||= emptyStat()).misses += 1;
      if (typed) {
        const c = `${k}→${typed.toLowerCase()}`;
        this.data.confusions[c] = (this.data.confusions[c] || 0) + 1;
      }
    }
    if (unit && isKanaUnit(unit)) (this.data.units[unit] ||= emptyStat()).misses += 1;
    this.todayDay().misses += 1;
    this.scheduleSave();
  }

  unitDone(u) {
    if (isKanaUnit(u)) (this.data.units[u] ||= emptyStat()).hits += 1;
  }

  active(sec) { this.todayDay().activeSec += sec; }

  line(rec) {
    this.data.lines.push(rec);
    if (this.data.lines.length > MAX_LINES) this.data.lines.splice(0, this.data.lines.length - MAX_LINES);
    const d = this.todayDay();
    d.lines += 1;
    d.bestKPM = Math.max(d.bestKPM, rec.kpm);
    this.scheduleSave();
  }

  reset() {
    this.data = emptyData();
    this.saveNow();
  }

  scheduleSave() {
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveNow(), 1500);
  }
  saveNow() {
    clearTimeout(this.saveTimer);
    localStorage.setItem(KEY, JSON.stringify(this.data));
    this.emit();
    emit("analytics-saved", {});
  }

  // ---- 集計 ----

  get today() { return this.data.days[this.todayKey] || emptyDay(); }

  get streak() {
    const d = new Date();
    if (!((this.data.days[dayKey(d)] || {}).keys > 0)) d.setDate(d.getDate() - 1);
    let n = 0;
    while ((this.data.days[dayKey(d)] || {}).keys > 0) { n += 1; d.setDate(d.getDate() - 1); }
    return n;
  }

  /** 直近 n 日（今日を含む、練習しなかった日は 0）。n=null なら記録の最初の日から */
  dayRange(n) {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    let count = n ?? 7;
    if (n == null) {
      const first = Object.keys(this.data.days).sort()[0];
      if (first) {
        const [y, m, d] = first.split("-").map(Number);
        count = Math.max(7, Math.round((today - new Date(y, m - 1, d)) / 86400000) + 1);
      }
    }
    const out = [];
    for (let i = count - 1; i >= 0; i--) {
      const d = new Date(today); d.setDate(d.getDate() - i);
      out.push({ date: d, stat: this.data.days[dayKey(d)] || emptyDay() });
    }
    return out;
  }

  linesSince(date) { return date ? this.data.lines.filter((l) => new Date(l.date) >= date) : this.data.lines; }

  linesCSV() {
    let out = "date,mode,kpm,accuracy,keys,misses,text\n";
    for (const l of this.data.lines) {
      out += `${l.date},${l.mode},${l.kpm},${l.accuracy.toFixed(1)},${l.keys},${l.misses},"${String(l.text).replaceAll('"', '""')}"\n`;
    }
    return out;
  }

  keysCSV() {
    let out = "key,hits,misses,miss_rate,avg_ms\n";
    for (const k of Object.keys(this.data.keys).sort()) {
      const s = this.data.keys[k];
      const key = /[",]/.test(k) ? `"${k.replaceAll('"', '""')}"` : k;
      const ms = stat.avgMs(s);
      out += `${key},${s.hits},${s.misses},${stat.missRate(s).toFixed(4)},${ms == null ? "" : ms.toFixed(0)}\n`;
    }
    return out;
  }
}

export function formatDuration(sec) {
  const m = Math.floor(sec / 60);
  return m >= 60 ? `${Math.floor(m / 60)}時間${m % 60}分` : `${m}分`;
}
