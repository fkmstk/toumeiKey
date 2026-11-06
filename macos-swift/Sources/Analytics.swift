import Foundation
import Combine

struct KeyStat: Codable {
    var hits = 0
    var misses = 0
    var totalSec = 0.0     // 直前の打鍵からの間隔の合計（測れたものだけ）
    var timed = 0

    var attempts: Int { hits + misses }
    var missRate: Double { attempts == 0 ? 0 : Double(misses) / Double(attempts) }
    var avgMs: Double? { timed == 0 ? nil : totalSec / Double(timed) * 1000 }

    mutating func add(_ o: KeyStat) {
        hits += o.hits; misses += o.misses; totalSec += o.totalSec; timed += o.timed
    }
}

struct DayStat: Codable {
    var keys = 0
    var misses = 0
    var activeSec = 0.0
    var lines = 0
    var bestKPM = 0

    var kpm: Int { activeSec > 1 ? Int(Double(keys) / activeSec * 60) : 0 }
    var accuracy: Double { keys + misses == 0 ? 0 : Double(keys) / Double(keys + misses) * 100 }
}

struct LineRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var kpm: Int
    var accuracy: Double
    var keys: Int
    var misses: Int
    var mode: String
    var text: String
}

struct AnalyticsData: Codable {
    var keys: [String: KeyStat] = [:]        // 打つべきだったキー → 成績
    var units: [String: KeyStat] = [:]       // かな単位（しゃ, っ, ん …）→ 成績
    var confusions: [String: Int] = [:]      // "e→r"（e を打つべきところで r を打った）
    var days: [String: DayStat] = [:]        // "yyyy-MM-dd"
    var lines: [LineRecord] = []
}

/// 練習データを ~/Library/Application Support/TypingOverlay/analytics.json に保存する
final class Analytics: ObservableObject {
    @Published private(set) var data = AnalyticsData()
    private var saveWork: DispatchWorkItem?
    private let maxLines = 3000
    private let idleCap: TimeInterval = 2.0

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let url: URL

    private static let defaultURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypingOverlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("analytics.json")
    }()

    init(fileURL: URL? = nil) {
        url = fileURL ?? Self.defaultURL
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder.iso.decode(AnalyticsData.self, from: d) {
            data = v
        }
    }

    // MARK: 記録

    private var todayKey: String { Self.dayFormatter.string(from: Date()) }

    private static func norm(_ k: String) -> String { k.lowercased() }

    func hit(key: String, interval: TimeInterval?) {
        guard !key.isEmpty else { return }
        var s = data.keys[Self.norm(key)] ?? KeyStat()
        s.hits += 1
        if let i = interval, i < idleCap { s.totalSec += i; s.timed += 1 }
        data.keys[Self.norm(key)] = s
        data.days[todayKey, default: DayStat()].keys += 1
        scheduleSave()
    }

    func miss(expected: String, typed: String, unit: String?) {
        if !expected.isEmpty {
            data.keys[Self.norm(expected), default: KeyStat()].misses += 1
            if !typed.isEmpty { data.confusions["\(Self.norm(expected))→\(typed.lowercased())", default: 0] += 1 }
        }
        if let u = unit, isKanaUnit(u) { data.units[u, default: KeyStat()].misses += 1 }
        data.days[todayKey, default: DayStat()].misses += 1
        scheduleSave()
    }

    /// かな単位を打ち終えた
    func unitDone(_ u: String) {
        guard isKanaUnit(u) else { return }
        data.units[u, default: KeyStat()].hits += 1
    }

    func active(_ sec: TimeInterval) {
        data.days[todayKey, default: DayStat()].activeSec += sec
    }

    func line(_ r: LineRecord) {
        data.lines.append(r)
        if data.lines.count > maxLines { data.lines.removeFirst(data.lines.count - maxLines) }
        var d = data.days[todayKey, default: DayStat()]
        d.lines += 1
        d.bestKPM = max(d.bestKPM, r.kpm)
        data.days[todayKey] = d
        scheduleSave()
    }

    private func isKanaUnit(_ u: String) -> Bool {
        u.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    func reset() {
        data = AnalyticsData()
        saveNow()
    }

    // MARK: 保存

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    func saveNow() {
        saveWork?.cancel()
        if let d = try? JSONEncoder.iso.encode(data) { try? d.write(to: url, options: .atomic) }
    }

    // MARK: 集計

    var today: DayStat { data.days[todayKey] ?? DayStat() }

    /// 連続練習日数（今日まだ打っていなければ昨日から数える）
    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if (data.days[Self.dayFormatter.string(from: day)]?.keys ?? 0) == 0 {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var n = 0
        while (data.days[Self.dayFormatter.string(from: day)]?.keys ?? 0) > 0 {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    /// 直近 n 日（今日を含む、練習しなかった日は 0 で埋める）。n=nil なら記録のある最初の日から
    func dayRange(_ n: Int?) -> [(date: Date, stat: DayStat)] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var count = n ?? 7
        if n == nil, let first = data.days.keys.sorted().first, let fd = Self.dayFormatter.date(from: first) {
            count = max(7, (cal.dateComponents([.day], from: fd, to: todayStart).day ?? 0) + 1)
        }
        return (0..<count).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: todayStart)!
            return (d, data.days[Self.dayFormatter.string(from: d)] ?? DayStat())
        }
    }

    func lines(since: Date?) -> [LineRecord] {
        guard let s = since else { return data.lines }
        return data.lines.filter { $0.date >= s }
    }

    // MARK: CSV

    func linesCSV() -> String {
        let f = ISO8601DateFormatter()
        var out = "date,mode,kpm,accuracy,keys,misses,text\n"
        for l in data.lines {
            let t = l.text.replacingOccurrences(of: "\"", with: "\"\"")
            out += "\(f.string(from: l.date)),\(l.mode),\(l.kpm),\(String(format: "%.1f", l.accuracy)),\(l.keys),\(l.misses),\"\(t)\"\n"
        }
        return out
    }

    func keysCSV() -> String {
        var out = "key,hits,misses,miss_rate,avg_ms\n"
        for (k, s) in data.keys.sorted(by: { $0.key < $1.key }) {
            let key = k == "," ? "\",\"" : (k == "\"" ? "\"\"\"\"" : k)
            out += "\(key),\(s.hits),\(s.misses),\(String(format: "%.4f", s.missRate)),\(s.avgMs.map { String(format: "%.0f", $0) } ?? "")\n"
        }
        return out
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}
extension JSONDecoder {
    static let iso: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
