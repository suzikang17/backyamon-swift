import Foundation
import AVFoundation

/// Downloads a user/community sample, converts it to the engine's mono 44.1k
/// format, and installs it as a per-voice override on a SampleLibrary. The
/// download is injected so the conversion path is unit-testable; the live
/// initializer uses URLSession with an on-disk URL-keyed cache.
@MainActor
final class RiddimVoiceLoader {
    private let library: SampleLibrary
    private let download: (URL) async throws -> Data

    init(library: SampleLibrary, download: @escaping (URL) async throws -> Data) {
        self.library = library
        self.download = download
    }

    /// Live wiring: cache-then-network download.
    static func live(library: SampleLibrary) -> RiddimVoiceLoader {
        RiddimVoiceLoader(library: library) { url in
            let cache = try cacheURL(for: url)
            if let cached = try? Data(contentsOf: cache) { return cached }
            let (data, _) = try await URLSession.shared.data(from: url)
            try? data.write(to: cache)
            return data
        }
    }

    /// Download, convert, and install the override. Awaits completion so the
    /// override is in place before any pull-based render.
    func setVoice(url: URL, rootMidiNote: Int?, for id: InstrumentID) async throws {
        let data = try await download(url)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("riddim-voice-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension.isEmpty ? "wav" : url.pathExtension)
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = try SampleLibrary.loadMono(url: tmp, format: fmt)
        library.setOverride(buffer: buffer, rootMidiNote: rootMidiNote, for: id)
    }

    /// Restore the bundled default for a voice.
    func clearVoice(_ id: InstrumentID) {
        library.clearOverride(for: id)
    }

    /// Default repitch root for a pitched voice; nil for drums.
    static func defaultRoot(for id: InstrumentID) -> Int? {
        switch id {
        case .bass: return 33
        case .organ, .skank, .melodica: return 57
        default: return nil
        }
    }

    private static func cacheURL(for url: URL) throws -> URL {
        let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("backyamon-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Derive a STABLE filename from the URL (String.hashValue is randomized
        // per process, so it never hits across launches). Percent-encoding to
        // the alphanumerics set keeps the filename filesystem-safe.
        let key = url.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "voice"
        return dir.appendingPathComponent("voice-\(key)").appendingPathExtension("dat")
    }
}
