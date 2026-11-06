import Cocoa
import SwiftUI
import Carbon
import UniformTypeIdentifiers
import Combine

// MARK: - 半透明・最前面パネル

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// ウィンドウ背景をドラッグして移動できるようにする
struct DragArea: NSViewRepresentable {
    let menu: () -> NSMenu
    final class V: NSView {
        var provider: (() -> NSMenu)?
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            window?.performDrag(with: event)
        }
        override func menu(for event: NSEvent) -> NSMenu? { provider?() }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.provider = menu; return v }
    func updateNSView(_ v: V, context: Context) { v.provider = menu }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

final class WindowState: ObservableObject {
    @Published var isKey = false
    @Published var toast: String?
    @Published var showSettings = false
    private var toastWork: DispatchWorkItem?

    func show(_ msg: String) {
        toast = msg
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }
}

// MARK: - 画面

struct ContentView: View {
    @ObservedObject var m: TypingModel
    @ObservedObject var win: WindowState
    let actions: AppActions
    @AppStorage("bgOpacity") private var bgOpacity = 0.4
    @AppStorage("textOpacity") private var textOpacity = 0.95
    @AppStorage("fontSize") private var fontSize = 26.0
    @AppStorage("fontTheme") private var fontTheme = FontTheme.modern
    @AppStorage("cursorStyle") private var cursorStyle = CursorStyle.underline
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("keyLayout") private var keyLayout = KeyLayout.auto
    @AppStorage("dimWhenIdle") private var dimWhenIdle = true
    @AppStorage("compact") private var compact = false
    @AppStorage("seenTips") private var seenTips = false
    @State private var hovering = false

    private let doneColor = Color(red: 0.45, green: 0.88, blue: 0.58)

