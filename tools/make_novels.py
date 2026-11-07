#!/usr/bin/env python3
"""Convert Aozora Bunko ruby text into src/js/novels.js, one [display, reading] pair per sentence.

Usage:
  pip install fugashi unidic-lite
  python3 tools/make_novels.py <directory of UTF-8 Aozora texts>

Readings come from morphological analysis (fugashi + UniDic). Where the source
gives a ruby reading (《》), that reading wins.
"""
import json
import re
import sys
from pathlib import Path

import fugashi

# (file name, id, title, author, which chapters to use (None = all))
WORKS = [
    ("789_ruby_5639.txt", "neko", "吾輩は猫である", "夏目漱石", 1),
    ("752_ruby_2438.txt", "bocchan", "坊っちゃん", "夏目漱石", 2),
    ("1567_ruby_4948.txt", "melos", "走れメロス", "太宰治", None),
    ("92_ruby_164.txt", "kumo", "蜘蛛の糸", "芥川龍之介", None),
    ("127_ruby_150.txt", "rashomon", "羅生門", "芥川龍之介", None),
    ("43737_ruby_19028.txt", "ginga", "銀河鉄道の夜", "宮沢賢治", None),
]

MAX_LEN = 42   # 1行の最大文字数（表示）
HARD_MAX = 60  # 読点が無くてもこれより長い文は切る
MIN_LEN = 6    # これより短い文は前の文につなげる

tagger = fugashi.Tagger()
KANJI = r"[㐀-鿿豈-﫿々〆ヶ※]"


