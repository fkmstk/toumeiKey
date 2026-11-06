// ローマ字入力エンジン: かな文 → 入力単位（表示とその打ち方の候補）に分解する

const SINGLE = {
  "あ": ["a"], "い": ["i", "yi"], "う": ["u", "wu", "whu"], "え": ["e"], "お": ["o"],
  "か": ["ka", "ca"], "き": ["ki"], "く": ["ku", "cu", "qu"], "け": ["ke"], "こ": ["ko", "co"],
  "さ": ["sa"], "し": ["shi", "si", "ci"], "す": ["su"], "せ": ["se", "ce"], "そ": ["so"],
  "た": ["ta"], "ち": ["chi", "ti"], "つ": ["tsu", "tu"], "て": ["te"], "と": ["to"],
  "な": ["na"], "に": ["ni"], "ぬ": ["nu"], "ね": ["ne"], "の": ["no"],
  "は": ["ha"], "ひ": ["hi"], "ふ": ["fu", "hu"], "へ": ["he"], "ほ": ["ho"],
  "ま": ["ma"], "み": ["mi"], "む": ["mu"], "め": ["me"], "も": ["mo"],
  "や": ["ya"], "ゆ": ["yu"], "よ": ["yo"],
  "ら": ["ra"], "り": ["ri"], "る": ["ru"], "れ": ["re"], "ろ": ["ro"],
  "わ": ["wa"], "を": ["wo"], "ん": ["nn"],
  "が": ["ga"], "ぎ": ["gi"], "ぐ": ["gu"], "げ": ["ge"], "ご": ["go"],
  "ざ": ["za"], "じ": ["ji", "zi"], "ず": ["zu"], "ぜ": ["ze"], "ぞ": ["zo"],
  "だ": ["da"], "ぢ": ["di"], "づ": ["du"], "で": ["de"], "ど": ["do"],
  "ば": ["ba"], "び": ["bi"], "ぶ": ["bu"], "べ": ["be"], "ぼ": ["bo"],
  "ぱ": ["pa"], "ぴ": ["pi"], "ぷ": ["pu"], "ぺ": ["pe"], "ぽ": ["po"],
  "ゔ": ["vu"],
  "ぁ": ["xa", "la"], "ぃ": ["xi", "li"], "ぅ": ["xu", "lu"], "ぇ": ["xe", "le"], "ぉ": ["xo", "lo"],
  "ゃ": ["xya", "lya"], "ゅ": ["xyu", "lyu"], "ょ": ["xyo", "lyo"],
  "っ": ["xtu", "ltu", "xtsu", "ltsu"], "ゎ": ["xwa", "lwa"],
  "ー": ["-"], "、": [","], "。": ["."], "！": ["!"], "？": ["?"],
  "「": ["["], "」": ["]"], "・": ["/"], "　": [" "], "〜": ["~"],
};

const COMBO = {
  "きゃ": ["kya"], "きゅ": ["kyu"], "きょ": ["kyo"], "きぇ": ["kye"],
  "しゃ": ["sha", "sya"], "しゅ": ["shu", "syu"], "しょ": ["sho", "syo"], "しぇ": ["she", "sye"],
  "ちゃ": ["cha", "tya", "cya"], "ちゅ": ["chu", "tyu", "cyu"], "ちょ": ["cho", "tyo", "cyo"], "ちぇ": ["che", "tye", "cye"],
  "にゃ": ["nya"], "にゅ": ["nyu"], "にょ": ["nyo"],
  "ひゃ": ["hya"], "ひゅ": ["hyu"], "ひょ": ["hyo"],
  "みゃ": ["mya"], "みゅ": ["myu"], "みょ": ["myo"],
  "りゃ": ["rya"], "りゅ": ["ryu"], "りょ": ["ryo"],
  "ぎゃ": ["gya"], "ぎゅ": ["gyu"], "ぎょ": ["gyo"],
  "じゃ": ["ja", "zya", "jya"], "じゅ": ["ju", "zyu", "jyu"], "じょ": ["jo", "zyo", "jyo"], "じぇ": ["je", "zye", "jye"],
  "ぢゃ": ["dya"], "ぢゅ": ["dyu"], "ぢょ": ["dyo"],
  "びゃ": ["bya"], "びゅ": ["byu"], "びょ": ["byo"],
  "ぴゃ": ["pya"], "ぴゅ": ["pyu"], "ぴょ": ["pyo"],
  "ふぁ": ["fa"], "ふぃ": ["fi"], "ふぇ": ["fe"], "ふぉ": ["fo"],
  "てぃ": ["thi"], "でぃ": ["dhi"], "とぅ": ["twu"], "どぅ": ["dwu"],
  "うぃ": ["wi"], "うぇ": ["we"], "うぉ": ["who"],
  "ゔぁ": ["va"], "ゔぃ": ["vi"], "ゔぇ": ["ve"], "ゔぉ": ["vo"],
};

