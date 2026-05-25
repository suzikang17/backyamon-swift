import Foundation
import AVFoundation

/// Music style — one per difficulty tier.
enum MusicStyle {
    case roots       // easy / Beach Bum
    case dub         // medium / Selector
    case dancehall   // hard / King Tubby
}

/// Reactive mood that crossfades stem volumes.
enum MusicMood {
    case chill
    case moving
    case tension
    case climax
}

/// Procedural reggae music engine.
///
/// Ports the web MusicEngine to AVFoundation. Generates four looping
/// stems (kick, snare/rim, bass, skank) as 4-bar PCM buffers and mixes
/// them based on mood. One AVAudioPlayerNode per stem, all wired to a
/// dedicated AVAudioEngine so the existing SoundManager remains untouched.
@MainActor
final class MusicEngine: ObservableObject {
    static let shared = MusicEngine()

    @Published var isMusicEnabled: Bool = false

    private let engine = AVAudioEngine()
    private let kickPlayer = AVAudioPlayerNode()
    private let snarePlayer = AVAudioPlayerNode()
    private let bassPlayer = AVAudioPlayerNode()
    private let skankPlayer = AVAudioPlayerNode()

    private let kickMixer = AVAudioMixerNode()
    private let snareMixer = AVAudioMixerNode()
    private let bassMixer = AVAudioMixerNode()
    private let skankMixer = AVAudioMixerNode()

    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat

    private var engineStarted = false
    private var isPlaying = false
    private var currentStyle: MusicStyle = .dub
    private var currentMood: MusicMood = .chill

    // MARK: - Init

    private init() {
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        configureSession()
        buildGraph()
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        #endif
    }

    private func buildGraph() {
        let mixer = engine.mainMixerNode
        let pairs: [(AVAudioPlayerNode, AVAudioMixerNode)] = [
            (kickPlayer, kickMixer),
            (snarePlayer, snareMixer),
            (bassPlayer, bassMixer),
            (skankPlayer, skankMixer),
        ]
        for (player, stemMixer) in pairs {
            engine.attach(player)
            engine.attach(stemMixer)
            engine.connect(player, to: stemMixer, format: format)
            engine.connect(stemMixer, to: mixer, format: format)
            stemMixer.outputVolume = 0
        }
        mixer.outputVolume = 0.5
    }

    private func startEngineIfNeeded() {
        guard !engineStarted else { return }
        do {
            try engine.start()
            engineStarted = true
        } catch {
            engineStarted = false
        }
    }

    // MARK: - Public API

    func start(style: MusicStyle, difficulty: Difficulty) {
        // Reconcile style with difficulty in case caller passed mismatched values.
        let resolved: MusicStyle
        switch difficulty {
        case .beachBum: resolved = .roots
        case .selector: resolved = .dub
        case .kingTubby: resolved = .dancehall
        }
        currentStyle = resolved

        startEngineIfNeeded()
        guard engineStarted else { return }

        // Stop any prior loops.
        stopPlayers()

        let preset = Self.preset(for: currentStyle)

        let kickBuf = makeKickLoop(preset: preset)
        let snareBuf = makeSnareLoop(preset: preset)
        let bassBuf = makeBassLoop(preset: preset)
        let skankBuf = makeSkankLoop(preset: preset)

        scheduleLoop(kickPlayer, buffer: kickBuf)
        scheduleLoop(snarePlayer, buffer: snareBuf)
        scheduleLoop(bassPlayer, buffer: bassBuf)
        scheduleLoop(skankPlayer, buffer: skankBuf)

        kickPlayer.play()
        snarePlayer.play()
        bassPlayer.play()
        skankPlayer.play()

        isPlaying = true
        isMusicEnabled = true
        applyMood(currentMood)
    }

    func stop() {
        stopPlayers()
        isPlaying = false
        isMusicEnabled = false
    }

    func setMood(_ mood: MusicMood) {
        currentMood = mood
        applyMood(mood)
    }

    /// Compute mood from the leading player's pip count and apply it.
    /// Leading-pip thresholds: < 15 = climax, < 30 = tension, < 50 = moving, else chill.
    func updateMood(from state: GameState) {
        let mood = Self.derive(from: state)
        setMood(mood)
    }

