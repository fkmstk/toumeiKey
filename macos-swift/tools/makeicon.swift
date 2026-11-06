// アプリアイコン (AppIcon.icns) を生成する: swift tools/makeicon.swift <出力先.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.32, alpha: 1),
                        NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1)])!.draw(in: path, angle: -90)

    // 半透明のガラス板
    let glass = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.1, dy: s * 0.2).offsetBy(dx: 0, dy: s * 0.1),
                             xRadius: s * 0.06, yRadius: s * 0.06)
    NSColor(white: 1, alpha: 0.12).setFill(); glass.fill()
    NSColor(white: 1, alpha: 0.35).setStroke(); glass.lineWidth = max(1, s * 0.008); glass.stroke()

    // キー
    let colors: [NSColor] = [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple]
    let kw = s * 0.075, gap = s * 0.018
    let total = CGFloat(colors.count) * kw + CGFloat(colors.count - 1) * gap
    var x = (s - total) / 2
    for (i, c) in colors.enumerated() {
        let r = NSRect(x: x, y: s * 0.22, width: kw, height: kw)
        let k = NSBezierPath(roundedRect: r, xRadius: kw * 0.22, yRadius: kw * 0.22)
        (i == 3 ? c : c.withAlphaComponent(0.55)).setFill(); k.fill()
        x += kw + gap
    }

    // カーソル
    let caret = NSRect(x: s * 0.5 - s * 0.012, y: s * 0.45, width: s * 0.024, height: s * 0.22)
    NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).setFill()
    NSBezierPath(roundedRect: caret, xRadius: s * 0.01, yRadius: s * 0.01).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
