// 統計・分析ウィンドウ。グラフは SVG で描画（外部ライブラリなし）。
// 配色はダーク面 #17171b 用の参照パレット。単一系列のグラフは指標ごとに1色、ヒートマップは青の単色ランプ。
import * as store from "./store.js";
import { Analytics, stat, day, formatDuration } from "./analytics.js";
import { rows, lookup, FINGER_NAMES, FINGER_COLORS } from "./keyboard.js";

const T = window.__TAURI__;
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const a = new Analytics();

const C = { kpm: "#3987e5", time: "#9085e9", acc: "#199e70", grid: "#2a2a2f", baseline: "#38383e", muted: "#8b8b90" };
const RAMP = ["#184f95", "#1c5cab", "#256abf", "#2a78d6", "#3987e5", "#5598e7", "#6da7ec", "#86b6ef", "#9ec5f4", "#b7d3f6", "#cde2fb"];
const rampColor = (t) => RAMP[Math.round(Math.max(0, Math.min(1, t)) * (RAMP.length - 1))];
const rampInk = (t) => (t > 0.55 ? "#0b0b0b" : "#ffffff");
const MODE_LABEL = { japanese: "日本語", english: "English", novel: "小説", custom: "カスタム" };

let range = "week";   // week | month | all
let heat = "miss";    // miss | speed
const RANGES = { week: ["7日", 7], month: ["30日", 30], all: ["全期間", null] };

// ---------- ツールチップ ----------
const tip = $("tip");
function showTip(e, lines) {
  tip.innerHTML = lines.map((l) => `<div>${esc(l)}</div>`).join("");
  tip.style.display = "block";
  const r = tip.getBoundingClientRect();
  let x = e.clientX + 14, y = e.clientY - r.height - 10;
  if (x + r.width > innerWidth - 8) x = e.clientX - r.width - 14;
  if (y < 8) y = e.clientY + 16;
  tip.style.left = `${x}px`; tip.style.top = `${y}px`;
}
const hideTip = () => { tip.style.display = "none"; };

// ---------- 軸 ----------
function niceTicks(lo, hi, n = 4) {
  const span = hi - lo || 1;
  const raw = span / n, mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw) || raw;
  const out = [];
  for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(+v.toFixed(6));
  return out;
}
const md = (d) => `${d.getMonth() + 1}/${d.getDate()}`;
const wd = (d) => `${md(d)}（${"日月火水木金土"[d.getDay()]}）`;

/**
 * 共通の折れ線/棒グラフ。xs は 0..n-1 の位置、ys は値（null は欠測）。
 * mode: "line" | "bar" | "trend"（trend は faint 点 + 平均線）
 */