    /// Toggle music on/off, restarting with the current style if turning on.
    func toggleMusic() {
        if isPlaying {
            stop()
        } else {
            // Restart with the most recent style; default to dub if never started.
            let difficulty: Difficulty
            switch currentStyle {
            case .roots: difficulty = .beachBum
            case .dub: difficulty = .selector
            case .dancehall: difficulty = .kingTubby
            }
            start(style: currentStyle, difficulty: difficulty)
        }
    }

    // MARK: - Internals

    private func stopPlayers() {
        for player in [kickPlayer, snarePlayer, bassPlayer, skankPlayer] {
            if player.isPlaying { player.stop() }
        }
    }

    private func scheduleLoop(_ player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, at: nil, options: [.loops, .interruptsAtLoop], completionHandler: nil)
    }

    private func applyMood(_ mood: MusicMood) {
        guard isPlaying else { return }
        // Stem gains per mood: (kick, snare, bass, skank).
        let gains: (Float, Float, Float, Float)
        switch mood {
        case .chill:   gains = (0.7, 0.0, 0.8, 0.0)
        case .moving:  gains = (0.8, 0.5, 0.9, 0.6)
        case .tension: gains = (0.9, 0.7, 1.0, 0.7)
        case .climax:  gains = (1.0, 0.85, 1.0, 0.85)
        }
        kickMixer.outputVolume = gains.0
        snareMixer.outputVolume = gains.1
        bassMixer.outputVolume = gains.2
        skankMixer.outputVolume = gains.3
    }

    // MARK: - Mood derivation

    private static func derive(from state: GameState) -> MusicMood {
        if state.phase == .gameOver { return .climax }
        let goldPips = pipCount(state: state, for: .gold)
        let redPips = pipCount(state: state, for: .red)
        let leader = min(goldPips, redPips)
        if leader < 15 { return .climax }
        if leader < 30 { return .tension }
        if leader < 50 { return .moving }
        return .chill
    }

    /// Local pip-count to avoid leaning on AI internals. Bar pieces count as 25.
    private static func pipCount(state: GameState, for player: Player) -> Int {
        var pips = 0
        for i in 0..<24 {
            guard let pt = state.points[i], pt.player == player else { continue }
            let dist = player == .gold ? (24 - i) : (i + 1)
            pips += dist * pt.count
        }
        pips += (state.bar[player] ?? 0) * 25
        return pips
    }

    // MARK: - Style presets

    private struct Preset {
        let bpm: Double
        /// 4-bar chord roots, one bass freq per bar.
        let bassRoots: [Double]
        /// Bandpass center for skank stabs.
        let skankBrightness: Double
        /// Kick start frequency (punch).
        let kickPunch: Double
    }

    private static func preset(for style: MusicStyle) -> Preset {
        switch style {
        case .roots:
            return Preset(bpm: 70,
                          bassRoots: [130.81, 174.61, 196.00, 130.81], // C - F - G - C
                          skankBrightness: 1000,
                          kickPunch: 130)
        case .dub:
            return Preset(bpm: 75,
                          bassRoots: [220.00, 146.83, 196.00, 261.63], // Am - Dm - G - C
                          skankBrightness: 1200,
                          kickPunch: 150)
        case .dancehall:
            return Preset(bpm: 82,
                          bassRoots: [220.00, 164.81, 146.83, 329.63], // Am - E - Dm - E4
                          skankBrightness: 1500,
                          kickPunch: 180)
        }
    }

    // MARK: - Loop builders

    /// Duration in seconds for a 4-bar loop at the given BPM.
    private func loopSeconds(bpm: Double) -> Double {
        return (60.0 / bpm) * 4 * 4
    }

    private func makeLoopBuffer(bpm: Double) -> AVAudioPCMBuffer {
        let seconds = loopSeconds(bpm: bpm)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ptr = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ptr[i] = 0 }
        return buf
    }

    /// One-drop kick: beat 3 of every bar (4-on-the-floor's "drop").
    /// In a 4-bar loop at 75 BPM, that's beats 3, 7, 11, 15.
    private func makeKickLoop(preset: Preset) -> AVAudioPCMBuffer {
        let buf = makeLoopBuffer(bpm: preset.bpm)
        let beatSec = 60.0 / preset.bpm
        // Beat indices (0-based) within 16-beat (4-bar) loop where the kick lands.
        let kickBeats: [Int] = [2, 6, 10, 14] // beat 3 of each bar
        for beat in kickBeats {
            let t = Double(beat) * beatSec
            renderKick(into: buf, startTime: t, punch: preset.kickPunch)
        }
        return buf
    }

    /// Rim/snare: beat 3 too (classic one-drop pairs snare with kick) plus a
    /// syncopated ghost rim on the "and" of beat 4 each bar.
    private func makeSnareLoop(preset: Preset) -> AVAudioPCMBuffer {
        let buf = makeLoopBuffer(bpm: preset.bpm)
        let beatSec = 60.0 / preset.bpm
        for bar in 0..<4 {
            let barStart = Double(bar) * 4 * beatSec
            // Main rimshot on beat 3.
            renderRim(into: buf, startTime: barStart + 2 * beatSec, amp: 0.55)
            // Ghost on the "and" of beat 4 (offbeat).
            renderRim(into: buf, startTime: barStart + 3.5 * beatSec, amp: 0.3)
        }
        return buf
    }

    /// Bass: root on beat 1, octave-up on beat 2.5, fifth below on beat 3.
    private func makeBassLoop(preset: Preset) -> AVAudioPCMBuffer {
        let buf = makeLoopBuffer(bpm: preset.bpm)
        let beatSec = 60.0 / preset.bpm
        for bar in 0..<4 {
            let barStart = Double(bar) * 4 * beatSec
            let root = preset.bassRoots[bar]
            renderBass(into: buf, startTime: barStart, freq: root, duration: 0.6)
            renderBass(into: buf, startTime: barStart + 1.5 * beatSec, freq: root * 2, duration: 0.25)
            renderBass(into: buf, startTime: barStart + 2 * beatSec, freq: root * (2.0 / 3.0), duration: 0.45)
        }
        return buf
    }

    /// Skank: chord stabs on every offbeat (the "and" of every beat).
    private func makeSkankLoop(preset: Preset) -> AVAudioPCMBuffer {
        let buf = makeLoopBuffer(bpm: preset.bpm)
        let beatSec = 60.0 / preset.bpm
        for bar in 0..<4 {
            let barStart = Double(bar) * 4 * beatSec
            let root = preset.bassRoots[bar]
            for offbeat in 0..<4 {
                let t = barStart + (Double(offbeat) + 0.5) * beatSec
                renderSkank(into: buf,
                            startTime: t,
                            rootFreq: root,
                            brightness: preset.skankBrightness)
            }
        }
        return buf
    }

    // MARK: - Per-hit renderers

    /// Sine kick with exponential pitch drop (punch → 40Hz) and exponential amp decay.
    private func renderKick(into buf: AVAudioPCMBuffer,
                            startTime: Double,
                            punch: Double) {
        let duration = 0.25
        let ptr = buf.floatChannelData![0]
        let total = Int(buf.frameLength)
        let startIdx = max(0, Int(startTime * sampleRate))
        let durFrames = Int(duration * sampleRate)
        let endIdx = min(total, startIdx + durFrames)
        guard startIdx < endIdx else { return }

        let lnStart = log(punch)
        let lnEnd = log(40.0)
        // Pitch sweep happens over the first 0.12s.
        let sweepFrames = Int(0.12 * sampleRate)
        var phase: Double = 0
        for i in startIdx..<endIdx {
            let n = i - startIdx
            let pitchT = min(1.0, Double(n) / Double(max(1, sweepFrames)))
            let f = exp(lnStart + (lnEnd - lnStart) * pitchT)
            phase += 2.0 * .pi * f / sampleRate
            if phase > 2.0 * .pi { phase -= 2.0 * .pi }
            let ampT = Double(n) / Double(max(1, endIdx - startIdx))
            let env = Float(pow(0.001, ampT))
            ptr[i] += Float(sin(phase)) * 0.85 * env
        }
    }

    /// Rimshot: very brief highpassed noise click + resonant 820Hz triangle body.
    private func renderRim(into buf: AVAudioPCMBuffer,
                           startTime: Double,
                           amp: Float) {
        let ptr = buf.floatChannelData![0]
        let total = Int(buf.frameLength)

        // Noise click — 5ms, simple high-pass via one-pole differentiation.
        let clickDur = 0.005
        let clickStart = max(0, Int(startTime * sampleRate))
        let clickEnd = min(total, clickStart + Int(clickDur * sampleRate))
        var prev: Float = 0
        if clickStart < clickEnd {
            for i in clickStart..<clickEnd {
                let n = i - clickStart
                let t = Double(n) / Double(max(1, clickEnd - clickStart))
                let env = Float(pow(0.001, t))
                let white = Float.random(in: -1...1)
                // One-pole highpass (coef 0.7).
                let lp = prev + 0.7 * (white - prev)
                prev = lp
                let hp = white - lp
                ptr[i] += hp * 0.55 * amp * env
            }
        }

        // Resonant body — triangle at 820 Hz, 40ms.
        let bodyDur = 0.04
        let bodyStart = max(0, Int(startTime * sampleRate))
        let bodyEnd = min(total, bodyStart + Int(bodyDur * sampleRate))
        if bodyStart < bodyEnd {
            var phase: Double = 0
            let f = 820.0
            for i in bodyStart..<bodyEnd {
                let n = i - bodyStart
                let t = Double(n) / Double(max(1, bodyEnd - bodyStart))
                let env = Float(pow(0.001, t))
                phase += 2.0 * .pi * f / sampleRate
                if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                // Triangle from phase.
                let p = phase / (2.0 * .pi)
                let tri = 2.0 * abs(2.0 * (p - floor(p + 0.5))) - 1.0
                ptr[i] += Float(tri) * 0.28 * amp * env
            }
        }
    }

    /// Triangle bass with simple low-pass smoothing (acts as 500Hz lowpass surrogate).
    private func renderBass(into buf: AVAudioPCMBuffer,
                            startTime: Double,
                            freq: Double,
                            duration: Double) {
        let ptr = buf.floatChannelData![0]
        let total = Int(buf.frameLength)
        let startIdx = max(0, Int(startTime * sampleRate))
        let endIdx = min(total, startIdx + Int(duration * sampleRate))
        guard startIdx < endIdx else { return }

        var phase: Double = 0
        var lpState: Float = 0
        let lpCoef: Float = 0.12 // ~ low-pass smoothing
        for i in startIdx..<endIdx {
            let n = i - startIdx
            let t = Double(n) / Double(max(1, endIdx - startIdx))
            let env = Float(pow(0.001, t))
            phase += 2.0 * .pi * freq / sampleRate
            if phase > 2.0 * .pi { phase -= 2.0 * .pi }
            let p = phase / (2.0 * .pi)
            let tri = 2.0 * abs(2.0 * (p - floor(p + 0.5))) - 1.0
            let raw = Float(tri)
            lpState += lpCoef * (raw - lpState)
            ptr[i] += lpState * 0.85 * env
        }
    }

    /// Skank chord stab: three square partials (root×2, ×2.52, ×3) through
    /// a one-pole bandpass surrogate centered around `brightness`.
    private func renderSkank(into buf: AVAudioPCMBuffer,
                             startTime: Double,
                             rootFreq: Double,
                             brightness: Double) {
        let ptr = buf.floatChannelData![0]
        let total = Int(buf.frameLength)
        let duration = 0.06
        let startIdx = max(0, Int(startTime * sampleRate))
        let endIdx = min(total, startIdx + Int(duration * sampleRate))
        guard startIdx < endIdx else { return }

        let partials: [Double] = [rootFreq * 2, rootFreq * 2.52, rootFreq * 3]
        var phases: [Double] = [0, 0, 0]

        // 2-pole bandpass state per channel.
        var z1: Double = 0
        var z2: Double = 0
        let omega = 2.0 * .pi * brightness / sampleRate
        let bw = 220.0
        let r = exp(-Double.pi * bw / sampleRate)
        let c1 = 2.0 * r * cos(omega)
        let c2 = -r * r

        for i in startIdx..<endIdx {
            let n = i - startIdx
            let t = Double(n) / Double(max(1, endIdx - startIdx))
            let env = Float(pow(0.001, t))

            // Sum three squares.
            var src: Double = 0
            for k in 0..<partials.count {
                phases[k] += 2.0 * .pi * partials[k] / sampleRate
                if phases[k] > 2.0 * .pi { phases[k] -= 2.0 * .pi }
                src += phases[k] < .pi ? 1.0 : -1.0
            }
            src /= Double(partials.count)

            let y = src + c1 * z1 + c2 * z2
            z2 = z1
            z1 = y

            ptr[i] += Float(y) * 0.4 * env
        }
    }
}
