import SwiftUI
import Charts

// MARK: - 配色（ダークモード固定。参照パレットのダーク段）

enum VZ {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    static let page = hex(0x0d0d0d)
    static let surface = hex(0x1a1a19)
    static let ink = hex(0xf0efec)
    static let ink2 = hex(0xc3c2b7)
    static let muted = hex(0x898781)
    static let grid = hex(0x2c2c2a)
    static let baseline = hex(0x383835)
    static let border = Color.white.opacity(0.10)
    // 単一系列のグラフは系列の色を固定（指標ごとに1色）
    static let kpm = hex(0x3987e5)      // 青
    static let time = hex(0x9085e9)     // 紫
    static let acc = hex(0x199e70)      // アクア
    // ステータス（必ずアイコン + ラベルと併用）
    static let good = hex(0x0ca30c)
    static let critical = hex(0xd03b3b)
    // 連続値（ヒートマップ）: 青の単色ランプ。ダーク面では小さい値ほど面に沈む
    static let ramp: [UInt32] = [0x184f95, 0x1c5cab, 0x256abf, 0x2a78d6, 0x3987e5, 0x5598e7, 0x6da7ec, 0x86b6ef, 0x9ec5f4, 0xb7d3f6, 0xcde2fb]
    static func rampColor(_ t: Double) -> Color {
        let i = Int((max(0, min(1, t)) * Double(ramp.count - 1)).rounded())
        return hex(ramp[i])
    }
    static func rampInk(_ t: Double) -> Color { t > 0.55 ? hex(0x0b0b0b) : .white }
}

enum StatRange: String, CaseIterable, Identifiable {
    case week, month, all
    var id: String { rawValue }
    var label: String { ["week": "7日", "month": "30日", "all": "全期間"][rawValue]! }
    var days: Int? { self == .week ? 7 : self == .month ? 30 : nil }
}

enum HeatMetric: String, CaseIterable, Identifiable {
    case missRate, speed
    var id: String { rawValue }
    var label: String { self == .missRate ? "ミス率" : "打鍵間隔" }
}

// MARK: - 画面