function chart(el, { n, ys, ys2, color, height, yLo, yHi, xLabel, tooltip, mode, yFmt = (v) => v }) {
  const W = Math.max(200, el.clientWidth), H = height;
  const m = { l: 6, r: 38, t: 10, b: 22 };
  const iw = W - m.l - m.r, ih = H - m.t - m.b;
  const band = mode === "bar" ? iw / n : 0;
  const X = (i) => (mode === "bar" ? m.l + band * (i + 0.5) : m.l + (n <= 1 ? iw / 2 : (iw * i) / (n - 1)));
  const Y = (v) => m.t + ih - ((v - yLo) / (yHi - yLo || 1)) * ih;
  let s = `<svg width="${W}" height="${H}">`;
  for (const t of niceTicks(yLo, yHi)) {
    s += `<line x1="${m.l}" x2="${m.l + iw}" y1="${Y(t)}" y2="${Y(t)}" stroke="${C.grid}"/>`;
    s += `<text x="${m.l + iw + 6}" y="${Y(t) + 3}">${yFmt(t)}</text>`;
  }
  s += `<line x1="${m.l}" x2="${m.l + iw}" y1="${m.t + ih}" y2="${m.t + ih}" stroke="${C.baseline}"/>`;
  const step = Math.max(1, Math.ceil(n / Math.max(2, Math.floor(iw / 70))));
  for (let i = 0; i < n; i += step) s += `<text x="${X(i)}" y="${H - 6}" text-anchor="middle">${esc(xLabel(i))}</text>`;

  if (mode === "bar") {
    const bw = Math.max(2, Math.min(36, band - 4));
    ys.forEach((v, i) => {
      if (!v) return;
      const y = Y(v), h = m.t + ih - y, r = Math.min(4, bw / 2, h);
      // 上だけ角丸、下はベースラインに接地
      s += `<path class="mk" data-i="${i}" fill="${color}" d="M${X(i) - bw / 2},${m.t + ih} V${y + r} Q${X(i) - bw / 2},${y} ${X(i) - bw / 2 + r},${y} H${X(i) + bw / 2 - r} Q${X(i) + bw / 2},${y} ${X(i) + bw / 2},${y + r} V${m.t + ih} Z"/>`;
    });
  } else {
    if (mode === "trend") ys.forEach((v, i) => { if (v != null) s += `<circle cx="${X(i)}" cy="${Y(v)}" r="2.2" fill="${color}" opacity="0.35"/>`; });
    const line = mode === "trend" ? ys2 : ys;
    let d = "", pen = false;
    line.forEach((v, i) => { if (v == null) return; d += `${pen ? "L" : "M"}${X(i).toFixed(1)},${Y(v).toFixed(1)} `; pen = true; });
    s += `<path d="${d}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;
    if (mode === "line") ys.forEach((v, i) => { if (v != null) s += `<circle cx="${X(i)}" cy="${Y(v)}" r="4" fill="${color}" stroke="#17171b" stroke-width="2"/>`; });
  }
  s += `<line id="rule" x1="0" x2="0" y1="${m.t}" y2="${m.t + ih}" stroke="${C.baseline}" visibility="hidden"/>`;
  s += `<circle id="hl" r="5" fill="${color}" stroke="#17171b" stroke-width="2" visibility="hidden"/>`;
  s += `<rect x="${m.l}" y="${m.t}" width="${iw}" height="${ih}" fill="transparent" id="hit"/></svg>`;
  el.innerHTML = s;

  // ホバー: 一番近い x の値を表示
  const svg = el.querySelector("svg"), rule = svg.querySelector("#rule"), hl = svg.querySelector("#hl");
  svg.querySelector("#hit").addEventListener("mousemove", (e) => {
    const px = e.clientX - svg.getBoundingClientRect().left;
    let best = -1, bd = Infinity;
    for (let i = 0; i < n; i++) {
      const v = mode === "trend" ? ys2[i] : ys[i];
      if (v == null || (mode === "bar" && !v && !tooltip(i, true))) continue;
      const d = Math.abs(X(i) - px);
      if (d < bd) { bd = d; best = i; }
    }
    if (best < 0) { hideTip(); return; }
    rule.setAttribute("x1", X(best)); rule.setAttribute("x2", X(best)); rule.setAttribute("visibility", "visible");
    const hv = mode === "trend" ? ys[best] : ys[best];
    if (mode !== "bar" && hv != null) { hl.setAttribute("cx", X(best)); hl.setAttribute("cy", Y(hv)); hl.setAttribute("visibility", "visible"); }
    svg.querySelectorAll(".mk").forEach((p) => p.setAttribute("opacity", +p.dataset.i === best ? 1 : 0.45));
    showTip(e, tooltip(best));
  });
  svg.querySelector("#hit").addEventListener("mouseleave", () => {
    hideTip(); rule.setAttribute("visibility", "hidden"); hl.setAttribute("visibility", "hidden");
    svg.querySelectorAll(".mk").forEach((p) => p.setAttribute("opacity", 1));
  });
}

function padDomain(vals, minPad, clampHi) {
  const lo = Math.min(...vals), hi = Math.max(...vals);
  const pad = Math.max(minPad, (hi - lo) * 0.12);
  return [Math.max(0, lo - pad), clampHi != null ? Math.min(clampHi, hi + pad) : hi + pad];
}

// ---------- 部品 ----------
const card = (title, sub, body, extra = "") => `<div class="card"><div class="head"><div><h2>${title}</h2><div class="sub">${sub}</div></div>${extra}</div>${body}</div>`;

function rankCard(title, sub, rws) {
  const body = rws.length
    ? `<div class="rank">${rws.map((r) => `<div class="l">${r.swatch ? `<span class="sw" style="background:${r.swatch}"></span>` : ""}${esc(r.label)}</div>` +
      `<div class="b"><div style="width:${(r.fraction * 100).toFixed(1)}%"></div></div><div class="v">${esc(r.value)}</div><div class="x">${esc(r.detail || "")}</div>`).join("")}</div>`
    : `<div class="empty">データがまだ足りません</div>`;
  return card(title, sub, body);
}

function tile(title, value, note, delta) {
  const d = delta ? `<span class="${delta[1] ? "up" : "down"}">${delta[1] ? "↗" : "↘"}</span> <span class="d">${esc(delta[0])}</span> ` : "";
  return `<div class="card tile"><div class="t">${title}</div><div class="v">${esc(value)}</div><div class="n">${d}${esc(note)}</div></div>`;
}

const keyLabel = (k) => (k === " " ? "␣ space" : k.toUpperCase());

// ---------- 画面 ----------
function render() {
  $("range").innerHTML = Object.entries(RANGES).map(([k, [l]]) => `<button data-r="${k}" class="${range === k ? "on" : ""}">${l}</button>`).join("");
  const data = a.data;
  if (!Object.keys(data.keys).length && !data.lines.length) {
    $("content").innerHTML = `<div class="card emptyState"><b>まだ記録がありません</b>帯で何行か打つと、ここに速さ・正確さ・苦手なキーが表示されます。</div>`;
    return;
  }
  const n = RANGES[range][1];
  const days = a.dayRange(n);
  const since = n ? days[0].date : null;
  const lines = a.linesSince(since);

  // サマリー
  const sum = (ds) => ds.reduce((o, d) => ({ keys: o.keys + d.keys, misses: o.misses + d.misses, sec: o.sec + d.activeSec }), { keys: 0, misses: 0, sec: 0 });
  const cur = sum(days.map((d) => d.stat));
  const kpm = cur.sec > 1 ? Math.floor((cur.keys / cur.sec) * 60) : 0;
  const acc = cur.keys + cur.misses ? (cur.keys / (cur.keys + cur.misses)) * 100 : 0;
  let dK, dA, dT;
  if (n) {
    const prev = sum(a.dayRange(n * 2).slice(0, n).map((d) => d.stat));
    if (prev.sec > 1 && cur.sec > 1) { const v = kpm - Math.floor((prev.keys / prev.sec) * 60); dK = [`${v >= 0 ? "+" : ""}${v}`, v >= 0]; }
    if (prev.keys + prev.misses && cur.keys + cur.misses) { const v = acc - (prev.keys / (prev.keys + prev.misses)) * 100; dA = [`${v >= 0 ? "+" : ""}${v.toFixed(1)} pt`, v >= 0]; }
    if (prev.sec > 0) { const v = (cur.sec - prev.sec) / 60; dT = [`${v >= 0 ? "+" : ""}${v.toFixed(0)} 分`, v >= 0]; }
  }
  const cmp = n ? `前の${n}日比` : "";
  const best = lines.reduce((m, l) => Math.max(m, l.kpm), 0);
  let html = `<div class="tiles">` +
    tile("平均 KPM", String(kpm), cmp, dK) + tile("正確率", `${acc.toFixed(1)}%`, cmp, dA) +
    tile("練習時間", formatDuration(cur.sec), cmp, dT) + tile("打鍵数", cur.keys.toLocaleString(), `${lines.length} 行`) +
    tile("ベスト KPM", String(best), "この期間の1行") + tile("連続練習", `${a.streak} 日`, `今日 ${formatDuration(a.today.activeSec)}`) + `</div>`;

  // KPM の推移
  const pts = []; const win = [];
  lines.forEach((l) => { win.push(l.kpm); if (win.length > 10) win.shift(); pts.push({ kpm: l.kpm, avg: win.reduce((x, y) => x + y, 0) / win.length, rec: l }); });
  const hero = pts.length ? `<div class="hero"><b>${Math.round(pts[pts.length - 1].avg)}</b><span>直近10行の平均 KPM</span></div>` : "";
  html += card("KPM の推移", "点 = 各行の KPM、線 = 直近10行の平均", pts.length >= 2 ? `<div class="chart" id="c-trend"></div>` : `<div class="empty">2行以上打つとグラフが表示されます</div>`, hero);

  html += `<div class="grid2">` +
    card("日別の練習時間", "打鍵していた時間（分）", `<div class="chart" id="c-time"></div>`) +
    card("日別の平均 KPM", "その日の打鍵数 ÷ 打鍵していた時間", `<div class="chart" id="c-dkpm"></div>`) + `</div>`;

  // 指ごと
  const layout = store.get("keyLayout");
  const agg = Array.from({ length: 9 }, () => ({ hits: 0, misses: 0, totalSec: 0, timed: 0 }));
  for (const [k, s] of Object.entries(data.keys)) {
    const f = (lookup(layout, k) || lookup(layout, k.toUpperCase()))?.key.finger;
    if (f != null) agg[f] = stat.add(agg[f], s);
  }
  const maxF = Math.max(0.0001, ...agg.map(stat.missRate));
  const fingerRows = agg.map((s, i) => ({
    label: FINGER_NAMES[i], swatch: FINGER_COLORS[i], fraction: stat.missRate(s) / maxF,
    value: stat.attempts(s) ? `${(stat.missRate(s) * 100).toFixed(1)}%` : "–",
    detail: stat.avgMs(s) != null ? `${stat.avgMs(s).toFixed(0)} ms` : "",
  }));
  html += `<div class="grid2">` + card("日別の正確率", "正しく打った数 ÷ 全打鍵", `<div class="chart" id="c-dacc"></div>`) +
    rankCard("指ごとのミス率", "右の数字は平均打鍵間隔（全期間）", fingerRows) + `</div>`;

  html += heatmap(layout);

  // ランキング
  const ks = Object.entries(data.keys);
  const weak = ks.filter(([, s]) => stat.attempts(s) >= 20).sort((x, y) => stat.missRate(y[1]) - stat.missRate(x[1])).slice(0, 8);
  const wm = Math.max(0.0001, weak[0] ? stat.missRate(weak[0][1]) : 0);
  const slow = ks.filter(([, s]) => s.timed >= 20).map(([k, s]) => [k, stat.avgMs(s)]).sort((x, y) => y[1] - x[1]).slice(0, 8);
  const sm = Math.max(1, slow[0]?.[1] || 1);
  const conf = Object.entries(data.confusions).sort((x, y) => y[1] - x[1]).slice(0, 8);
  const cm = Math.max(1, conf[0]?.[1] || 1);
  const kana = Object.entries(data.units).filter(([, s]) => stat.attempts(s) >= 5).sort((x, y) => stat.missRate(y[1]) - stat.missRate(x[1])).slice(0, 8);
  const km = Math.max(0.0001, kana[0] ? stat.missRate(kana[0][1]) : 0);
  html += `<div class="grid2">` +
    rankCard("苦手なキー", "ミス率が高い順（20回以上打ったキー・全期間）", weak.map(([k, s]) => ({ label: keyLabel(k), value: `${(stat.missRate(s) * 100).toFixed(1)}%`, fraction: stat.missRate(s) / wm, detail: `${s.misses}/${stat.attempts(s)}` }))) +
    rankCard("時間がかかるキー", "直前のキーからの平均間隔（全期間）", slow.map(([k, v]) => ({ label: keyLabel(k), value: `${v.toFixed(0)} ms`, fraction: v / sm }))) + `</div>`;
  html += `<div class="grid2">` +
    rankCard("よくある打ち間違い", "打つべきキー → 実際に打ったキー（全期間）", conf.map(([k, v]) => { const [p, q] = k.split("→"); return { label: `${keyLabel(p)}  →  ${keyLabel(q)}`, value: `${v} 回`, fraction: v / cm }; })) +
    rankCard("苦手なかな", "ミス率が高い順（5回以上・全期間）", kana.map(([k, s]) => ({ label: k, value: `${(stat.missRate(s) * 100).toFixed(1)}%`, fraction: stat.missRate(s) / km, detail: `${s.misses}/${stat.attempts(s)}` }))) + `</div>`;

  // 最近の行
  const recent = lines.slice(-40).reverse();
  const fmt = (iso) => { const d = new Date(iso); return `${md(d)} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`; };
  html += card("最近の行", "新しい順に最大40行", recent.length
    ? `<div class="scroll"><table><tr><th>日時</th><th>モード</th><th>KPM</th><th>正確率</th><th>ミス</th><th>文</th></tr>${recent.map((l) =>
      `<tr><td>${fmt(l.date)}</td><td>${MODE_LABEL[l.mode] || esc(l.mode)}</td><td>${l.kpm}</td><td>${l.accuracy.toFixed(1)}%</td><td>${l.misses}</td><td class="txt">${esc(l.text)}</td></tr>`).join("")}</table></div>`
    : `<div class="empty">この期間の記録はありません</div>`);

  $("content").innerHTML = html;
  drawCharts(pts, days);
}

function drawCharts(pts, days) {
  if ($("c-trend")) {
    const vals = pts.map((p) => p.kpm);
    const [lo, hi] = padDomain(vals, 10);
    chart($("c-trend"), {
      n: pts.length, ys: vals, ys2: pts.map((p) => p.avg), color: C.kpm, height: 220, yLo: lo, yHi: hi, mode: "trend",
      xLabel: (i) => String(i + 1),
      tooltip: (i) => { const p = pts[i], d = new Date(p.rec.date); return [`${i + 1} 行目  ${md(d)} ${d.getHours()}:${String(d.getMinutes()).padStart(2, "0")}`, `KPM ${p.rec.kpm}   平均 ${Math.round(p.avg)}`, `正確率 ${p.rec.accuracy.toFixed(1)}%`, p.rec.text]; },
    });
  }
  const mins = days.map((d) => d.stat.activeSec / 60);
  chart($("c-time"), {
    n: days.length, ys: mins, color: C.time, height: 180, yLo: 0, yHi: Math.max(1, ...mins) * 1.1, mode: "bar",
    xLabel: (i) => md(days[i].date), yFmt: (v) => +v.toFixed(1),
    tooltip: (i, probe) => probe ? true : [wd(days[i].date), `練習 ${formatDuration(days[i].stat.activeSec)}`, `打鍵 ${days[i].stat.keys}  /  ${days[i].stat.lines} 行`],
  });
  const dk = days.map((d) => (d.stat.keys > 0 ? day.kpm(d.stat) : null));
  const dkv = dk.filter((v) => v != null);
  if (dkv.length) {
    const [lo, hi] = padDomain(dkv, 5);
    chart($("c-dkpm"), { n: days.length, ys: dk, color: C.kpm, height: 180, yLo: lo, yHi: hi, mode: "line", xLabel: (i) => md(days[i].date),
      tooltip: (i) => [wd(days[i].date), `${dk[i]} KPM`, `打鍵 ${days[i].stat.keys}  ミス ${days[i].stat.misses}`] });
  } else $("c-dkpm").innerHTML = `<div class="empty">この期間の記録はありません</div>`;
  const da = days.map((d) => (d.stat.keys + d.stat.misses > 0 ? day.accuracy(d.stat) : null));
  const dav = da.filter((v) => v != null);
  if (dav.length) {
    const [lo, hi] = padDomain(dav, 1, 100);
    chart($("c-dacc"), { n: days.length, ys: da, color: C.acc, height: 180, yLo: lo, yHi: hi, mode: "line", xLabel: (i) => md(days[i].date),
      tooltip: (i) => [wd(days[i].date), `正確率 ${da[i].toFixed(1)}%`, `打鍵 ${days[i].stat.keys}  ミス ${days[i].stat.misses}`] });
  } else $("c-dacc").innerHTML = `<div class="empty">この期間の記録はありません</div>`;
}

function heatmap(layout) {
  const keyStat = (k) => {
    let s = a.data.keys[k.normal.toLowerCase()] || { hits: 0, misses: 0, totalSec: 0, timed: 0 };
    if (k.shifted.toLowerCase() !== k.normal.toLowerCase() && a.data.keys[k.shifted.toLowerCase()]) s = stat.add(s, a.data.keys[k.shifted.toLowerCase()]);
    return s;
  };
  const metric = (s) => (heat === "miss" ? (stat.attempts(s) >= 5 ? stat.missRate(s) * 100 : null) : s.timed >= 5 ? stat.avgMs(s) : null);
  const rs = rows(layout);
  const space = a.data.keys[" "] || { hits: 0, misses: 0, totalSec: 0, timed: 0 };
  const vals = [...rs.flat().map((k) => metric(keyStat(k))), metric(space)].filter((v) => v != null);
  const lo = vals.length ? Math.min(...vals) : 0, hi = vals.length ? Math.max(...vals) : 1;
  const norm = (v) => (hi - lo < 1e-4 ? 0.5 : (v - lo) / (hi - lo));
  const fmt = (v) => (heat === "miss" ? `${v.toFixed(0)}%` : v.toFixed(0));
  const cell = (label, s, w) => {
    const v = metric(s), t = v == null ? null : norm(v);
    const title = `${label === "space" ? "スペース" : label}  打鍵 ${s.hits} / ミス ${s.misses} (${(stat.missRate(s) * 100).toFixed(1)}%)` + (stat.avgMs(s) != null ? `  平均 ${stat.avgMs(s).toFixed(0)} ms` : "");
    return `<div class="k" title="${esc(title)}" style="width:${w}px;background:${t == null ? C.grid : rampColor(t)};color:${t == null ? C.muted : rampInk(t)}"><b>${esc(label)}</b><i>${v == null ? "–" : fmt(v)}</i></div>`;
  };
  const indent = [0, 0.5, 0.8, 1.3];
  let kb = `<div class="rows">`;
  rs.forEach((row, r) => { kb += `<div class="r"><div style="width:${40 * indent[r]}px"></div>${row.map((k) => cell(k.label, keyStat(k), 40)).join("")}</div>`; });
  kb += `<div class="r"><div style="width:${40 * 3.6}px"></div>${cell("space", space, 240)}</div></div>`;
  const legend = `<div class="legend">${heat === "miss" ? "ミス率" : "打鍵間隔 (ms)"}<div class="g" style="background:linear-gradient(90deg,${RAMP.join(",")})"></div>` +
    `<div class="mm"><span>${vals.length ? fmt(lo) : "–"}</span><span>${vals.length ? fmt(hi) : "–"}</span></div><div class="na"><span></span>データ不足</div></div>`;
  const sw = `<div class="seg" id="heatSeg"><button data-h="miss" class="${heat === "miss" ? "on" : ""}">ミス率</button><button data-h="speed" class="${heat === "speed" ? "on" : ""}">打鍵間隔</button></div>`;
  const sub = heat === "miss" ? "キーごとのミス率（5回以上打ったキー・全期間）。色が明るいほど苦手" : "直前の打鍵からの平均間隔 ms（全期間）。色が明るいほど時間がかかる";
  return card("キーボード ヒートマップ", sub, `<div class="heat">${kb}${legend}</div>`, sw);
}

// ---------- 操作 ----------
document.addEventListener("click", (e) => {
  const r = e.target.closest("[data-r]")?.dataset.r;
  if (r) { range = r; render(); }
  const h = e.target.closest("[data-h]")?.dataset.h;
  if (h) { heat = h; render(); }
});

$("csv").onclick = async () => {
  if (!T) { console.log(a.linesCSV()); return; }
  try {
    const paths = await T.core.invoke("export_csv", { lines: a.linesCSV(), keys: a.keysCSV() });
    if (!paths) return;
    await T.dialog.message(`書き出しました\n${paths.join("\n")}`, { title: "CSV 書き出し" });
  } catch (err) { await T.dialog.message(String(err), { title: "書き出せませんでした", kind: "error" }); }
};

$("reset").onclick = async () => {
  const ok = T ? await T.dialog.ask("キー別・日別・行ごとの記録とベスト KPM をすべて消去します。元に戻せません。", { title: "記録を消去", kind: "warning" }) : confirm("記録を消去しますか？");
  if (ok) store.send("resetRecords");
};

a.onChange(render);
store.subscribe((k) => { if (k === "keyLayout") render(); });
let rt;
window.addEventListener("resize", () => { clearTimeout(rt); rt = setTimeout(render, 120); });
window.addEventListener("focus", () => { a.data = a.load(); render(); });
render();
