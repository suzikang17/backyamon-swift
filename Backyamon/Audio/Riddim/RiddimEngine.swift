import AVFoundation

/// Sample-based riddim engine. This task implements offline buffer assembly;
/// later tasks add chord-voicing depth, FX, and file render.
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
}