/** カタカナ → ひらがな、全角英数 → 半角 */
export function toHiragana(c) {
  const v = c.codePointAt(0);
  if (v >= 0x30a1 && v <= 0x30f6) return String.fromCodePoint(v - 0x60);
  if (v === 0x30f4) return "ゔ";
  if (v >= 0xff01 && v <= 0xff5e) {
    const a = String.fromCodePoint(v - 0xfee0);
    if (!(c in SINGLE)) return a;
  }
  return c;
}

const isConsonant = (c) => /^[a-z]$/.test(c) && !"aiueon".includes(c);
const isPrintableAscii = (c) => c.length === 1 && c.charCodeAt(0) >= 32 && c.charCodeAt(0) < 127;

/** 読み（かな + ASCII）を入力単位に分解する。入力できない文字（漢字など）は捨てる。 */
export function units(text) {
  const orig = Array.from(text);
  const hira = orig.map(toHiragana);
  const raw = [];
  for (let i = 0; i < hira.length; ) {
    if (i + 1 < hira.length) {
      const key = hira[i] + hira[i + 1];
      if (COMBO[key]) {
        const opts = [...COMBO[key]];
        // 分解打ち（例: ki + xya）も許可
        for (const a of SINGLE[hira[i]] || []) for (const b of SINGLE[hira[i + 1]] || []) opts.push(a + b);
        raw.push({ display: orig[i] + orig[i + 1], options: opts });
        i += 2;
        continue;
      }
    }
    const s = hira[i];
    if (SINGLE[s]) raw.push({ display: orig[i], options: [...SINGLE[s]] });
    else if (isPrintableAscii(s)) raw.push({ display: s, options: [s] });
    i += 1;
  }

  // 促音「っ」と撥音「ん」
  const out = [];
  for (let j = 0; j < raw.length; ) {
    const u = raw[j];
    const h = Array.from(u.display).map(toHiragana).join("");
    if (h === "っ" && j + 1 < raw.length) {
      const n = raw[j + 1];
      const opts = [];
      for (const o of n.options) if (isConsonant(o[0])) opts.push(o[0] + o);
      if (opts.length) {
        for (const x of SINGLE["っ"]) for (const o of n.options) opts.push(x + o);
        out.push({ display: u.display + n.display, options: opts });
        j += 2;
        continue;
      }
    }
    if (h === "ん") {
      const opts = ["nn", "xn", "n'"];
      if (j + 1 < raw.length) {
        const ok = raw[j + 1].options.every((o) => o.length > 0 && !"aiueoyn'".includes(o[0]));
        if (ok) opts.push("n");
      }
      out.push({ display: u.display, options: opts });
      j += 1;
      continue;
    }
    out.push(u);
    j += 1;
  }
  return out;
}

/** カスタム文の1行をパース。「表示|よみ」形式なら漢字交じりの文も練習できる */
export function parseSentence(line) {
  const t = line.trim();
  if (!t) return null;
  const bar = t.indexOf("|");
  let s;
  if (bar >= 0 && t.slice(bar + 1).trim()) s = { display: t.slice(0, bar).trim(), reading: t.slice(bar + 1).trim() };
  else s = { display: t, reading: t };
  return units(s.reading).length ? s : null;
}
