// node tests/romaji.test.mjs で実行
import { units, parseSentence } from "../src/js/romaji.js";
import { VOCAB } from "../src/js/vocab.js";

function run(reading, input) {
  const us = units(reading); let idx = 0, buf = "";
  const accept = (c) => {
    if (idx >= us.length) return false;
    const u = us[idx], nb = buf + c, cands = u.options.filter((o) => o.startsWith(nb));
    if (cands.length) { buf = nb; if (cands.includes(nb) && !cands.some((o) => o.length > nb.length)) { buf = ""; idx++; } return true; }
    if (buf && u.options.includes(buf)) { buf = ""; idx++; return accept(c); }
    return false;
  };
  for (const c of input) if (!accept(c)) return false;
  return idx === us.length;
}
const guide = (r) => units(r).map((u) => u.options[0]).join("");

let fail = 0;
const cases = [
  ["きょうはいいてんきですね", "kyouhaiitenkidesune", true], ["きょうはいいてんきですね", "kixyouhaiitennkidesune", true],
  ["いっぱい", "ippai", true], ["いっぱい", "ixtupai", true], ["しゅうまつ", "syuumatu", true], ["しゅうまつ", "shuumatsu", true],
  ["こんやは", "konnyaha", true], ["こんやは", "konyaha", false], ["ちゃんねる", "channneru", true], ["ちゃんねる", "channeru", false],
  ["おんがく", "ongaku", true], ["ほん", "hon", false], ["ほん", "honn", true], ["かふぇ", "kafe", true],
  ["すっきり", "sukkiri", true], ["ちょっと", "chotto", true], ["ちょっと", "tyotto", true], ["Hello, World!", "Hello, World!", true],
  ["カタカナ", "katakana", true], ["ゔぁいおりん", "vaiorinn", true],
];
for (const [r, i, exp] of cases) if (run(r, i) !== exp) { fail++; console.log("FAIL", r, i); }

const all = [...VOCAB.japanese, ...VOCAB.jpWords, ...VOCAB.english.map((s) => [s, s]), ...VOCAB.enWords.map((s) => [s, s])];
for (const [, r] of all) {
  if (units(r).map((u) => u.display).join("") !== r) { fail++; console.log("DROP", r); }
  if (!run(r, guide(r))) { fail++; console.log("UNTYPEABLE", r); }
}
const p = parseSentence("今日は晴れ|きょうははれ");
if (!p || p.display !== "今日は晴れ" || p.reading !== "きょうははれ") { fail++; console.log("FAIL parse"); }
if (parseSentence("   ") !== null) { fail++; console.log("FAIL parse empty"); }
console.log(`cases ${cases.length} + vocab ${all.length}: ${fail === 0 ? "all OK" : fail + " failed"}`);
process.exit(fail ? 1 : 0);
