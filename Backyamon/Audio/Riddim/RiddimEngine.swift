import AVFoundation

/// Sample-based riddim engine: assembles a looped 4-stem groove from the
/// bundled sample kit, voices the chord progression (bass = root, melodic =
/// full chord), runs it through the dub FX chain (tape delay + spring reverb),
/// and renders the result to a playable WAV file. Mono 44.1k (Phase 1).
final class RiddimEngine {
    private let library: SampleLibrary
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat

    private(set) var pattern: RiddimPattern
    private(set) var progression: [Chord]

    init() throws {
        self.library = try SampleLibrary()
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let preset = RiddimPreset.oneDrop
        self.pattern = preset.pattern
        self.progression = preset.progression
    }

    func load(preset: RiddimPreset) {
        pattern = preset.pattern
        progression = preset.progression
    }

    func setProgression(_ chords: [Chord]) { progression = chords }

    /// Mix the full looped pattern into one mono buffer (drums+bass+melodic).
    func renderLoopBuffer() -> AVAudioPCMBuffer {
        let frames = Int(Double(pattern.totalSteps) * pattern.secondsPerStep * sampleRate)
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        out.frameLength = AVAudioFrameCount(frames)
        let dst = out.floatChannelData![0]
        for i in 0..<frames { dst[i] = 0 }

        for id in InstrumentID.allCases {
            for step in pattern.activeSteps(id) {
                let t = pattern.time(ofStep: step)
                let startFrame = Int(t * sampleRate)
                let hit = sampleForHit(id, step: step)
                mix(hit, into: dst, at: startFrame, total: frames, gain: gain(for: id))
            }
        }
        for i in 0..<frames { dst[i] = tanhf(dst[i]) }
        return out
    }

    private func sampleForHit(_ id: InstrumentID, step: Int) -> AVAudioPCMBuffer {
        guard let base = library.buffer(for: id) else { return emptyBuffer() }
        guard library.rootMidiNote(for: id) != nil else { return base }   // drums
        let bar = pattern.bar(ofStep: step)
        let chord = progression[bar % progression.count]
        if id == .bass {
            return repitch(base, semitones: Double(chord.root - 12))
        }
        // Melodic: sum repitched copies for each chord tone.
        return layeredChord(base: base, voicing: chord.voicing())
    }

    private func layeredChord(base: AVAudioPCMBuffer, voicing: [Int]) -> AVAudioPCMBuffer {
        let copies = voicing.map { repitch(base, semitones: Double($0)) }
        let maxLen = copies.map { Int($0.frameLength) }.max() ?? 0
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxLen))!
        out.frameLength = AVAudioFrameCount(maxLen)
        let dst = out.floatChannelData![0]
        for i in 0..<maxLen { dst[i] = 0 }
        let norm = Float(1.0 / Double(max(1, copies.count)))
        for c in copies {
            let s = c.floatChannelData![0]; let n = Int(c.frameLength)
            for i in 0..<n { dst[i] += s[i] * norm }
        }
        return out
    }

    private func gain(for id: InstrumentID) -> Float {
        switch id {
        case .kick: return 1.0
        case .snare: return 0.8
        case .hat: return 0.5
        case .shaker, .perc: return 0.5
        case .bass: return 1.2
        case .organ: return 0.9
        case .skank: return 0.9
        case .melodica: return 0.6
        }
    }

    private func mix(_ src: AVAudioPCMBuffer, into dst: UnsafeMutablePointer<Float>,
                     at start: Int, total: Int, gain: Float) {
        let s = src.floatChannelData![0]; let n = Int(src.frameLength)
        for i in 0..<n {
            let j = start + i
            if j >= 0 && j < total { dst[j] += s[i] * gain }
        }
    }

    private func emptyBuffer() -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!; b.frameLength = 1; return b
    }

    /// Run the assembled loop through the dub FX chain offline (manual rendering),
    /// returning a buffer that includes the reverb/echo tail.
    func renderProcessedLoop(tailSeconds: Double = 1.5) throws -> AVAudioPCMBuffer {
        let source = renderLoopBuffer()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()

        delay.delayTime = (60.0 / pattern.bpm) * 0.75
        delay.feedback = 40
        delay.lowPassCutoff = 2800
        delay.wetDryMix = 28
        reverb.loadFactoryPreset(.largeRoom)
        reverb.wetDryMix = 22

        engine.attach(player); engine.attach(delay); engine.attach(reverb)
        engine.connect(player, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        let total = AVAudioFrameCount(Double(source.frameLength) + tailSeconds * sampleRate)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        player.scheduleBuffer(source, at: nil, options: [], completionHandler: nil)
        player.play()

        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total)!
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        while engine.manualRenderingSampleTime < AVAudioFramePosition(total) {
            let remaining = total - AVAudioFrameCount(engine.manualRenderingSampleTime)
            let toRender = min(chunk.frameCapacity, remaining)
            let status = try engine.renderOffline(toRender, to: chunk)
            guard status == .success || status == .insufficientDataFromInputNode else { break }
            appendBuffer(chunk, to: out)
        }
        engine.stop()
        return out
    }

    /// Render the processed loop, tiled `loops` times, to a WAV file in caches.
    func renderToFile(loops: Int = 1) throws -> URL {
        let one = try renderProcessedLoop()
        let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        let url = dir.appendingPathComponent("riddim-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        for _ in 0..<max(1, loops) { try file.write(from: one) }
        return url
    }

    private func appendBuffer(_ src: AVAudioPCMBuffer, to dst: AVAudioPCMBuffer) {
        let n = Int(src.frameLength); let off = Int(dst.frameLength)
        let s = src.floatChannelData![0]; let d = dst.floatChannelData![0]
        let cap = Int(dst.frameCapacity)
        for i in 0..<n where off + i < cap { d[off + i] = s[i] }
        dst.frameLength = AVAudioFrameCount(min(cap, off + n))
    }
}
