import Foundation
import AVFoundation

/// Game sound effects. Mirrors the web app's SFXName set.
enum GameSound {
    case diceRoll
    case pieceMove
    case pieceHit
    case bearOff
    case victory
    case defeat
    case doubleOffered
    case yaMon
    case turnStart
}

/// Singleton audio manager.
///
/// Synthesizes all 9 SFX procedurally via AVAudioEngine — no audio files.
/// Each `play(_:)` call schedules a freshly-built PCM buffer on a player node
/// (transient nodes are attached/detached per shot so multiple sounds can overlap).
@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()

    @Published var isMuted: Bool = false

    private let engine = AVAudioEngine()
    private let mixer: AVAudioMixerNode
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private var started = false

    // Custom (user-equipped) audio buffers indexed by GameSound slot. When a
    // buffer is present here, `play(_:)` uses it instead of the procedural
    // synthesis path.
    private var customSFXBuffers: [GameSound: AVAudioPCMBuffer] = [:]

    // Background music player (for an equipped custom track).
    private var musicPlayer: AVAudioPlayer?

    private init() {
        self.mixer = engine.mainMixerNode
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        configureSession()
        startEngine()
    }

    // MARK: - Engine lifecycle

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        #endif
    }

    private func startEngine() {
        guard !started else { return }
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    // MARK: - Public API

    func toggleMute() {
        isMuted.toggle()
    }

    func play(_ sound: GameSound) {
        guard !isMuted else { return }
        if !started { startEngine() }
        guard started else { return }

        // Prefer a user-equipped custom buffer when one is loaded for this slot.
        if let custom = customSFXBuffers[sound] {
            playBuffer(custom)
            return
        }

        let buffer: AVAudioPCMBuffer
        switch sound {
        case .diceRoll:      buffer = makeShaker()
        case .pieceMove:     buffer = makeWoodKnock()
        case .pieceHit:      buffer = make808Boom()
        case .bearOff:       buffer = makeSteelDrum()
        case .victory:       buffer = makeHornStab()
        case .defeat:        buffer = makeDefeat()
        case .doubleOffered: buffer = makeDubSiren()
        case .yaMon:         buffer = makeVocalAh()
        case .turnStart:     buffer = makeRimshot()
        }

        playBuffer(buffer)
    }

    // MARK: - Custom assets (web parity: loadCustomSFX / loadCustomMusic)

    /// Download an audio file from `url` and assign it to a `GameSound` slot.
    /// Subsequent `play(_:)` calls for that slot will use the custom buffer.
    /// Errors are swallowed silently — the synthesised fallback continues to
    /// work if a download or decode fails.
    func loadCustomSFX(slot: GameSound, url: URL) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let cachedURL = try Self.cache(downloadedURL: tempURL, key: url.absoluteString)
                let file = try AVAudioFile(forReading: cachedURL)
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)
                ) else { return }
                try file.read(into: buffer)
                await MainActor.run {
                    self.customSFXBuffers[slot] = buffer
                }
            } catch {
                // Ignore — synthetic SFX remains available.
            }
        }
    }

    /// Download music from `url` and queue it for looped playback. Replaces
    /// any previously-loaded custom music. Music does not auto-start; call
    /// `playCustomMusic()` to begin playback.
    func loadCustomMusic(url: URL) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let cachedURL = try Self.cache(downloadedURL: tempURL, key: url.absoluteString)
                let player = try AVAudioPlayer(contentsOf: cachedURL)
                player.numberOfLoops = -1
                player.volume = 0.4
                player.prepareToPlay()
                await MainActor.run {
                    self.musicPlayer?.stop()
                    self.musicPlayer = player
                }
            } catch {
                // Ignore — procedural music remains available.
            }
        }
    }

    /// Load a *local* audio file (e.g. a freshly-rendered riddim) for looped
    /// playback. Unlike `loadCustomMusic(url:)` this does no network download.
    func loadCustomMusic(fileURL: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.numberOfLoops = -1
            player.volume = 0.4
            player.prepareToPlay()
            self.musicPlayer?.stop()
            self.musicPlayer = player
        } catch {
            // Ignore — procedural music remains available.
        }
    }

    /// Clear any custom SFX bound to `slot`.
    func clearCustomSFX(slot: GameSound) {
        customSFXBuffers[slot] = nil
    }

    /// Clear all custom SFX buffers.
    func clearAllCustomSFX() {
        customSFXBuffers.removeAll()
    }

    /// Start the currently-loaded custom music track, if any. No-op otherwise.
    func playCustomMusic() {
        guard let player = musicPlayer else { return }
        if !player.isPlaying {
            player.play()
        }
    }

    /// Stop the custom music track, if playing.
    func stopCustomMusic() {
        musicPlayer?.stop()
    }

    /// Drop any previously-loaded custom music.
    func clearCustomMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
    }

    /// Cache a downloaded file in the app's Caches directory keyed by a hash
    /// of the source URL so repeat downloads reuse the same on-disk path.
    nonisolated private static func cache(downloadedURL temp: URL, key: String) throws -> URL {
        let fm = FileManager.default
        let cacheDir = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("backyamon-audio", isDirectory: true)
        if !fm.fileExists(atPath: cacheDir.path) {
            try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        // Use a stable filename derived from the URL so repeat downloads land
        // on the same path. `addingPercentEncoding` keeps the filename safe.
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "asset"
        let dest = cacheDir.appendingPathComponent(safe)
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: dest)
        }
        try fm.moveItem(at: temp, to: dest)
        return dest
    }

    // MARK: - Playback

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: mixer, format: buffer.format)
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                player.stop()
                self.engine.disconnectNodeOutput(player)
                self.engine.detach(player)
            }
        }
        player.play()
    }

    // MARK: - Buffer builders

    private func makeBuffer(seconds: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) { ptr[i] = 0 }
        return buffer
    }

    // MARK: Helpers

    /// Add a single oscillator with an exponential pitch sweep and exponential
    /// amplitude decay into `buffer`, starting at `startTime` for `duration`.
    private func addOsc(into buffer: AVAudioPCMBuffer,
                        startTime: Double,
                        duration: Double,
                        freqStart: Double,
                        freqEnd: Double,
                        amp: Float,
                        wave: Waveform = .sine) {
        let ptr = buffer.floatChannelData![0]
        let total = Int(buffer.frameLength)
        let startIdx = max(0, Int(startTime * sampleRate))
        let durFrames = Int(duration * sampleRate)
        let endIdx = min(total, startIdx + durFrames)
        guard startIdx < endIdx else { return }

        var phase: Double = 0
        let lnFreqStart = log(max(1e-3, freqStart))
        let lnFreqEnd = log(max(1e-3, freqEnd))

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / Double(max(1, endIdx - startIdx))
            let f = exp(lnFreqStart + (lnFreqEnd - lnFreqStart) * t)
            // Exponential amplitude decay (matches Web Audio exponentialRampToValueAtTime).
            let env = Float(pow(0.001, t))
            phase += 2.0 * .pi * f / sampleRate
            if phase > 2.0 * .pi { phase -= 2.0 * .pi }
            let sample: Float
            switch wave {
            case .sine:     sample = Float(sin(phase))
            case .triangle: sample = Float(triangleWave(phase))
            case .square:   sample = phase < .pi ? 1.0 : -1.0
            case .sawtooth: sample = Float((phase / .pi) - 1.0)
            }
            ptr[i] += sample * amp * env
        }
    }

    /// Add filtered white noise (one-pole highpass/lowpass) with exponential decay.
    private func addNoise(into buffer: AVAudioPCMBuffer,
                          startTime: Double,
                          duration: Double,
                          amp: Float,
                          filter: NoiseFilter = .none) {
        let ptr = buffer.floatChannelData![0]
        let total = Int(buffer.frameLength)
        let startIdx = max(0, Int(startTime * sampleRate))
        let durFrames = Int(duration * sampleRate)
        let endIdx = min(total, startIdx + durFrames)
        guard startIdx < endIdx else { return }

        var prev: Float = 0
        let coef: Float
        switch filter {
        case .none:           coef = 0
        case .lowpass(let c): coef = c
        case .highpass(let c): coef = c
        }

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / Double(max(1, endIdx - startIdx))
            let env = Float(pow(0.001, t))
            let white = Float.random(in: -1...1)
            let sample: Float
            switch filter {
            case .none:
                sample = white
            case .lowpass:
                prev = prev + coef * (white - prev)
                sample = prev
            case .highpass:
                let lp = prev + coef * (white - prev)
                prev = lp
                sample = white - lp
            }
            ptr[i] += sample * amp * env
        }
    }

    /// Add a band-passed buzz (sawtooth) -> resonant filter for steel-drum / formant work.
    private func addFormantBuzz(into buffer: AVAudioPCMBuffer,
                                startTime: Double,
                                duration: Double,
                                fundamental: Double,
                                formants: [(freq: Double, gain: Float)],
                                amp: Float) {
        let ptr = buffer.floatChannelData![0]
        let total = Int(buffer.frameLength)
        let startIdx = max(0, Int(startTime * sampleRate))
        let durFrames = Int(duration * sampleRate)
        let endIdx = min(total, startIdx + durFrames)
        guard startIdx < endIdx else { return }

        var phase: Double = 0
        // Resonator state for each formant (simple 2-pole bandpass).
        var states = formants.map { _ in (z1: 0.0, z2: 0.0) }
        let bws: [Double] = formants.map { _ in 80.0 } // bandwidth Hz

        for i in startIdx..<endIdx {
            let t = Double(i - startIdx) / Double(max(1, endIdx - startIdx))
            let env = Float(pow(0.001, t))
            phase += 2.0 * .pi * fundamental / sampleRate
            if phase > 2.0 * .pi { phase -= 2.0 * .pi }
            // Sawtooth source
            let src = (phase / .pi) - 1.0

            var out: Double = 0
            for (idx, f) in formants.enumerated() {
                let omega = 2.0 * .pi * f.freq / sampleRate
                let r = exp(-.pi * bws[idx] / sampleRate)
                let c1 = 2.0 * r * cos(omega)
                let c2 = -r * r
                let y = src + c1 * states[idx].z1 + c2 * states[idx].z2
                states[idx].z2 = states[idx].z1
                states[idx].z1 = y
                out += y * Double(f.gain)
            }

            ptr[i] += Float(out) * amp * env
        }
    }

    private func triangleWave(_ phase: Double) -> Double {
        // Phase in [0, 2π) -> triangle in [-1, 1]
        let p = phase / (2.0 * .pi)
        return 2.0 * abs(2.0 * (p - floor(p + 0.5))) - 1.0
    }

    private enum Waveform { case sine, triangle, square, sawtooth }
    private enum NoiseFilter {
        case none
        case lowpass(Float)   // coefficient 0..1
        case highpass(Float)
    }

    // MARK: - Sound recipes

    /// Shaker rattle: 3 staggered noise grains + low body thump.
    private func makeShaker() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.18)
        for i in 0..<3 {
            let start = Double(i) * 0.03
            addNoise(into: buf, startTime: start, duration: 0.06, amp: 0.35,
                     filter: .highpass(0.4))
        }
        addOsc(into: buf, startTime: 0, duration: 0.08,
               freqStart: 180, freqEnd: 80, amp: 0.25, wave: .sine)
        return buf
    }

    /// Woody knock: highpassed noise click + resonant low triangle body.
    private func makeWoodKnock() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.1)
        addNoise(into: buf, startTime: 0, duration: 0.015, amp: 0.3,
                 filter: .highpass(0.6))
        addOsc(into: buf, startTime: 0, duration: 0.06,
               freqStart: 280, freqEnd: 180, amp: 0.25, wave: .triangle)
        return buf
    }

    /// 808 boom: deep sine with steep pitch drop + square click.
    private func make808Boom() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.4)
        addOsc(into: buf, startTime: 0, duration: 0.35,
               freqStart: 160, freqEnd: 40, amp: 0.55, wave: .sine)
        addOsc(into: buf, startTime: 0, duration: 0.01,
               freqStart: 800, freqEnd: 800, amp: 0.18, wave: .square)
        return buf
    }

    /// Steel drum ting: five inharmonic sine partials + brief attack click.
    private func makeSteelDrum() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.7)
        let partials: [(Double, Float, Double)] = [
            // (freq Hz, relative gain, duration)
            (523, 0.30, 0.40),
            (659, 0.15, 0.36),
            (1047, 0.10, 0.32),
            (1318, 0.075, 0.28),
            (1568, 0.060, 0.24),
        ]
        for p in partials {
            addOsc(into: buf, startTime: 0, duration: p.2,
                   freqStart: p.0, freqEnd: p.0, amp: p.1, wave: .sine)
        }
        addNoise(into: buf, startTime: 0, duration: 0.008, amp: 0.2,
                 filter: .highpass(0.5))
        return buf
    }

    /// Reggae horn stab: detuned sawtooth major chord (C-E-G) + echo.
    private func makeHornStab() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 1.0)
        let notes: [Double] = [523, 659, 784] // C5, E5, G5
        // Primary stab
        for f in notes {
            addOsc(into: buf, startTime: 0, duration: 0.8,
                   freqStart: f * 0.997, freqEnd: f * 0.997,
                   amp: 0.12, wave: .sawtooth)
            addOsc(into: buf, startTime: 0, duration: 0.8,
                   freqStart: f * 1.003, freqEnd: f * 1.003,
                   amp: 0.12, wave: .sawtooth)
        }
        // Echo
        for f in notes {
            addOsc(into: buf, startTime: 0.15, duration: 0.5,
                   freqStart: f, freqEnd: f, amp: 0.06, wave: .sawtooth)
        }
        return buf
    }

    /// Descending minor arpeggio Eb5 -> C5 -> Ab4 on triangles.
    private func makeDefeat() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.9)
        let notes: [Double] = [622, 523, 415]
        for (i, f) in notes.enumerated() {
            addOsc(into: buf, startTime: Double(i) * 0.2, duration: 0.35,
                   freqStart: f, freqEnd: f, amp: 0.25, wave: .triangle)
        }
        return buf
    }

    /// Dub siren: sweep 400->900->400 Hz with echo.
    private func makeDubSiren() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.6)
        // Rise then fall — two sweeps stitched together
        addOsc(into: buf, startTime: 0, duration: 0.2,
               freqStart: 400, freqEnd: 900, amp: 0.15, wave: .sawtooth)
        addOsc(into: buf, startTime: 0.2, duration: 0.2,
               freqStart: 900, freqEnd: 400, amp: 0.15, wave: .sawtooth)
        // Echo
        addOsc(into: buf, startTime: 0.15, duration: 0.2,
               freqStart: 400, freqEnd: 700, amp: 0.07, wave: .sawtooth)
        return buf
    }

    /// Vocal "ah" formant — sawtooth buzz through three resonant formants.
    private func makeVocalAh() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.5)
        let formants: [(freq: Double, gain: Float)] = [
            (730, 1.0),
            (1090, 0.5),
            (2440, 0.3),
        ]
        addFormantBuzz(into: buf, startTime: 0, duration: 0.45,
                       fundamental: 150,
                       formants: formants,
                       amp: 0.08)
        return buf
    }

    /// Rimshot click: highpassed noise + resonant triangle body at 820 Hz.
    private func makeRimshot() -> AVAudioPCMBuffer {
        let buf = makeBuffer(seconds: 0.08)
        addNoise(into: buf, startTime: 0, duration: 0.005, amp: 0.25,
                 filter: .highpass(0.7))
        addOsc(into: buf, startTime: 0, duration: 0.04,
               freqStart: 820, freqEnd: 820, amp: 0.12, wave: .triangle)
        return buf
    }
}
