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
    func regenerateAndPlay() async {
        guard let engine else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            // Run the heavy offline render OFF the main actor so the busy state
            // is observable and the UI does not freeze. (A Sendable warning here
            // under Swift 5.10 is acceptable.)
            let url = try await Task.detached { try engine.renderToFile() }.value
            // Audition as a preview so the player's equipped background music is
            // paused (not clobbered) and resumes when they stop / leave.
            SoundManager.shared.playPreview(fileURL: url)
        } catch {
            // Render failed — leave existing audio untouched.
        }
    }

    /// Stop the riddim audition and resume any equipped background music.
    func stop() {
        SoundManager.shared.stopPreview()
    }
}
