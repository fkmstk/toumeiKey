import AppKit
import SwiftUI

/// フォントの組み合わせプリセット。インストールされていないフォントは自動でフォールバックする。
enum FontTheme: String, CaseIterable, Identifiable {
    case modern, round, textbook, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .modern: return "モダン"
        case .round: return "まるっと"
        case .textbook: return "教科書"
        case .system: return "システム"
        }
    }

    /// (日本語の表示用ファミリー, 太さ NSFontManager 0-15)
    private var jpFamily: (String, Int) {
        switch self {
        case .modern: return ("Hiragino Sans", 8)
        case .round: return ("Hiragino Maru Gothic ProN", 5)
        case .textbook: return ("Klee", 9)
        case .system: return ("", 0)
        }
    }

    private var monoFamilies: [String] {
        switch self {
        case .modern, .round:
            return ["JetBrains Mono", "JetBrainsMono Nerd Font Mono", "JetBrainsMono Nerd Font", "Fira Code", "SF Mono", "Menlo"]
        case .textbook: return ["Menlo", "Monaco"]
        case .system: return []
        }
    }

    private static func nsFont(family: String, weight: Int, size: CGFloat) -> NSFont? {
        guard !family.isEmpty else { return nil }
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: weight, size: size)
    }

    /// 漢字かな交じりの見出し・かな表示
    func jp(_ size: CGFloat, bold: Bool = true) -> Font {
        let (fam, w) = jpFamily
        if let f = Self.nsFont(family: fam, weight: bold ? w : max(3, w - 3), size: size) { return Font(f) }
        return .system(size: size, weight: bold ? .bold : .regular, design: self == .round ? .rounded : .default)
    }

    /// ローマ字・英文（等幅）
    func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        for fam in monoFamilies {
            if let f = Self.nsFont(family: fam, weight: bold ? 9 : 6, size: size) { return Font(f) }
        }
        return .system(size: size, weight: bold ? .bold : .medium, design: .monospaced)
    }

    /// 統計などの小さな文字
    func ui(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .semibold : .regular, design: self == .round ? .rounded : .default)
    }
}