    private func styled(_ parts: (String, String, String), font: Font) -> AttributedString {
        var done = AttributedString(parts.0)
        done.foregroundColor = doneColor.opacity(0.7)
        var cur = AttributedString(parts.1 == " " ? "␣" : parts.1)
        let accent = m.missFlash ? Color(red: 1, green: 0.38, blue: 0.45) : cursorStyle.accent
        switch cursorStyle {
        case .underline:
            cur.foregroundColor = accent
            cur.underlineStyle = Text.LineStyle(pattern: .solid, color: accent)
        case .color:
            cur.foregroundColor = accent
        case .box:
            cur.foregroundColor = .white
            cur.backgroundColor = accent.opacity(m.missFlash ? 0.55 : 0.28)
        }
        var rest = AttributedString(parts.2)
        rest.foregroundColor = .white.opacity(0.88)
        var all = done + cur + rest
        all.font = font
        return all
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            textColumn
            if showKeyboard {
                KeyboardGuide(nextKey: m.nextKey, layout: keyLayout, unit: max(16, min(24, fontSize * 0.72)))
                    .padding(.top, 26)
            }
        }
        .opacity(textOpacity)
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 8 : 12)
        .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)
        .background(DragArea(menu: actions.menu))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(bgOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: m.missFlash || m.doneFlash ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if hovering || win.showSettings { controls.padding(8) }
        }
        .overlay(alignment: .bottomTrailing) {
            if let t = win.toast {
                Text(t)
                    .font(fontTheme.ui(12, bold: true))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.25), value: dimmed)
        .animation(.easeOut(duration: 0.2), value: win.toast)
        .onHover { hovering = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        .onPreferenceChange(HeightKey.self) { h in actions.fitHeight(h) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// フォーカスが外れている間は動画が見やすいように薄くする（マウスを乗せると戻る）
    private var dimmed: Bool { dimWhenIdle && !win.isKey && !hovering && !win.showSettings }

    private var borderColor: Color {
        if m.missFlash { return Color.red.opacity(0.9) }
        if m.doneFlash { return doneColor }
        return Color.white.opacity(win.isKey ? 0.22 : 0.07)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !compact { header }

            if m.showsReading {
                Text(m.sentence.display)
                    .font(fontTheme.jp(fontSize * 0.95))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(styled(m.kanaParts, font: fontTheme.jp(fontSize * 0.58, bold: false)))
                    .lineLimit(2)
            }
            Text(styled(m.romajiParts, font: fontTheme.mono(fontSize)))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            progressBar

            if !compact {
                Text("次: " + m.upcoming.display)
                    .font(fontTheme.jp(fontSize * 0.42, bold: false))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }

            if !seenTips {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundColor(.yellow.opacity(0.85))
                    Text("⌃⌥T でブラウザ ⇄ タイピング切替　右クリックでメニュー　⌘, で設定")
                        .foregroundColor(.white.opacity(0.85))
                    Button("OK") { seenTips = true }
                        .buttonStyle(.borderless)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .font(fontTheme.ui(11))
                .padding(.top, 2)
            } else if !win.isKey {
                HStack(spacing: 5) {
                    Image(systemName: "pause.fill")
                    Text("一時停止中 — クリック or ⌃⌥T で再開")
                }
                .font(fontTheme.ui(11))
                .foregroundColor(.white.opacity(0.6))
            }
        }
        .shadow(color: .black.opacity(0.75), radius: 1.5, x: 0, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(doneColor.opacity(0.8))
                    .frame(width: g.size.width * m.progress)
                    .animation(.easeOut(duration: 0.1), value: m.progress)
            }
        }
        .frame(height: 3)
        .padding(.vertical, 2)
    }

    private var header: some View {
        HStack(spacing: 14) {
            stat("KPM", "\(m.kpm)")
            stat("正確率", String(format: "%.1f%%", m.accuracy))
            stat("ミス", "\(m.misses)")
            if let l = m.lastLineKPM { stat("前の行", "\(l)") }
            stat("ベスト", "\(m.bestKPM)")
            stat("今日", formatDuration(m.analytics.today.activeSec))
            if !m.topWeakKeys.isEmpty {
                stat("苦手", m.topWeakKeys.map { $0 == " " ? "␣" : $0 }.joined(separator: " "))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func stat(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(fontTheme.ui(11)).foregroundColor(.white.opacity(0.5))
            Text(v).font(fontTheme.mono(13, bold: true)).foregroundColor(.white.opacity(0.92))
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $m.mode) {
                ForEach(Mode.allCases.filter { $0 != .custom || !m.customSentences.isEmpty }) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button { actions.openAnalytics() } label: { Image(systemName: "chart.bar.xaxis") }
                .help("統計・分析 (⌘S)")
            Button { win.showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .help("設定 (⌘,)")
                .popover(isPresented: $win.showSettings, arrowEdge: .bottom) {
                    SettingsView(m: m, actions: actions)
                }
            Button { actions.hide() } label: { Image(systemName: "eye.slash") }
                .help("隠す（⌃⌥T かメニューバーで再表示）")
        }
        .buttonStyle(.borderless)
        .foregroundColor(.white.opacity(0.85))
        .controlSize(.small)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

struct SettingsView: View {
    @ObservedObject var m: TypingModel
    let actions: AppActions
    @AppStorage("bgOpacity") private var bgOpacity = 0.4
    @AppStorage("textOpacity") private var textOpacity = 0.95
    @AppStorage("fontSize") private var fontSize = 26.0
    @AppStorage("fontTheme") private var fontTheme = FontTheme.modern
    @AppStorage("cursorStyle") private var cursorStyle = CursorStyle.underline
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("keyLayout") private var keyLayout = KeyLayout.auto
    @AppStorage("autoASCII") private var autoASCII = true
    @AppStorage("soundPreset") private var soundPreset = SoundPreset.thock
    @AppStorage("soundVolume") private var soundVolume = 0.45
    @AppStorage("dimWhenIdle") private var dimWhenIdle = true
    @AppStorage("compact") private var compact = false
    @AppStorage("missSound") private var missSound = true
    @AppStorage("doneSound") private var doneSound = true
    @AppStorage("contentKind") private var contentKind = ContentKind.mix

    var body: some View {
        Form {
            Section("見た目") {
                Picker("フォント", selection: $fontTheme) {
                    ForEach(FontTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("現在位置の表示", selection: $cursorStyle) {
                    ForEach(CursorStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("文字サイズ")
                    Slider(value: $fontSize, in: 16...56, step: 1)
                    Text("\(Int(fontSize))").monospacedDigit().frame(width: 24)
                }
                HStack { Text("背景の濃さ"); Slider(value: $bgOpacity, in: 0...0.95) }
                HStack { Text("全体の濃さ"); Slider(value: $textOpacity, in: 0.2...1) }
                Toggle("タイピングしていない間は薄くする", isOn: $dimWhenIdle)
                Toggle("コンパクト表示（統計と次の文を隠す）", isOn: $compact)
            }
            Section("練習") {
                Picker("出題", selection: $contentKind) {
                    ForEach(ContentKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: contentKind) { m.contentKindChanged() }
                Toggle("キーボードガイドを表示", isOn: $showKeyboard)
                Picker("キー配列", selection: $keyLayout) {
                    ForEach(KeyLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("入力中は英数入力に自動で切り替える", isOn: $autoASCII)
                HStack {
                    Button("ファイルから読み込む…") { actions.openFile() }
                    Button("クリップボードから") { actions.pasteCustom() }
                }
                Text("カスタム文は1行1問。漢字を含む文は「今日は晴れ|きょうははれ」のように | の後に読みを書く。")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("サウンド") {
                Picker("タイプ音", selection: $soundPreset) {
                    ForEach(SoundPreset.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: soundPreset) { actions.previewSound() }
                HStack {
                    Text("音量")
                    Slider(value: $soundVolume, in: 0...1) { editing in
                        if !editing { actions.previewSound() }
                    }
                }
                .disabled(soundPreset == .off)
                Toggle("ミスしたときの音", isOn: $missSound)
                Toggle("行をクリアしたときのチャイム", isOn: $doneSound)
            }
            Section("記録") {
                LabeledContent("今日の練習時間", value: formatDuration(m.analytics.today.activeSec))
                LabeledContent("今日の打鍵数 / 行数", value: "\(m.analytics.today.keys) / \(m.analytics.today.lines)")
                LabeledContent("連続練習", value: "\(m.analytics.streak) 日")
                LabeledContent("ベスト KPM", value: "\(m.bestKPM)")
                HStack {
                    Button("統計・分析を開く…") { actions.openAnalytics() }
                    Button("セッションをリセット") { m.resetSession() }
                    Button("記録を消去") { m.resetRecords() }
                }
            }
            Section("ショートカット") {
                Text("⌃⌥T  タイピング ⇄ ブラウザのフォーカス切替\nEsc  行の最初から / Tab  スキップ\n⌘1 ⌘2 ⌘3  日本語 / English / カスタム\n⌘,  設定 / ⌘S  統計・分析 / ⌘K  コンパクト表示\n⌘V  クリップボード / ⌘O  ファイル\n⌘W  隠す / ⌘Q  終了\n右クリックでメニュー")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 次に打つ文字の強調スタイル
enum CursorStyle: String, CaseIterable, Identifiable {
    case underline, color, box
    var id: String { rawValue }
    var label: String { ["underline": "下線", "color": "文字色", "box": "うすい枠"][rawValue]! }
    var accent: Color { Color(red: 0.45, green: 0.85, blue: 1.0) }
}

/// SwiftUI からアプリ側の操作を呼ぶための窓口
struct AppActions {
    let hide: () -> Void
    let openFile: () -> Void
    let pasteCustom: () -> Void
    let previewSound: () -> Void
    let menu: () -> NSMenu
    let openAnalytics: () -> Void
    let fitHeight: (CGFloat) -> Void
}

// MARK: - アプリ

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let analytics = Analytics()
    lazy var model = TypingModel(analytics: analytics)
    private var analyticsWindow: NSWindow?
    let win = WindowState()
    var panel: OverlayPanel!
    var statusItem: NSStatusItem!
    var monitor: Any?
    var hotKeyRef: EventHotKeyRef?
    private var savedInputSource: TISInputSource?
    let sound = SoundEngine()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 980, height: 210)
        let rect = NSRect(x: screen.midX - size.width / 2, y: screen.minY + 40, width: size.width, height: size.height)

        panel = OverlayPanel(contentRect: rect,
                             styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 420, height: 50)
        panel.setFrameAutosaveName("TypingOverlayPanel")

        let actions = AppActions(
            hide: { [weak self] in self?.hide() },
            openFile: { [weak self] in self?.openFile() },
            pasteCustom: { [weak self] in self?.pasteCustom() },
            previewSound: { [weak self] in self?.sound.preview() },
            menu: { [weak self] in self?.makeMenu(forStatusBar: false) ?? NSMenu() },
            openAnalytics: { [weak self] in self?.openAnalytics() },
            fitHeight: { [weak self] h in self?.fitHeight(h) }
        )
        let host = NSHostingView(rootView: ContentView(m: model, win: win, actions: actions))
        host.sizingOptions = []   // ウィンドウサイズは fitHeight で自前管理する
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host

        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.win.isKey = true
            self?.switchToASCII()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.win.isKey = false
            self?.restoreInputSource()
        }

        model.onEvent = { [weak self] e in
            guard let self else { return }
            let d = UserDefaults.standard
            switch e {
            case .hit(let c):
                self.playKey(c)
            case .lineDone(let c):
                self.playKey(c)
                if d.object(forKey: "doneSound") as? Bool ?? true { self.sound.lineDone() }
            case .miss:
                if d.object(forKey: "missSound") as? Bool ?? true { self.sound.miss() }
            }
        }

        model.$mode.dropFirst().removeDuplicates().sink { [weak self] m in
            self?.win.show("\(m.label) モード")
        }.store(in: &cancellables)

        setupStatusItem()
        setupKeyMonitor()
        registerHotKey()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreInputSource()
        analytics.saveNow()
    }

    // MARK: メニューバー

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Typing Overlay")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in makeMenu(forStatusBar: true).items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    /// 右クリックメニューとメニューバーの共通メニュー
    func makeMenu(forStatusBar: Bool) -> NSMenu {
        let menu = NSMenu()
        let d = UserDefaults.standard
        @discardableResult
        func add(_ title: String, _ sel: Selector, key: String = "", on: Bool = false, enabled: Bool = true, tag: Int = 0, to m: NSMenu? = nil) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: enabled ? sel : nil, keyEquivalent: key)
            it.target = self
            it.state = on ? .on : .off
            it.tag = tag
            (m ?? menu).addItem(it)
            return it
        }
        if forStatusBar {
            add(panel.isVisible ? "タイピング ⇄ ブラウザ切替  ⌃⌥T" : "表示する  ⌃⌥T", #selector(toggleFocus))
            menu.addItem(.separator())
        }
        for (i, mode) in Mode.allCases.enumerated() {
            add(mode.label, #selector(selectMode(_:)), key: "\(i + 1)", on: model.mode == mode,
                enabled: mode != .custom || !model.customSentences.isEmpty, tag: i)
        }
        let kindItem = NSMenuItem(title: "出題", action: nil, keyEquivalent: "")
        let ksub = NSMenu()
        let curKind = d.string(forKey: "contentKind").flatMap(ContentKind.init) ?? .mix
        for (i, k) in ContentKind.allCases.enumerated() {
            add(k.label, #selector(selectKind(_:)), on: k == curKind, tag: i, to: ksub)
        }
        kindItem.submenu = ksub
        menu.addItem(kindItem)
        menu.addItem(.separator())
        add("統計・分析…", #selector(openAnalytics), key: "s")
        add("設定…", #selector(openSettings), key: ",")
        add("コンパクト表示", #selector(toggleCompact), key: "k", on: d.bool(forKey: "compact"))
        add("キーボードガイド", #selector(toggleKeyboard), on: d.object(forKey: "showKeyboard") as? Bool ?? true)

        let soundItem = NSMenuItem(title: "タイプ音", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let cur = d.string(forKey: "soundPreset").flatMap(SoundPreset.init) ?? .thock
        for (i, p) in SoundPreset.allCases.enumerated() {
            add(p.label, #selector(selectSound(_:)), on: p == cur, tag: i, to: sub)
        }
        soundItem.submenu = sub
        menu.addItem(soundItem)

        menu.addItem(.separator())
        add("テキストファイルで練習…", #selector(openFile), key: "o")
        add("クリップボードの文章で練習", #selector(pasteCustom), key: "v")
        menu.addItem(.separator())
        add("位置とサイズをリセット", #selector(resetPosition))
        add("隠す", #selector(hide), key: "w")
        add("終了", #selector(quit), key: "q")
        return menu
    }

    @objc func selectMode(_ sender: NSMenuItem) { setMode(Mode.allCases[sender.tag]) }

    private func setMode(_ mode: Mode) {
        guard mode != .custom || !model.customSentences.isEmpty else {
            win.show("カスタム文がまだありません（⌘V / ⌘O で読み込み）")
            return
        }
        if model.mode != mode { model.mode = mode }
    }

    @objc func selectKind(_ sender: NSMenuItem) {
        let k = ContentKind.allCases[sender.tag]
        UserDefaults.standard.set(k.rawValue, forKey: "contentKind")
        model.contentKindChanged()
        win.show("出題: \(k.label)")
    }

    @objc func openAnalytics() {
        if analyticsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "TypingOverlay — 統計・分析"
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AnalyticsView(a: analytics, exportCSV: { [weak self] in self?.exportCSV() }))
            w.setFrameAutosaveName("TypingOverlayAnalytics")
            if w.frame.origin == .zero { w.center() }
            analyticsWindow = w
        }
        NSApp.activate()
        analyticsWindow?.makeKeyAndOrderFront(nil)
    }

    private func exportCSV() {
        analytics.saveNow()
        let p = NSSavePanel()
        p.allowedContentTypes = [.commaSeparatedText]
        p.nameFieldStringValue = "typing-lines.csv"
        p.message = "行ごとの記録を書き出します（同じ場所にキー別の typing-keys.csv も作ります）"
        guard p.runModal() == .OK, let url = p.url else { return }
        let keysURL = url.deletingLastPathComponent().appendingPathComponent("typing-keys.csv")
        do {
            try analytics.linesCSV().write(to: url, atomically: true, encoding: .utf8)
            try analytics.keysCSV().write(to: keysURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url, keysURL])
        } catch {
            let a = NSAlert(error: error)
            a.runModal()
        }
    }

    @objc func openSettings() {
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.win.showSettings = true }
    }

    @objc func toggleCompact() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "compact"), forKey: "compact")
    }

    @objc func toggleKeyboard() {
        let d = UserDefaults.standard
        d.set(!(d.object(forKey: "showKeyboard") as? Bool ?? true), forKey: "showKeyboard")
    }

    @objc func selectSound(_ sender: NSMenuItem) {
        UserDefaults.standard.set(SoundPreset.allCases[sender.tag].rawValue, forKey: "soundPreset")
        sound.preview()
    }

    /// 内容の高さに合わせてパネルを伸縮（下端を固定して上に伸びる）
    private func fitHeight(_ h: CGFloat) {
        let h = ceil(h)
        guard h > 10 else { return }
        var f = panel.frame
        guard abs(f.height - h) > 0.5 else { return }
        f.size.height = h
        // 画面からはみ出さないように収める
        if let vis = (panel.screen ?? NSScreen.main)?.visibleFrame {
            f.origin.y = min(max(f.origin.y, vis.minY), vis.maxY - f.height)
            f.origin.x = min(max(f.origin.x, vis.minX - f.width + 120), vis.maxX - 120)
        }
        panel.setFrame(f, display: true)
    }

    // MARK: キー入力

    private func setupKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                switch e.charactersIgnoringModifiers?.lowercased() {
                case "q": NSApp.terminate(nil)
                case "w": self.hide()
                case "v": self.pasteCustom()
                case "o": self.openFile()
                case "1": self.setMode(.japanese)
                case "2": self.setMode(.english)
                case "3": self.setMode(.custom)
                case ",": self.openSettings()
                case "s": self.openAnalytics()
                case "k": self.toggleCompact()
                default: return e
                }
                return nil
            }
            if flags.contains(.control) || flags.contains(.option) { return nil }
            switch e.keyCode {
            case 53: self.model.restartLine(); return nil      // Esc: 行の最初から
            case 48: self.model.skip(); return nil             // Tab: スキップ
            default: break
            }
            if let s = e.characters, s.count == 1, let c = s.first, let a = c.asciiValue, a >= 32, a < 127 {
                self.model.type(c)
            }
            return nil
        }
    }

    /// ⌃⌥T: どのアプリからでもタイピング欄にフォーカス／ブラウザに戻す
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.toggleFocus() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5459_504F), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: 入力ソース（IME）

    private func isASCIICapable(_ src: TISInputSource) -> Bool {
        guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsASCIICapable) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
    }

    private func switchToASCII() {
        guard UserDefaults.standard.object(forKey: "autoASCII") as? Bool ?? true else { return }
        let cur = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard !isASCIICapable(cur) else { return }
        savedInputSource = cur
        let ascii = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        TISSelectInputSource(ascii)
    }

    private func restoreInputSource() {
        if let s = savedInputSource {
            TISSelectInputSource(s)
            savedInputSource = nil
        }
    }

    /// 打った指の側（左手なら左）から音が聞こえるようにする
    private func playKey(_ c: Character) {
        let layout = UserDefaults.standard.string(forKey: "keyLayout").flatMap(KeyLayout.init) ?? .auto
        let finger = layout.lookup(String(c))?.0.finger ?? 8
        let pan: Float = finger == 8 ? 0 : (Float(finger) - 3.5) / 3.5 * 0.45
        sound.key(space: c == " ", pan: pan)
    }

    // MARK: 操作

    @objc func toggleFocus() {
        if panel.isVisible && panel.isKeyWindow {
            // キーフォーカスだけ手放して、表示はそのまま
            panel.orderOut(nil)
            if NSApp.isActive { NSApp.deactivate() }
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc func hide() { panel.orderOut(nil) }

    @objc func pasteCustom() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            win.show("クリップボードに文章がありません")
            return
        }
        loadCustom(text)
    }

    @objc func openFile() {
        NSApp.activate()
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText]
        p.allowsMultipleSelection = false
        p.message = "練習用のテキストファイル（1行1問、漢字文は「表示|よみ」）"
        if p.runModal() == .OK, let url = p.url, let text = try? String(contentsOf: url, encoding: .utf8) {
            loadCustom(text)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func loadCustom(_ text: String) {
        let n = model.loadCustom(text)
        win.show(n > 0 ? "\(n) 行を読み込みました" : "練習できる行がありませんでした")
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func resetPosition() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: screen.midX - 490, y: screen.minY + 40, width: 980, height: panel.frame.height), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
