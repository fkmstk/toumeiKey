import AVFoundation

/// タイプ音のプリセット。音源ファイルは使わず、起動時に波形を合成する。
enum SoundPreset: String, CaseIterable, Identifiable {
    case off, thock, clicky, soft, typewriter, pop
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "オフ"
        case .thock: return "コトコト（木）"
        case .clicky: return "カチカチ（青軸風）"
        case .soft: return "スコスコ（静音）"
        case .typewriter: return "タイプライター"
        case .pop: return "ポップ"
        }
    }
}

final class SoundEngine {
    private let engine = AVAudioEngine()
    private let sr: Double = 44100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0

    private var keyBufs: [SoundPreset: [AVAudioPCMBuffer]] = [:]
    private var spaceBufs: [SoundPreset: [AVAudioPCMBuffer]] = [:]
    private var missBuf: AVAudioPCMBuffer!
    private var doneBuf: AVAudioPCMBuffer!
    private var lastIndex = -1

    init() {
        let pitches: [Double] = [0.93, 0.96, 0.98, 1.0, 1.02, 1.04, 1.07]
        for p in SoundPreset.allCases where p != .off {
            keyBufs[p] = pitches.map { synth(p, pitch: $0, length: 1) }
            spaceBufs[p] = [0.76, 0.8].map { synth(p, pitch: $0, length: 1.5) }
        }
        missBuf = makeMiss()
        doneBuf = makeChime()

        for _ in 0..<12 {
            let n = AVAudioPlayerNode()
            engine.attach(n)
            engine.connect(n, to: engine.mainMixerNode, format: format)
            players.append(n)
        }
        // AirPods 接続などで出力先が変わったらエンジンを再始動
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
        restart()
    }

    private func restart() {
        engine.stop()
        try? engine.start()
    }

    // MARK: 再生

    private var preset: SoundPreset {
        UserDefaults.standard.string(forKey: "soundPreset").flatMap(SoundPreset.init) ?? .thock
    }
    private var volume: Float {
        (UserDefaults.standard.object(forKey: "soundVolume") as? Double).map(Float.init) ?? 0.45
    }

    /// pan: -1(左) 〜 1(右)。打った手の側から聞こえるようにする
    func key(space: Bool, pan: Float) {
        let p = preset
        guard p != .off, let bufs = (space ? spaceBufs[p] : keyBufs[p]), !bufs.isEmpty else { return }
        var i = Int.random(in: 0..<bufs.count)
        if i == lastIndex && bufs.count > 1 { i = (i + 1) % bufs.count }   // 同じ音が続かないように
        lastIndex = i
        play(bufs[i], gain: Float.random(in: 0.85...1.0) * Self.presetGain[p, default: 0.6], pan: pan)
    }

    private static let presetGain: [SoundPreset: Float] = [
        .thock: 0.55, .clicky: 0.45, .soft: 0.55, .typewriter: 0.4, .pop: 0.4,
    ]

    func miss() { play(missBuf, gain: 0.35, pan: 0) }
    func lineDone() { play(doneBuf, gain: 0.28, pan: 0) }

