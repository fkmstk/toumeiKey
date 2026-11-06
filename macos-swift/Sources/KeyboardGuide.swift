import SwiftUI
import Carbon

/// 指: 0=左小指 1=左薬指 2=左中指 3=左人差し指 4=右人差し指 5=右中指 6=右薬指 7=右小指 8=親指
enum Finger {
    static let names = ["左 小指", "左 薬指", "左 中指", "左 人差し指", "右 人差し指", "右 中指", "右 薬指", "右 小指", "親指"]
    static let colors: [Color] = [
        Color(red: 0.95, green: 0.45, blue: 0.55), Color(red: 0.98, green: 0.65, blue: 0.35),
        Color(red: 0.95, green: 0.85, blue: 0.35), Color(red: 0.45, green: 0.85, blue: 0.50),
        Color(red: 0.40, green: 0.80, blue: 0.85), Color(red: 0.45, green: 0.60, blue: 0.98),
        Color(red: 0.70, green: 0.55, blue: 0.98), Color(red: 0.92, green: 0.50, blue: 0.90),
        Color(white: 0.75),
    ]
}

struct KeyDef: Hashable {
    let normal: String
    let shifted: String
    let finger: Int
    var label: String { normal.count == 1 && normal.first!.isLetter ? normal.uppercased() : normal }
}

enum KeyLayout: String, CaseIterable, Identifiable {
    case auto, jis, us
    var id: String { rawValue }
    var label: String { ["auto": "自動", "jis": "JIS", "us": "US"][rawValue]! }

    var resolved: KeyLayout {
        guard self == .auto else { return self }
        return KBGetLayoutType(Int16(LMGetKbdType())) == UInt32(kKeyboardJIS) ? .jis : .us
    }

    private static let fingerByCol: [[Int]] = [
        [0, 0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7, 7], // 数字段（US は ` から）
        [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7],
        [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7],
        [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7],
    ]

    private static func letters(_ s: String) -> [(String, String)] {
        s.map { (String($0), String($0).uppercased()) }
    }

    private var rawRows: [[(String, String)]] {
        switch resolved {
        case .jis:
            return [
                [("1", "!"), ("2", "\""), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "&"), ("7", "'"), ("8", "("), ("9", ")"), ("0", ""), ("-", "="), ("^", "~"), ("¥", "|")],
                Self.letters("qwertyuiop") + [("@", "`"), ("[", "{")],
                Self.letters("asdfghjkl") + [(";", "+"), (":", "*"), ("]", "}")],
                Self.letters("zxcvbnm") + [(",", "<"), (".", ">"), ("/", "?"), ("_", "_")],
            ]
        default:
            return [
                [("`", "~"), ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "^"), ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"), ("-", "_"), ("=", "+")],
                Self.letters("qwertyuiop") + [("[", "{"), ("]", "}"), ("\\", "|")],
                Self.letters("asdfghjkl") + [(";", ":"), ("'", "\"")],
                Self.letters("zxcvbnm") + [(",", "<"), (".", ">"), ("/", "?")],
            ]
        }
    }

    var rows: [[KeyDef]] {
        let isUS = resolved == .us
        return rawRows.enumerated().map { r, keys in
            keys.enumerated().map { c, k in
                // JIS の数字段は「1」から始まるので指の割り当てを1つずらす
                let col = (r == 0 && !isUS) ? c + 1 : c
                let f = Self.fingerByCol[r][min(col, Self.fingerByCol[r].count - 1)]
                return KeyDef(normal: k.0, shifted: k.1, finger: f)
            }
        }
    }

    /// 文字 → (キー, Shift が必要か)
    func lookup(_ ch: String) -> (KeyDef, Bool)? {
        if ch == " " { return (KeyDef(normal: " ", shifted: " ", finger: 8), false) }
        for row in rows {
            for k in row {
                if k.normal == ch { return (k, false) }
                if k.shifted == ch { return (k, true) }
            }
        }
        return nil
    }
}

struct KeyboardGuide: View {
    let nextKey: String
    let layout: KeyLayout
    var unit: CGFloat = 19

    var body: some View {
        let hit = layout.lookup(nextKey)
        let target = hit?.0
        let needShift = hit?.1 ?? false
        // Shift は打つ指と反対の手で押す
        let shiftLeft = needShift && (target?.finger ?? 0) >= 4
        let shiftRight = needShift && (target?.finger ?? 0) < 4
        let rows = layout.rows
        let indent: [CGFloat] = [0, 0.5, 0.8, 1.3]

        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 2) {
                    if r == 3 {
                        key("⇧", finger: 0, width: unit * 1.1, active: shiftLeft)
                    } else {
                        Spacer().frame(width: unit * indent[r])
                    }
                    ForEach(rows[r], id: \.self) { k in
                        key(k.label, finger: k.finger, width: unit, active: k == target)
                    }
                    if r == 3 { key("⇧", finger: 7, width: unit * 1.4, active: shiftRight) }
                }
            }
            HStack(spacing: 2) {
                Spacer().frame(width: unit * 3.4)
                key("space", finger: 8, width: unit * 5.5, active: target?.finger == 8)
            }
            Text(target.map { Finger.names[$0.finger] + (needShift ? " + Shift" : "") } ?? " ")
                .font(.system(size: 10))
                .foregroundColor(target.map { Finger.colors[$0.finger] } ?? .clear)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .fixedSize()
    }

    private func key(_ label: String, finger: Int, width: CGFloat, active: Bool) -> some View {
        let c = Finger.colors[finger]
        return Text(label)
            .font(.system(size: unit * 0.48, weight: active ? .bold : .regular, design: .monospaced))
            .foregroundColor(active ? .black : .white.opacity(0.75))
            .frame(width: width, height: unit)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(active ? c : c.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(active ? Color.white : c.opacity(0.35), lineWidth: active ? 1.5 : 0.5)
            )
            .scaleEffect(active ? 1.08 : 1)
            .animation(.easeOut(duration: 0.08), value: active)
    }
}