def kata_to_hira(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def gaiji(m):
    """※［＃「…」、第3水準1-87-71］ → the actual character (JIS X 0213 plane 1 only)."""
    g = re.search(r"第[34]水準1-(\d+)-(\d+)", m.group(0))
    if g:
        try:
            return bytes([0xA0 + int(g.group(1)), 0xA0 + int(g.group(2))]).decode("euc_jis_2004")
        except UnicodeDecodeError:
            pass
    return "\0"  # 変換できない外字（その文は捨てる）


def body(text, chapters):
    text = text.replace("\r\n", "\n")
    parts = re.split(r"^-{20,}$", text, flags=re.M)
    text = parts[2] if len(parts) >= 3 else text
    text = re.split(r"^底本：", text, flags=re.M)[0]
    out, chapter = [], 0
    for line in text.split("\n"):
        if "見出し］" in line:
            chapter += 1
            if chapters and chapter > chapters:
                break
            continue
        line = re.sub(r"※［＃[^］]*］", gaiji, line)
        line = re.sub(r"［＃[^］]*］", "", line)
        line = line.replace("〔", "").replace("〕", "").strip("　 \t")
        if line:
            out.append(line)
    return out


def segments(line):
    """Split one paragraph into (display, reading | None) pieces; ruby pieces carry a reading."""
    segs, pos = [], 0
    for m in re.finditer(r"(?:｜([^｜《]+)|(" + KANJI + r"+))《([^》]+)》", line):
        if m.start() > pos:
            segs.append((line[pos:m.start()], None))
        segs.append((m.group(1) or m.group(2), m.group(3)))
        pos = m.end()
    if pos < len(line):
        segs.append((line[pos:], None))
    return segs


def read_plain(s):
    r = []
    for w in tagger(s):
        surf = w.surface
        if not re.search(KANJI, surf):
            r.append(surf)
            continue
        kana = getattr(w.feature, "kana", None)
        if not kana or kana == "*":
            return None
        r.append(kana)
    return "".join(r)


def sentences(paragraph):
    """Split at 。！？ (outside quotes) and at a closing 」 that ends a quote."""
    out, cur, depth = [], [], 0
    for d, r in paragraph:
        # ルビ付きの塊は分割しない
        if r is not None:
            cur.append((d, r))
            continue
        buf = ""
        for ch in d:
            buf += ch
            if ch in "「『（":
                depth += 1
            elif ch in "」』）":
                depth = max(0, depth - 1)
            size = sum(len(x) for x, _ in cur) + len(buf)
            # 長い台詞は「」の中でも。で切る
            if (ch in "。！？" and (depth == 0 or size >= 12)) or (ch in "」』" and depth == 0):
                cur.append((buf, None))
                buf = ""
                out.append(cur)
                cur = []
        if buf:
            cur.append((buf, None))
    if cur:
        out.append(cur)
    return out


RUBY = {}  # その作品の中でルビが振られた語 → 読み（ルビの無い箇所の補助に使う）


def read_with_ruby(s):
    """Fallback: split plain text on words that carry ruby elsewhere in the work."""
    keys = sorted(RUBY, key=len, reverse=True)
    if not keys:
        return None
    parts = re.split("(" + "|".join(map(re.escape, keys)) + ")", s)
    out = []
    for i, x in enumerate(parts):
        if i % 2:
            out.append(RUBY[x])
        elif x:
            y = read_plain(x)
            if y is None:
                return None
            out.append(y)
    return "".join(out)


def flatten(sent):
    display = "".join(d for d, _ in sent).strip("　 ")
    reading = []
    for d, r in sent:
        if r is not None:
            reading.append(r)
        else:
            x = read_plain(d)
            if x is None:
                x = read_with_ruby(d)
            if x is None:
                return None
            reading.append(x)
    return display, kata_to_hira("".join(reading)).strip("　 ")


def split_long(display, sent):
    """Split an over-long sentence at the 、 closest to its middle (recursively)."""
    if len(display) <= MAX_LEN:
        return [sent]
    # 句読点で区切れる位置（平文の中だけ）
    cuts, n = [], 0
    for i, (d, r) in enumerate(sent):
        if r is None:
            for j, ch in enumerate(d):
                if ch == "、" and 0 < n + j + 1 < len(display.rstrip("、　 ")):
                    cuts.append((abs(n + j + 1 - len(display) / 2), i, j + 1))
        n += len(d)
    if not cuts and len(display) > HARD_MAX:
        # 読点が無い長文は、助詞の直後（文の真ん中に近い所）で切る
        n = 0
        for i, (d, r) in enumerate(sent):
            if r is None:
                k = 0
                for w in tagger(d):
                    k += len(w.surface)
                    if w.feature.pos1 == "助詞" and 0 < k < len(d):
                        cuts.append((abs(n + k - len(display) / 2), i, k))
            n += len(d)
    if not cuts:
        return [sent]
    _, i, j = min(cuts)
    d, _ = sent[i]
    a = sent[:i] + [(d[:j], None)]
    b = ([(d[j:], None)] if d[j:] else []) + sent[i + 1:]
    da = "".join(x for x, _ in a)
    db = "".join(x for x, _ in b)
    if not da.strip() or not db.strip():
        return [sent]
    return split_long(da, a) + split_long(db, b)


def convert(path, chapters):
    lines, dropped = [], 0
    paras = body(path.read_text(encoding="utf-8"), chapters)
    RUBY.clear()
    for para in paras:
        for d, r in segments(para):
            if r is not None and len(d) >= 2:
                RUBY.setdefault(d, r)
    for para in paras:
        for sent in sentences(segments(para)):
            disp = "".join(d for d, _ in sent)
            for piece in split_long(disp, sent):
                f = flatten(piece)
                if f is None or "\0" in f[0] or not f[0]:
                    dropped += 1
                    continue
                if lines and (len(f[0]) < MIN_LEN or len(lines[-1][0]) < MIN_LEN) and len(lines[-1][0]) + len(f[0]) <= MAX_LEN:
                    lines[-1] = [lines[-1][0] + f[0], lines[-1][1] + f[1]]
                else:
                    lines.append(list(f))
    return lines, dropped


def main():
    src = Path(sys.argv[1])
    novels = []
    for fname, nid, title, author, chapters in WORKS:
        lines, dropped = convert(src / fname, chapters)
        scope = f"（{chapters}章まで）" if chapters else ""
        print(f"{title}{scope}: {len(lines)} 行, 捨てた文 {dropped}", file=sys.stderr)
        novels.append({"id": nid, "title": title, "author": author, "scope": scope, "lines": lines})
    out = Path(__file__).resolve().parent.parent / "src/js/novels.js"
    head = (
        "// 自動生成: tools/make_novels.py（編集しないこと）\n"
        "// 本文は青空文庫（https://www.aozora.gr.jp/）の入力・校正による。著作権の切れた作品のみ。\n"
        "// 読みは形態素解析（UniDic）で付けたもので、誤りを含むことがある。\n"
    )
    out.write_text(head + "export const NOVELS = " + json.dumps(novels, ensure_ascii=False, separators=(",", ":")) + ";\n", encoding="utf-8")
    print(f"→ {out} ({out.stat().st_size // 1024} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