struct AnalyticsView: View {
    @ObservedObject var a: Analytics
    let exportCSV: () -> Void
    @AppStorage("keyLayout") private var keyLayout = KeyLayout.auto
    @State private var range: StatRange = .week
    @State private var heat: HeatMetric = .missRate
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolbar
                if a.data.keys.isEmpty && a.data.lines.isEmpty {
                    emptyState
                } else {
                    tiles
                    KPMTrendCard(lines: lines)
                    HStack(alignment: .top, spacing: 14) {
                        DailyBarCard(days: days)
                        DailyLineCard(title: "日別の平均 KPM", subtitle: "その日の打鍵数 ÷ 打鍵していた時間",
                                      days: days, color: VZ.kpm, unit: "KPM",
                                      value: { $0.keys > 0 ? Double($0.kpm) : nil })
                    }
                    HStack(alignment: .top, spacing: 14) {
                        DailyLineCard(title: "日別の正確率", subtitle: "正しく打った数 ÷ 全打鍵",
                                      days: days, color: VZ.acc, unit: "%",
                                      value: { $0.keys + $0.misses > 0 ? $0.accuracy : nil })
                        fingerCard
                    }
                    heatmapCard
                    HStack(alignment: .top, spacing: 14) {
                        RankCard(title: "苦手なキー", subtitle: "ミス率が高い順（20回以上打ったキー・全期間）", rows: weakKeyRows)
                        RankCard(title: "時間がかかるキー", subtitle: "直前のキーからの平均間隔（全期間）", rows: slowKeyRows)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        RankCard(title: "よくある打ち間違い", subtitle: "打つべきキー → 実際に打ったキー（全期間）", rows: confusionRows)
                        RankCard(title: "苦手なかな", subtitle: "ミス率が高い順（5回以上・全期間）", rows: kanaRows)
                    }
                    recentCard
                }
            }
            .padding(20)
        }
        .background(VZ.page)
        .foregroundColor(VZ.ink)
        .frame(minWidth: 860, minHeight: 600)
        .confirmationDialog("記録をすべて消去しますか？", isPresented: $confirmReset) {
            Button("消去する", role: .destructive) { a.reset() }
        } message: { Text("キー別・日別・行ごとの記録がすべて消えます。元に戻せません。") }
    }

    // MARK: 期間

    private var days: [(date: Date, stat: DayStat)] { a.dayRange(range.days) }
    private var since: Date? {
        range.days.map { Calendar.current.date(byAdding: .day, value: -($0 - 1), to: Calendar.current.startOfDay(for: Date()))! }
    }
    private var lines: [LineRecord] { a.lines(since: since) }

    /// 同じ長さの1つ前の期間（比較用）
    private var previousDays: [DayStat]? {
        guard let n = range.days else { return nil }
        let all = a.dayRange(n * 2)
        return Array(all.prefix(n)).map(\.stat)
    }

    // MARK: 上部

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("統計・分析").font(.system(size: 22, weight: .bold))
            Picker("", selection: $range) {
                ForEach(StatRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            Button { exportCSV() } label: { Label("CSV 書き出し", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { confirmReset = true } label: { Label("記録を消去", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 40)).foregroundColor(VZ.muted)
            Text("まだ記録がありません").font(.headline)
            Text("帯で何行か打つと、ここに速さ・正確さ・苦手なキーが表示されます。").foregroundColor(VZ.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .card()
    }

    private var tiles: some View {
        let ds = days.map(\.stat)
        let keys = ds.reduce(0) { $0 + $1.keys }
        let miss = ds.reduce(0) { $0 + $1.misses }
        let sec = ds.reduce(0) { $0 + $1.activeSec }
        let kpm = sec > 1 ? Int(Double(keys) / sec * 60) : 0
        let acc = keys + miss > 0 ? Double(keys) / Double(keys + miss) * 100 : 0
        let best = lines.map(\.kpm).max() ?? 0

        var dKPM: Double?, dAcc: Double?, dTime: Double?
        if let p = previousDays {
            let pk = p.reduce(0) { $0 + $1.keys }, pm = p.reduce(0) { $0 + $1.misses }, ps = p.reduce(0) { $0 + $1.activeSec }
            if ps > 1 && sec > 1 { dKPM = Double(kpm - Int(Double(pk) / ps * 60)) }
            if pk + pm > 0 && keys + miss > 0 { dAcc = acc - Double(pk) / Double(pk + pm) * 100 }
            if ps > 0 { dTime = (sec - ps) / 60 }
        }
        let cmp = range == .week ? "前の7日比" : "前の30日比"

        return HStack(spacing: 14) {
            StatTile(title: "平均 KPM", value: "\(kpm)", delta: dKPM.map { (String(format: "%+.0f", $0), $0 >= 0) }, note: cmp)
            StatTile(title: "正確率", value: String(format: "%.1f%%", acc), delta: dAcc.map { (String(format: "%+.1f pt", $0), $0 >= 0) }, note: cmp)
            StatTile(title: "練習時間", value: formatDuration(sec), delta: dTime.map { (String(format: "%+.0f 分", $0), $0 >= 0) }, note: cmp)
            StatTile(title: "打鍵数", value: keys.formatted(), delta: nil, note: "\(lines.count) 行")
            StatTile(title: "ベスト KPM", value: "\(best)", delta: nil, note: "この期間の1行")
            StatTile(title: "連続練習", value: "\(a.streak) 日", delta: nil, note: "今日 \(formatDuration(a.today.activeSec))")
        }
    }

    // MARK: キーボードのヒートマップ

    private func keyStat(_ k: KeyDef) -> KeyStat {
        var s = a.data.keys[k.normal.lowercased()] ?? KeyStat()
        if k.shifted.lowercased() != k.normal.lowercased(), let sh = a.data.keys[k.shifted.lowercased()] { s.add(sh) }
        return s
    }

    private func metric(_ s: KeyStat) -> Double? {
        switch heat {
        case .missRate: return s.attempts >= 5 ? s.missRate * 100 : nil
        case .speed: return s.timed >= 5 ? s.avgMs : nil
        }
    }

    private var heatmapCard: some View {
        let rows = keyLayout.rows
        let space = a.data.keys[" "] ?? KeyStat()
        let vals = rows.flatMap { $0 }.compactMap { metric(keyStat($0)) } + [metric(space)].compactMap { $0 }
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let norm: (Double) -> Double = { hi - lo < 0.0001 ? 0.5 : ($0 - lo) / (hi - lo) }
        let fmt: (Double) -> String = { heat == .missRate ? String(format: "%.0f%%", $0) : String(format: "%.0f", $0) }
        let indent: [CGFloat] = [0, 0.5, 0.8, 1.3]
        let u: CGFloat = 40

        func cell(_ label: String, _ s: KeyStat, width: CGFloat) -> some View {
            let v = metric(s)
            let t = v.map(norm)
            return VStack(spacing: 1) {
                Text(label).font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(v.map(fmt) ?? "–").font(.system(size: 9)).monospacedDigit().opacity(0.85)
            }
            .foregroundColor(t.map(VZ.rampInk) ?? VZ.muted)
            .frame(width: width, height: u)
            .background(RoundedRectangle(cornerRadius: 5).fill(t.map(VZ.rampColor) ?? VZ.grid))
            .help("\(label == "space" ? "スペース" : label)  打鍵 \(s.hits) / ミス \(s.misses)  (\(String(format: "%.1f", s.missRate * 100))%)"
                  + (s.avgMs.map { String(format: "  平均 %.0fms", $0) } ?? ""))
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(title: "キーボード ヒートマップ",
                          subtitle: heat == .missRate ? "キーごとのミス率（5回以上打ったキー・全期間）。色が明るいほど苦手"
                                                      : "直前の打鍵からの平均間隔 ms（全期間）。色が明るいほど時間がかかる")
                Spacer()
                Picker("", selection: $heat) { ForEach(HeatMetric.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<rows.count, id: \.self) { r in
                        HStack(spacing: 3) {
                            Spacer().frame(width: u * indent[r])
                            ForEach(rows[r], id: \.self) { k in cell(k.label, keyStat(k), width: u) }
                        }
                    }
                    HStack(spacing: 3) {
                        Spacer().frame(width: u * 3.6)
                        cell("space", space, width: u * 6)
                    }
                }
                // 凡例
                VStack(alignment: .leading, spacing: 4) {
                    Text(heat.label + (heat == .speed ? " (ms)" : "")).font(.caption).foregroundColor(VZ.ink2)
                    LinearGradient(colors: VZ.ramp.map(VZ.hex), startPoint: .leading, endPoint: .trailing)
                        .frame(width: 160, height: 10).clipShape(RoundedRectangle(cornerRadius: 3))
                    HStack {
                        Text(vals.isEmpty ? "–" : fmt(lo)); Spacer(); Text(vals.isEmpty ? "–" : fmt(hi))
                    }
                    .font(.caption2).foregroundColor(VZ.muted).frame(width: 160)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(VZ.grid).frame(width: 10, height: 10)
                        Text("データ不足").font(.caption2).foregroundColor(VZ.muted)
                    }
                }
            }
        }
        .card()
    }

    // MARK: 指ごと

    private var fingerCard: some View {
        var agg = [KeyStat](repeating: KeyStat(), count: 9)
        for (k, s) in a.data.keys {
            if let f = keyLayout.lookup(k)?.0.finger ?? keyLayout.lookup(k.uppercased())?.0.finger { agg[f].add(s) }
        }
        let maxRate = max(0.0001, agg.map(\.missRate).max() ?? 0)
        let rows = (0..<9).map { i -> RankRow in
            let s = agg[i]
            return RankRow(label: Finger.names[i], value: s.attempts == 0 ? "–" : String(format: "%.1f%%", s.missRate * 100),
                           fraction: s.missRate / maxRate,
                           detail: s.avgMs.map { String(format: "%.0fms", $0) } ?? "", swatch: Finger.colors[i])
        }
        return RankCard(title: "指ごとのミス率", subtitle: "右の数字は平均打鍵間隔（全期間）", rows: rows)
    }

    // MARK: ランキング

    private func keyLabel(_ k: String) -> String { k == " " ? "␣ space" : k.uppercased() == k.lowercased() ? k : k.uppercased() }

    private var weakKeyRows: [RankRow] {
        let xs = a.data.keys.filter { $0.value.attempts >= 20 }.sorted { $0.value.missRate > $1.value.missRate }.prefix(8)
        let m = max(0.0001, xs.first?.value.missRate ?? 0)
        return xs.map { RankRow(label: keyLabel($0.key), value: String(format: "%.1f%%", $0.value.missRate * 100),
                                fraction: $0.value.missRate / m, detail: "\($0.value.misses)/\($0.value.attempts)") }
    }

    private var slowKeyRows: [RankRow] {
        let xs = a.data.keys.compactMap { k, s in s.timed >= 20 ? (k, s.avgMs!) : nil }.sorted { $0.1 > $1.1 }.prefix(8)
        let m = max(1, xs.first?.1 ?? 1)
        return xs.map { RankRow(label: keyLabel($0.0), value: String(format: "%.0f ms", $0.1), fraction: $0.1 / m, detail: "") }
    }

    private var confusionRows: [RankRow] {
        let xs = a.data.confusions.sorted { $0.value > $1.value }.prefix(8)
        let m = Double(max(1, xs.first?.value ?? 1))
        return xs.map { kv in
            let p = kv.key.components(separatedBy: "→")
            let l = p.count == 2 ? "\(keyLabel(p[0]))  →  \(keyLabel(p[1]))" : kv.key
            return RankRow(label: l, value: "\(kv.value) 回", fraction: Double(kv.value) / m, detail: "")
        }
    }

    private var kanaRows: [RankRow] {
        let xs = a.data.units.filter { $0.value.attempts >= 5 }.sorted { $0.value.missRate > $1.value.missRate }.prefix(8)
        let m = max(0.0001, xs.first?.value.missRate ?? 0)
        return xs.map { RankRow(label: $0.key, value: String(format: "%.1f%%", $0.value.missRate * 100),
                                fraction: $0.value.missRate / m, detail: "\($0.value.misses)/\($0.value.attempts)") }
    }

    // MARK: 最近の行

    private var recentCard: some View {
        let recent = Array(lines.suffix(40).reversed())
        let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f }()
        return VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "最近の行", subtitle: "新しい順に最大40行")
            if recent.isEmpty {
                Text("この期間の記録はありません").foregroundColor(VZ.muted).padding(.vertical, 8)
            } else {
                Table(recent) {
                    TableColumn("日時") { Text(df.string(from: $0.date)).monospacedDigit() }.width(90)
                    TableColumn("モード") { Text(Mode(rawValue: $0.mode)?.label ?? $0.mode) }.width(70)
                    TableColumn("KPM") { Text("\($0.kpm)").monospacedDigit() }.width(50)
                    TableColumn("正確率") { Text(String(format: "%.1f%%", $0.accuracy)).monospacedDigit() }.width(60)
                    TableColumn("ミス") { Text("\($0.misses)").monospacedDigit() }.width(40)
                    TableColumn("文") { Text($0.text).lineLimit(1) }
                }
                .frame(height: 280)
                .scrollContentBackground(.hidden)
            }
        }
        .card()
    }
}

