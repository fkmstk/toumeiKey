import Foundation
import Combine

struct Sentence: Equatable {
    let display: String   // 画面に出す文（漢字かな交じり / 英文）
    let reading: String   // 打つ読み（かな / 英文）

    /// カスタム文の1行をパースする。「表示|よみ」形式なら漢字交じりの文も練習できる。
    static func parse(_ line: String) -> Sentence? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let s = parts.count == 2 && !parts[1].isEmpty
            ? Sentence(display: parts[0], reading: parts[1])
            : Sentence(display: t, reading: t)
        return Romaji.units(from: s.reading).isEmpty ? nil : s
    }
}

enum Mode: String, CaseIterable, Identifiable {
    case japanese, english, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .custom: return "カスタム"
        }
    }
}

/// 出題の種類（日本語・English モードで有効）
enum ContentKind: String, CaseIterable, Identifiable {
    case sentences, words, mix
    var id: String { rawValue }
    var label: String { ["sentences": "文章", "words": "単語", "mix": "ミックス"][rawValue]! }
}

enum TypingEvent { case hit(Character), miss, lineDone(Character) }

final class TypingModel: ObservableObject {
    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            resetSession()
            nextSentence()
        }
    }
    @Published private(set) var sentence = Sentence(display: "", reading: "")
    @Published private(set) var upcoming = Sentence(display: "", reading: "")
    @Published private(set) var units: [Unit] = []
    @Published private(set) var index = 0
    @Published private(set) var buffer = ""
    @Published private(set) var typed: [String] = []   // 確定済み単位で実際に打った文字列
    @Published private(set) var missFlash = false
    @Published private(set) var doneFlash = false

    // セッション統計（キーを打っている時間だけ計測するので、動画に見入って止まっても KPM が落ちない）
    @Published private(set) var correct = 0
    @Published private(set) var misses = 0
    @Published private(set) var lines = 0
    @Published private(set) var activeTime: TimeInterval = 0
    @Published private(set) var weakKeys: [String: Int] = [:]
    @Published private(set) var lastLineKPM: Int?
    private var lastKeyAt: Date?
    private let idleCap: TimeInterval = 2.0
    private var lineStartCorrect = 0
    private var lineStartTime: TimeInterval = 0
    private var lineMisses = 0

    // 永続記録
    @Published private(set) var bestKPM: Int = UserDefaults.standard.integer(forKey: "bestKPM")
    let analytics: Analytics

    @Published private(set) var customSentences: [Sentence] = []

    var onEvent: ((TypingEvent) -> Void)?

    init(analytics: Analytics = Analytics()) {
        self.analytics = analytics
        let d = UserDefaults.standard
        let custom = (d.stringArray(forKey: "customLines") ?? []).compactMap(Sentence.parse)
        var saved = d.string(forKey: "mode").flatMap(Mode.init) ?? .japanese
        if saved == .custom && custom.isEmpty { saved = .japanese }
        mode = saved
        customSentences = custom
        nextSentence()
    }

    var kpm: Int { activeTime > 1 ? Int(Double(correct) / activeTime * 60) : 0 }
    var accuracy: Double {
        let total = correct + misses
        return total == 0 ? 100 : Double(correct) / Double(total) * 100
    }
    var topWeakKeys: [String] {
        weakKeys.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }
    var progress: Double { units.isEmpty ? 0 : Double(index) / Double(units.count) }

    // MARK: - 表示用

    /// 各単位のガイド（確定済みは実際に打った綴り、未確定は推奨綴り）
    private func guide(_ i: Int) -> String {
        if i < index { return typed[i] }
        let u = units[i]
        if i == index, !buffer.isEmpty {
            return u.options.first { $0.hasPrefix(buffer) } ?? u.options[0]
        }
        return u.options[0]
    }

    /// (打ち終えた部分, 次に打つ1文字, 残り)
    var romajiParts: (String, String, String) {
        guard !units.isEmpty else { return ("", "", "") }
        let done = typed.joined() + buffer
        if index >= units.count { return (done, "", "") }
        var rest = String(guide(index).dropFirst(buffer.count))
        for i in (index + 1)..<units.count { rest += guide(i) }
        let next = rest.isEmpty ? "" : String(rest.removeFirst())
        return (done, next, rest)
    }

    var nextKey: String { romajiParts.1 }

    /// かな表示 (確定済み, 入力中, 残り)
    var kanaParts: (String, String, String) {
        let d = units.prefix(index).map(\.display).joined()
        let c = index < units.count ? units[index].display : ""
        let r = index + 1 < units.count ? units[(index + 1)...].map(\.display).joined() : ""
        return (d, c, r)
    }

    var showsReading: Bool { sentence.display != sentence.reading }

    /// 大文字を含まない文は Caps Lock / Shift を気にせず打てるよう小文字化して判定
    private var caseInsensitive: Bool {
        !sentence.reading.contains { $0.isASCII && $0.isUppercase }
    }

    // MARK: - 入力

    func type(_ raw: Character) {
        guard index < units.count else { return }
        let ch = caseInsensitive ? Character(raw.lowercased()) : raw

        let now = Date()
        var interval: TimeInterval?
        if let last = lastKeyAt {
            let d = now.timeIntervalSince(last)
            interval = d
            activeTime += min(d, idleCap)
            analytics.active(min(d, idleCap))
        }
        lastKeyAt = now

        let expected = nextKey
        let unit = index < units.count ? units[index].display : nil
        if accept(ch) {
            correct += 1
            analytics.hit(key: String(ch), interval: interval)
            if index >= units.count { finishLine(ch) } else { onEvent?(.hit(ch)) }
        } else {
            misses += 1
            lineMisses += 1
            analytics.miss(expected: expected, typed: String(ch), unit: unit)
            if !expected.isEmpty { weakKeys[expected, default: 0] += 1 }
            missFlash = true
            onEvent?(.miss)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.missFlash = false }
        }
    }

    private func finishLine(_ last: Character) {
        lines += 1
        let keys = correct - lineStartCorrect
        let t = activeTime - lineStartTime
        if t > 0.5 {
            let k = Int(Double(keys) / t * 60)
            lastLineKPM = k
            analytics.line(LineRecord(
                date: Date(), kpm: k,
                accuracy: Double(keys) / Double(max(1, keys + lineMisses)) * 100,
                keys: keys, misses: lineMisses, mode: mode.rawValue,
                text: String(sentence.display.prefix(60))))
            // 短すぎる行・ミスが多い行はベスト記録の対象外
            if keys >= 15, lineMisses <= keys / 10, k > bestKPM {
                bestKPM = k
                UserDefaults.standard.set(k, forKey: "bestKPM")
            }
        }
        doneFlash = true
        onEvent?(.lineDone(last))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.doneFlash = false
            self?.nextSentence()
        }
    }

    private func accept(_ c: Character) -> Bool {
        guard index < units.count else { return false }
        let u = units[index]
        let nb = buffer + String(c)
        let cands = u.options.filter { $0.hasPrefix(nb) }
        if !cands.isEmpty {
            buffer = nb
            if cands.contains(nb) && !cands.contains(where: { $0.count > nb.count }) {
                commit(nb)
            }
            return true
        }
        // 例:「ん」を n 1つで確定させて次の単位へ
        if !buffer.isEmpty, u.options.contains(buffer) {
            commit(buffer)
            return accept(c)
        }
        return false
    }

    private func commit(_ s: String) {
        if index < units.count { analytics.unitDone(units[index].display) }
        typed.append(s)
        buffer = ""
        index += 1
    }

    func restartLine() {
        index = 0
        buffer = ""
        typed = []
        lineStartCorrect = correct
        lineStartTime = activeTime
        lineMisses = 0
    }

    func skip() { nextSentence() }

    func resetSession() {
        correct = 0; misses = 0; lines = 0; activeTime = 0; lastKeyAt = nil; weakKeys = [:]; lastLineKPM = nil
        restartLine()
    }

    func resetRecords() {
        bestKPM = 0
        UserDefaults.standard.set(0, forKey: "bestKPM")
        analytics.reset()
    }

    private var upcomingKey = ""
    private var poolKey: String { "\(mode.rawValue)-\(kind.rawValue)-\(customSentences.count)" }
    private var kind: ContentKind {
        UserDefaults.standard.string(forKey: "contentKind").flatMap(ContentKind.init) ?? .mix
    }

    func nextSentence() {
        // モードや出題の種類が変わっていたら「次の文」も作り直す
        if upcomingKey != poolKey || upcoming.reading.isEmpty { upcoming = randomSentence(excluding: nil) }
        sentence = upcoming
        upcoming = randomSentence(excluding: sentence)
        upcomingKey = poolKey
        units = Romaji.units(from: sentence.reading)
        restartLine()
    }

    /// 出題の種類を変えたとき
    func contentKindChanged() {
        upcomingKey = ""
        nextSentence()
    }

    /// 改行区切りのテキストをカスタム問題として読み込む。読み込めた行数を返す。
    @discardableResult
    func loadCustom(_ text: String) -> Int {
        let raw = text.components(separatedBy: .newlines)
        let ss = raw.compactMap(Sentence.parse)
        guard !ss.isEmpty else { return 0 }
        customSentences = ss
        UserDefaults.standard.set(raw.filter { Sentence.parse($0) != nil }, forKey: "customLines")
        if mode == .custom { resetSession(); nextSentence() } else { mode = .custom }
        return ss.count
    }

    // MARK: - 出題

    private var pool: [Sentence] {
        switch mode {
        case .japanese: return Texts.allJapanese
        case .english: return Texts.allEnglish
        case .custom: return customSentences.isEmpty ? Texts.allEnglish : customSentences
        }
    }

    private func randomSentence(excluding ex: Sentence?) -> Sentence {
        if mode != .custom {
            let useWords = kind == .words || (kind == .mix && Double.random(in: 0..<1) < 0.35)
            if useWords { return Texts.wordLine(japanese: mode == .japanese) }
        }
        let p = pool
        if p.count <= 1 { return p.first ?? Sentence(display: "", reading: "") }
        var s: Sentence
        repeat { s = p.randomElement()! } while s == ex
        return s
    }
}