    func preview() {
        for (k, d) in [(0, -0.3), (1, 0.3), (2, -0.1), (3, 0.0)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.11) { [weak self] in
                self?.key(space: k == 3, pan: Float(d))
            }
        }
    }

    private func play(_ buf: AVAudioPCMBuffer, gain: Float, pan: Float) {
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let n = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        n.volume = gain * volume
        n.pan = pan
        n.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !n.isPlaying { n.play() }
    }

    // MARK: 合成

    private struct Biquad {
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        static func bandpass(_ f: Double, q: Double, sr: Double) -> Biquad {
            let w = 2 * .pi * f / sr, al = sin(w) / (2 * q), a0 = 1 + al
            return Biquad(b0: al / a0, b1: 0, b2: -al / a0, a1: -2 * cos(w) / a0, a2: (1 - al) / a0)
        }
        static func lowpass(_ f: Double, q: Double = 0.707, sr: Double) -> Biquad {
            let w = 2 * .pi * f / sr, al = sin(w) / (2 * q), c = cos(w), a0 = 1 + al
            return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0)
        }
        mutating func run(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private func noise() -> Double { Double.random(in: -1...1) }
    private func env(_ t: Double, _ tau: Double) -> Double { t < 0 ? 0 : exp(-t / tau) }
    /// 立ち上がり 0.4ms のクリックノイズ防止
    private func attack(_ t: Double) -> Double { min(1, t / 0.0004) }

    private func buffer(_ duration: Double, peak: Double, _ gen: (Double) -> Double) -> AVAudioPCMBuffer {
        let n = Int(duration * sr)
        var data = [Double](repeating: 0, count: n)
        for i in 0..<n { data[i] = gen(Double(i) / sr) }
        // 末尾をフェードアウト
        let fade = min(n, Int(0.008 * sr))
        for i in 0..<fade { data[n - 1 - i] *= Double(i) / Double(fade) }
        let m = data.map(abs).max() ?? 1
        let k = m > 0 ? peak / m : 0
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let ch = buf.floatChannelData![0]
        for i in 0..<n { ch[i] = Float(data[i] * k) }
        return buf
    }

    private func synth(_ preset: SoundPreset, pitch p: Double, length s: Double) -> AVAudioPCMBuffer {
        switch preset {
        case .thock:
            // 小さな木を軽く叩いたような「コトッ」: 木の共鳴2つ + やわらかい底打ち。高域ノイズはほぼ入れない
            var tap = Biquad.lowpass(2200 * p, sr: sr)
            var tone = Biquad.lowpass(2600, sr: sr)
            var phase = 0.0
            return buffer(0.06 * s, peak: 0.55) { t in
                let w1 = sin(2 * .pi * 720 * p * t) * env(t, 0.0045 * s) * 0.55
                let w2 = sin(2 * .pi * 1180 * p * t) * env(t, 0.0028 * s) * 0.28
                let f = 165 * p * (1 + 0.35 * exp(-t / 0.003))
                phase += 2 * .pi * f / sr
                let thump = sin(phase) * env(t, 0.008 * s) * 0.42
                let touch = tap.run(noise()) * env(t, 0.0010) * 0.22
                return tone.run(w1 + w2 + thump + touch) * min(1, t / 0.0008)
            }
        case .clicky:
            // 押下と戻りの2回の「カチッ」
            var bp1 = Biquad.bandpass(4600 * p, q: 2.2, sr: sr)
            var bp2 = Biquad.bandpass(3700 * p, q: 2.0, sr: sr)
            return buffer(0.07 * s, peak: 0.8) { t in
                let c1 = bp1.run(noise()) * env(t, 0.0014) * 1.2
                let ring = sin(2 * .pi * 3150 * p * t) * env(t, 0.004) * 0.25
                let c2 = bp2.run(noise()) * env(t - 0.026 * s, 0.0018) * 0.7
                let body = sin(2 * .pi * 390 * p * t) * env(t, 0.007) * 0.3
                return (c1 + ring + c2 + body) * attack(t)
            }
        case .soft:
            // こもった「スコッ」
            var lp = Biquad.lowpass(1300 * p, sr: sr)
            return buffer(0.07 * s, peak: 0.7) { t in
                let thud = lp.run(noise()) * env(t, 0.0075 * s) * 0.8
                let body = sin(2 * .pi * 150 * p * t) * env(t, 0.012 * s) * 0.4
                return (thud + body) * attack(t)
            }
        case .typewriter:
            // 金属的な「カシャッ」
            var bp = Biquad.bandpass(2300 * p, q: 0.8, sr: sr)
            return buffer(0.16 * s, peak: 0.85) { t in
                let strike = bp.run(noise()) * env(t, 0.003) * 1.2
                let metal = (sin(2 * .pi * 1760 * p * t) * 0.2 + sin(2 * .pi * 2940 * p * t) * 0.13) * env(t, 0.028 * s)
                let thump = sin(2 * .pi * 120 * p * t) * env(t, 0.02) * 0.45
                return (strike + metal + thump) * attack(t)
            }
        case .pop:
            // 泡がはじけるような「ポッ」
            var phase = 0.0
            return buffer(0.07 * s, peak: 0.7) { t in
                let f = (340 + 900 * (1 - exp(-t / 0.009))) * p / s
                phase += 2 * .pi * f / sr
                return sin(phase) * min(1, t / 0.001) * env(t, 0.018 * s)
            }
        case .off:
            return buffer(0.01, peak: 0) { _ in 0 }
        }
    }

    /// ミス: 控えめな「ブッ」
    private func makeMiss() -> AVAudioPCMBuffer {
        buffer(0.12, peak: 0.6) { t in
            let x = sin(2 * .pi * 155 * t) + 0.5 * sin(2 * .pi * 310 * t)
            return tanh(2.2 * x) * min(1, t / 0.002) * env(t, 0.045)
        }
    }

    /// 行クリア: 2音のチャイム
    private func makeChime() -> AVAudioPCMBuffer {
        buffer(0.5, peak: 0.6) { t in
            func note(_ f: Double, _ t0: Double) -> Double {
                let u = t - t0
                guard u >= 0 else { return 0 }
                return (sin(2 * .pi * f * u) + 0.18 * sin(4 * .pi * f * u)) * min(1, u / 0.003) * env(u, 0.16)
            }
            return note(1318.5, 0) + note(1760, 0.07)
        }
    }
}