func formatDuration(_ sec: Double) -> String {
    let m = Int(sec / 60)
    return m >= 60 ? "\(m / 60)時間\(m % 60)分" : "\(m)分"
}

// MARK: - 部品

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VZ.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VZ.border, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

struct CardTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(VZ.ink)
            Text(subtitle).font(.system(size: 11)).foregroundColor(VZ.ink2)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let delta: (String, Bool)?   // (表示, 良くなったか)
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundColor(VZ.ink2)
            Text(value).font(.system(size: 24, weight: .semibold)).foregroundColor(VZ.ink).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                if let (t, up) = delta {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .foregroundColor(up ? VZ.good : VZ.critical)
                    Text(t).foregroundColor(VZ.ink2).monospacedDigit()
                }
                Text(note).foregroundColor(VZ.muted)
            }
            .font(.system(size: 10))
            .lineLimit(1)
        }
        .card()
    }
}

struct RankRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let fraction: Double
    let detail: String
    var swatch: Color? = nil
}

struct RankCard: View {
    let title: String
    let subtitle: String
    let rows: [RankRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: title, subtitle: subtitle)
            if rows.isEmpty {
                Text("データがまだ足りません").font(.system(size: 12)).foregroundColor(VZ.muted).padding(.vertical, 6)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                    ForEach(rows) { r in
                        GridRow {
                            HStack(spacing: 6) {
                                if let c = r.swatch { Circle().fill(c).frame(width: 8, height: 8) }
                                Text(r.label).font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            .frame(minWidth: 90, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(VZ.grid)
                                    Capsule().fill(VZ.kpm).frame(width: max(4, g.size.width * r.fraction))
                                }
                            }
                            .frame(height: 6)
                            Text(r.value).font(.system(size: 12)).monospacedDigit().foregroundColor(VZ.ink)
                                .frame(minWidth: 54, alignment: .trailing)
                            Text(r.detail).font(.system(size: 10)).monospacedDigit().foregroundColor(VZ.muted)
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .card()
    }
}

// MARK: - グラフ

private func axisStyle() -> some AxisContent {
    AxisMarks { _ in
        AxisGridLine().foregroundStyle(VZ.grid)
        AxisValueLabel().foregroundStyle(VZ.muted)
    }
}

/// 行ごとの KPM（点）と直近10行の移動平均（線）
struct KPMTrendCard: View {
    let lines: [LineRecord]
    @State private var sel: Int?

    private var points: [(i: Int, kpm: Double, avg: Double, rec: LineRecord)] {
        var out: [(Int, Double, Double, LineRecord)] = []
        var window: [Double] = []
        for (i, l) in lines.enumerated() {
            window.append(Double(l.kpm))
            if window.count > 10 { window.removeFirst() }
            out.append((i + 1, Double(l.kpm), window.reduce(0, +) / Double(window.count), l))
        }
        return out
    }

    var body: some View {
        let pts = points
        let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f }()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                CardTitle(title: "KPM の推移", subtitle: "点 = 各行の KPM、線 = 直近10行の平均")
                Spacer()
                if let last = pts.last {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(last.avg))").font(.system(size: 22, weight: .semibold))
                        Text("直近10行の平均 KPM").font(.system(size: 10)).foregroundColor(VZ.ink2)
                    }
                }
            }
            if pts.count < 2 {
                Text("2行以上打つとグラフが表示されます").font(.system(size: 12)).foregroundColor(VZ.muted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(pts, id: \.i) { p in
                        PointMark(x: .value("行", p.i), y: .value("KPM", p.kpm))
                            .symbolSize(18)
                            .foregroundStyle(VZ.kpm.opacity(0.35))
                    }
                    ForEach(pts, id: \.i) { p in
                        LineMark(x: .value("行", p.i), y: .value("平均", p.avg))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(VZ.kpm)
                    }
                    if let s = sel, let p = pts.first(where: { $0.i == s }) {
                        RuleMark(x: .value("行", p.i))
                            .foregroundStyle(VZ.baseline)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Tooltip(lines: [
                                    "\(p.i) 行目  \(df.string(from: p.rec.date))",
                                    "KPM \(p.rec.kpm)   平均 \(Int(p.avg))",
                                    String(format: "正確率 %.1f%%", p.rec.accuracy),
                                    p.rec.text,
                                ])
                            }
                        PointMark(x: .value("行", p.i), y: .value("KPM", p.kpm))
                            .symbolSize(70).foregroundStyle(VZ.kpm)
                    }
                }
                .chartXSelection(value: $sel)
                .chartXAxis { axisStyle() }
                .chartYAxis { axisStyle() }
                .chartYScale(domain: yDomain(pts.map(\.kpm)))
                .chartXAxisLabel("行", alignment: .trailing)
                .frame(height: 220)
            }
        }
        .card()
    }
}

