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

    func buffer(for id: InstrumentID) -> AVAudioPCMBuffer? { buffers[id] }
    func rootMidiNote(for id: InstrumentID) -> Int? { rootNotes[id] }

    /// Read a WAV, downmixing to mono and converting to the engine format.
    private static func loadMono(url: URL, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
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
