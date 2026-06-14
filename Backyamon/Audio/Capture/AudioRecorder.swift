import AVFoundation
import Foundation

/// Records mic audio to a temporary `.m4a` (AAC) file. Mirrors SoundManager's
/// AVAudioSession usage. UI observes `isRecording`.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    nonisolated static let recorderSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    nonisolated static func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-\(UUID().uuidString).m4a")
    }

    /// Request mic permission; completion runs on the main actor.
    func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in done(granted) }
        }
    }

    func start() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        #endif
        let url = Self.makeTempURL()
        do {
            let rec = try AVAudioRecorder(url: url, settings: Self.recorderSettings)
            rec.record()
            recorder = rec
            fileURL = url
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    /// Stop and return the recorded file URL (nil if nothing was recorded).
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        return fileURL
    }
}

/// Duration in milliseconds of an audio file, or 0 if unreadable.
func audioDurationMs(of url: URL) -> Int {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    let seconds = Double(file.length) / file.processingFormat.sampleRate
    return Int(seconds * 1000)
}