private func yDomain(_ v: [Double]) -> ClosedRange<Double> {
    let lo = v.min() ?? 0, hi = v.max() ?? 1
    let pad = max(10, (hi - lo) * 0.12)
    return max(0, lo - pad)...(hi + pad)
}

/// 日別の練習時間（棒）
struct DailyBarCard: View {
    let days: [(date: Date, stat: DayStat)]
    @State private var sel: Date?

    var body: some View {
        let cal = Calendar.current
        let picked = sel.flatMap { s in days.first { cal.isDate($0.date, inSameDayAs: s) } }
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "日別の練習時間", subtitle: "打鍵していた時間（分）")
            Chart {
                ForEach(days, id: \.date) { d in
                    BarMark(x: .value("日", d.date, unit: .day), y: .value("分", d.stat.activeSec / 60))
                        .cornerRadius(4)
                        .foregroundStyle(VZ.time.opacity(picked == nil || cal.isDate(d.date, inSameDayAs: picked!.date) ? 1 : 0.45))
                }
                if let p = picked {
                    RuleMark(x: .value("日", p.date, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Tooltip(lines: [
                                p.date.formatted(.dateTime.month().day().weekday()),
                                "練習 \(formatDuration(p.stat.activeSec))",
                                "打鍵 \(p.stat.keys)  /  \(p.stat.lines) 行",
                            ])
                        }
                }
            }
            .chartXSelection(value: $sel)
            .chartXAxis { dayAxis(days.count) }
            .chartYAxis { axisStyle() }
            .frame(height: 180)
        }
        .card()
    }
}

