import Foundation
import SwiftUI

/// Owns the single shared `RiddimEngine` for the app so per-voice overrides
/// have one library to mutate and one place to render/play from. The engine's
/// `init()` throws (it loads 9 bundled WAVs); on failure the holder degrades to
/// an unavailable state instead of crashing.
@MainActor
final class RiddimEngineHolder: ObservableObject {
    static let shared = RiddimEngineHolder()

    private let engine: RiddimEngine?

    @Published private(set) var isGenerating = false

    private init() {
        self.engine = try? RiddimEngine()
    }

    /// Whether a working engine exists. False if bundled samples failed to load.
    var isAvailable: Bool { engine != nil }

    /// The shared library callers install overrides on. Nil when unavailable.
    var sampleLibrary: SampleLibrary? { engine?.sampleLibrary }

    /// Render the current loop (with whatever overrides are installed) to a file
    /// and loop it via SoundManager. Pull-based: call after overrides change.
    func regenerateAndPlay() {
        guard let engine else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            let url = try engine.renderToFile()
            SoundManager.shared.loadCustomMusic(fileURL: url)
            SoundManager.shared.playCustomMusic()
        } catch {
            // Render failed — leave existing audio untouched.
        }
    }

    /// Stop the looping riddim playback.
    func stop() {
        SoundManager.shared.clearCustomMusic()
    }
}
