import Foundation

/// 1つの入力単位（かな1〜2文字 or ASCII 1文字）と、受け付ける打ち方の候補
struct Unit {
    let display: String
    let options: [String]
}

enum Romaji {
    static let single: [String: [String]] = [
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
    ]

    static let combo: [String: [String]] = [
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
    ]

    static func toHiragana(_ c: Character) -> Character {
        guard let s = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return c }
        // カタカナ (ァ〜ヶ) → ひらがな
        if (0x30A1...0x30F6).contains(s.value), let h = Unicode.Scalar(s.value - 0x60) {
            return Character(h)
        }
        if s.value == 0x30F4 { return "ゔ" }
        // 全角英数 → 半角
        if (0xFF01...0xFF5E).contains(s.value), let a = Unicode.Scalar(s.value - 0xFEE0) {
            let ch = Character(a)
            if single[String(ch)] == nil { return ch }
        }
        return c
    }

    private static func isConsonant(_ c: Character) -> Bool {
        c.isLetter && c.isASCII && !"aiueon".contains(c)
    }

    /// 読み（かな + ASCII）を入力単位に分解する。入力できない文字（漢字など）は捨てる。
    static func units(from text: String) -> [Unit] {
        let orig = Array(text)
        let hira = orig.map(toHiragana)
        var raw: [Unit] = []
        var i = 0
        while i < hira.count {
            if i + 1 < hira.count {
                let key = String(hira[i...i + 1])
                if var opts = combo[key] {
                    // 分解打ち（例: ki + xya）も許可
                    for a in single[String(hira[i])] ?? [] {
                        for b in single[String(hira[i + 1])] ?? [] { opts.append(a + b) }
                    }
                    raw.append(Unit(display: String(orig[i...i + 1]), options: opts))
                    i += 2
                    continue
                }
            }
            let s = String(hira[i])
            if let opts = single[s] {
                raw.append(Unit(display: String(orig[i]), options: opts))
            } else if let a = hira[i].asciiValue, a >= 32, a < 127 {
                raw.append(Unit(display: s, options: [s]))
            }
            i += 1
        }

        // 促音「っ」と撥音「ん」の処理
        var out: [Unit] = []
        var j = 0
        while j < raw.count {
            let u = raw[j]
            let h = String(u.display.map(toHiragana))
            if h == "っ", j + 1 < raw.count {
                let n = raw[j + 1]
                var opts: [String] = []
                for o in n.options {
                    if let f = o.first, isConsonant(f) { opts.append(String(f) + o) }
                }
                if !opts.isEmpty {
                    for x in single["っ"]! { opts += n.options.map { x + $0 } }
                    out.append(Unit(display: u.display + n.display, options: opts))
                    j += 2
                    continue
                }
            }
            if h == "ん" {
                var opts = ["nn", "xn", "n'"]
                if j + 1 < raw.count {
                    let next = raw[j + 1].options
                    let ok = next.allSatisfy { o in
                        guard let f = o.first else { return false }
                        return !"aiueoyn'".contains(f)
                    }
                    if ok { opts.append("n") }
                }
                out.append(Unit(display: u.display, options: opts))
                j += 1
                continue
            }
            out.append(u)
            j += 1
        }
        return out
    }
}