/// 日別の値（折れ線）。打っていない日は線を切らずに飛ばす
struct DailyLineCard: View {
    let title: String
    let subtitle: String
    let days: [(date: Date, stat: DayStat)]
    let color: Color
    let unit: String
    let value: (DayStat) -> Double?
    @State private var sel: Date?

    var body: some View {
        let pts = days.compactMap { d in value(d.stat).map { (date: d.date, v: $0, stat: d.stat) } }
        let cal = Calendar.current
        let picked = sel.flatMap { s in pts.first { cal.isDate($0.date, inSameDayAs: s) } }
        let lo = pts.map(\.v).min() ?? 0, hi = pts.map(\.v).max() ?? 1
        let pad = max(1, (hi - lo) * 0.15)
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: title, subtitle: subtitle)
            if pts.isEmpty {
                Text("この期間の記録はありません").font(.system(size: 12)).foregroundColor(VZ.muted)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(pts, id: \.date) { p in
                        LineMark(x: .value("日", p.date, unit: .day), y: .value(unit, p.v))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(color)
                        PointMark(x: .value("日", p.date, unit: .day), y: .value(unit, p.v))
                            .symbolSize(40)
                            .foregroundStyle(color)
                    }
                    if let p = picked {
                        RuleMark(x: .value("日", p.date, unit: .day))
                            .foregroundStyle(VZ.baseline)
                            .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                Tooltip(lines: [
                                    p.date.formatted(.dateTime.month().day().weekday()),
                                    unit == "%" ? String(format: "正確率 %.1f%%", p.v) : "\(Int(p.v)) \(unit)",
                                    "打鍵 \(p.stat.keys)  ミス \(p.stat.misses)",
                                ])
                            }
                    }
                }
                .chartXSelection(value: $sel)
                .chartXScale(domain: (days.first?.date ?? Date())...(cal.date(byAdding: .hour, value: 12, to: days.last?.date ?? Date()) ?? Date()))
                .chartYScale(domain: max(0, lo - pad)...(unit == "%" ? min(100, hi + pad) : hi + pad))
                .chartXAxis { dayAxis(days.count) }
                .chartYAxis { axisStyle() }
                .frame(height: 180)
            }
        }
        .card()
    }
}

private func dayAxis(_ count: Int) -> some AxisContent {
    let step = count <= 10 ? 1 : count <= 35 ? 5 : max(7, count / 6)
    return AxisMarks(values: .stride(by: .day, count: step)) { _ in
        AxisGridLine().foregroundStyle(VZ.grid)
        AxisValueLabel(format: .dateTime.month(.defaultDigits).day()).foregroundStyle(VZ.muted)
    }
}

struct Tooltip: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                Text(l)
                    .font(.system(size: i == 0 ? 10 : 12, weight: i == 1 ? .semibold : .regular))
                    .foregroundColor(i == 0 ? VZ.ink2 : VZ.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(VZ.hex(0x262624)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VZ.border))
        .frame(maxWidth: 260)
    }
}
