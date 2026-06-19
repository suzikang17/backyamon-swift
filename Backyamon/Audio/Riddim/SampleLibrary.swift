import AVFoundation

/// Loads the bundled one-shot kit into mono 44.1k PCM buffers.
final class SampleLibrary {
    enum LibraryError: Error { case missing(String) }

    private var buffers: [InstrumentID: AVAudioPCMBuffer] = [:]

    /// MIDI note each pitched sample was recorded at (its repitch reference).
    /// Drums are absent (played at native pitch). The bass sample (~55 Hz) is
    /// ≈ A1 = MIDI 33; the stab ≈ A3 = 57.
    private let rootNotes: [InstrumentID: Int] = [
        .bass: 33, .organ: 57, .skank: 57, .melodica: 57,
    ]

    private let fileNames: [InstrumentID: String] = [
        .kick: "kick", .snare: "snare", .hat: "hat", .shaker: "shaker",
        .perc: "perc", .bass: "bass", .organ: "organ", .skank: "skank",
        .melodica: "melodica",
    ]

    init() throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        for (id, name) in fileNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                throw LibraryError.missing(name)
            }
            buffers[id] = try Self.loadMono(url: url, format: fmt)
        }
    }

    private var overrideBuffers: [InstrumentID: AVAudioPCMBuffer] = [:]
    private var overrideRoots: [InstrumentID: Int?] = [:]

    /// Replace a voice at runtime. `rootMidiNote == nil` marks a drum (no repitch).
    func setOverride(buffer: AVAudioPCMBuffer, rootMidiNote: Int?, for id: InstrumentID) {
        overrideBuffers[id] = buffer
        overrideRoots[id] = rootMidiNote
    }

    /// Remove a voice override, restoring the bundled default.
    func clearOverride(for id: InstrumentID) {
        overrideBuffers[id] = nil
        overrideRoots[id] = nil
    }

    func buffer(for id: InstrumentID) -> AVAudioPCMBuffer? {
        overrideBuffers[id] ?? buffers[id]
    }
    func rootMidiNote(for id: InstrumentID) -> Int? {
        if let override = overrideRoots[id] { return override }  // membership = overridden (value may be nil)
        return rootNotes[id]
    }

    /// Read a WAV, downmixing to mono and converting to the engine format.
    internal static func loadMono(url: URL, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        // A zero-length source (e.g. a still-open writer whose header has not
        // yet been finalized) would crash AVAudioFile.read with a frameCapacity
        // assertion; return a valid empty buffer in the target format instead.
        guard file.length > 0 else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                     frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw LibraryError.missing(url.lastPathComponent)
        }
        let outCapacity = AVAudioFrameCount(Double(file.length) * format.sampleRate / file.processingFormat.sampleRate) + 64
        let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity)!
        var done = false
        try converter.convert(to: outBuf, error: nil) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true; status.pointee = .haveData; return inBuf
        }
        return outBuf
    }
}
