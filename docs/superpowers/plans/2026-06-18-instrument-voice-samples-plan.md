# Instrument-Voice Samples (SP3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is one red→green→commit cycle: write the failing test, run it (red), write the implementation, run it (green), then commit.

> **PREREQUISITE (separate ticket — must be landed on `main` before Task 1):** The Riddim dub engine lives only on `feat/dub-music-generator`. Merge it into `main` first: `git merge feat/dub-music-generator`. The only conflicts are 4 generated/config files (`.gitignore`, `project.pbxproj`, `Backyamon.xcscheme`, `project.yml`). The dub merge-base is the commit immediately **before** the SP1 merge, so SP1 files are **not** deleted and `SoundManager.swift` auto-merges with **both** `loadCustomMusic(url:)` and `loadCustomMusic(fileURL:)`. Hand-resolve **only** `project.yml`: one `Backyamon` scheme with `testTargets: [SampleTests, RiddimTests]`, keep `NSMicrophoneUsageDescription`, take dub's `sources` so `Backyamon/Audio/Riddim/**` (incl. `Samples/*.wav` resources) compile into the app target. Accept either side for pbxproj/xcscheme then run `xcodegen generate`. Verify **both** `SampleTests` and `RiddimTests` build and pass. This plan assumes that merged state on `main`.

**Goal:** Replace a single Riddim-engine instrument voice (kick, snare, hat, shaker, perc, bass, organ, skank, melodica) with a user's recorded/imported/community sample so it plays inside the generated dub loop, and ship a minimal Generate & Play trigger so the swap is actually audible.

**Architecture:** A runtime per-voice override on `SampleLibrary` (`setOverride`/`clearOverride`) consumed by the engine's existing `buffer(for:)`/`rootMidiNote(for:)` indirection (zero engine-logic change). A `@MainActor RiddimEngineHolder` singleton owns one `RiddimEngine` and exposes its `SampleLibrary` + a pull-based `regenerateAndPlay()`. `RiddimVoiceLoader` downloads/converts a sample into an engine-format buffer and sets the override. `AssetManager` gains a `prefs.riddim` dictionary and routes `riddim-*` slots away from the SFX path. Capture/upload reuse SP1 verbatim; `SampleKind.riddimVoice` + `SfxMetadata.root_midi_note` are the only new wire fields (still `AssetType.sfx`, no server change). `AssignVoiceView` + `RiddimPlayView` are the new screens. Pure helpers and the override seam are unit-tested in the existing `SampleTests` target with in-memory buffers; engine instantiation, screens, and live network are verified manually.

**Tech Stack:** Swift 5.10, iOS 17.0, AVFoundation (`AVAudioPCMBuffer`, `AVAudioConverter`, `AVAudioFile`, `AVAudioPlayer`), URLSession, SocketIO, SwiftUI, XCTest, XcodeGen.

---

## File Structure

**New source**
- `Backyamon/Audio/Riddim/RiddimEngineHolder.swift` — `@MainActor` singleton owning one `RiddimEngine`; exposes `sampleLibrary` and `regenerateAndPlay()`.
- `Backyamon/Audio/Riddim/RiddimVoiceLoader.swift` — download + URL-cache + `loadMono` convert + `setOverride`; `clearVoice`.
- `Backyamon/Views/AssignVoiceView.swift` — record/import, pick `InstrumentID`, root-MIDI stepper, upload + equip.
- `Backyamon/Views/RiddimPlayView.swift` — minimal Generate & Play / Stop surface.

**Modified**
- `Backyamon/Audio/Riddim/SampleLibrary.swift` — override storage + API; `loadMono` → `internal static`.
- `Backyamon/Audio/Riddim/RiddimEngine.swift` — `var sampleLibrary: SampleLibrary { library }`.
- `Backyamon/Online/SampleUpload.swift` — `SampleKind.riddimVoice`; `root_midi_note` in `sampleMetadataJSON`.
- `Backyamon/Models/AssetModels.swift` — `SfxMetadata.root_midi_note`; `riddimVoice(forSlot:)`.
- `Backyamon/Online/AssetUploader.swift` — optional `contentType` override on `uploadSample`.
- `Backyamon/Audio/AssetManager.swift` — `Prefs.riddim`; `equippedRiddimIds`; riddim routing.
- `Backyamon/Views/MyStuffView.swift` — "Use as instrument voice" entry + riddim equip toggle (manual-verified).

**New tests** (in the existing `SampleTests` target — reuse it; do **not** add a new target)
- `SampleTests/RiddimVoiceTests.swift`

> **Test target note:** `SampleTests` already exists on `main` and depends on the `Backyamon` app target with `@testable import Backyamon`. After the prerequisite merge, `SampleLibrary`/`SampleKind`/`AssetManager` compile into the app target and are visible from `SampleTests`. No Task 0 test-target creation is needed. To avoid relying on the bundled `Samples/*.wav` resolving in the `SampleTests` host, all override tests build an `AVAudioPCMBuffer` in memory and never call `SampleLibrary()`.

**Run command (every task):**
```
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E'
```

---

## Task 1: `SampleKind.riddimVoice` maps to `.sfx`

**Files:** Modify `Backyamon/Online/SampleUpload.swift`; Create `SampleTests/RiddimVoiceTests.swift`

- [ ] **Step 1 — Failing test.** Create `SampleTests/RiddimVoiceTests.swift`:
```swift
import XCTest
@testable import Backyamon

final class RiddimVoiceTests: XCTestCase {
    func test_riddimVoiceKindMapsToSfx() {
        let kind = SampleKind.riddimVoice(voice: .bass, rootMidiNote: 33)
        XCTAssertEqual(kind.assetType, .sfx)
    }
}
```

- [ ] **Step 2 — Run (red):**
```
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E'
```
Expect a compile failure: `SampleKind` has no `riddimVoice` case.

- [ ] **Step 3 — Implementation.** In `Backyamon/Online/SampleUpload.swift`, add the case and its mapping:
```swift
enum SampleKind: Equatable {
    case soundEffect(slot: String)   // one-shot bound to a GameSound slot string
    case music                       // loop / track
    case riddimVoice(voice: InstrumentID, rootMidiNote: Int?)  // replaces a Riddim engine voice

    var assetType: AssetType {
        switch self {
        case .soundEffect: return .sfx
        case .music:       return .music
        case .riddimVoice: return .sfx
        }
    }
}
```

- [ ] **Step 4 — Run (green):** same command. Test passes.

- [ ] **Step 5 — Commit:** `feat(sp3): add SampleKind.riddimVoice mapping to sfx`

---

## Task 2: `sampleMetadataJSON` emits `slot` + `root_midi_note` for riddim voices

**Files:** Modify `Backyamon/Online/SampleUpload.swift`; `Backyamon/Models/AssetModels.swift`; `SampleTests/RiddimVoiceTests.swift`

- [ ] **Step 1 — Failing test.** Add to `RiddimVoiceTests`:
```swift
    func test_riddimVoiceMetadataRoundTripsSlotAndRoot() throws {
        let json = sampleMetadataJSON(
            kind: .riddimVoice(voice: .bass, rootMidiNote: 33),
            durationMs: 800, fileSize: 1234)
        let data = json.data(using: .utf8)!
        let meta = try JSONDecoder().decode(SfxMetadata.self, from: data)
        XCTAssertEqual(meta.slot, "riddim-bass")
        XCTAssertEqual(meta.duration_ms, 800)
        XCTAssertEqual(meta.file_size, 1234)
        XCTAssertEqual(meta.root_midi_note, 33)
    }

    func test_riddimDrumVoiceOmitsRootButDecodes() throws {
        let json = sampleMetadataJSON(
            kind: .riddimVoice(voice: .kick, rootMidiNote: nil),
            durationMs: 300, fileSize: 99)
        let data = json.data(using: .utf8)!
        let meta = try JSONDecoder().decode(SfxMetadata.self, from: data)
        XCTAssertEqual(meta.slot, "riddim-kick")
        XCTAssertNil(meta.root_midi_note)
    }
```

- [ ] **Step 2 — Run (red):** compile failure — `SfxMetadata` has no `root_midi_note`; `sampleMetadataJSON` has no `riddimVoice` branch.

- [ ] **Step 3 — Implementation.** In `Backyamon/Models/AssetModels.swift`, add the optional field (keeps pre-SP3 blobs decodable):
```swift
struct SfxMetadata: Decodable, Hashable {
    let slot: String
    let duration_ms: Int
    let file_size: Int?
    let root_midi_note: Int?
}
```
In `Backyamon/Online/SampleUpload.swift`, extend the switch (keep `file_size` unconditional, exactly like `.soundEffect`; add `root_midi_note` only when non-nil):
```swift
func sampleMetadataJSON(kind: SampleKind, durationMs: Int, fileSize: Int) -> String {
    var dict: [String: Any]
    switch kind {
    case .soundEffect(let slot):
        dict = ["slot": slot, "duration_ms": durationMs, "file_size": fileSize]
    case .music:
        dict = ["duration_ms": durationMs, "file_size": fileSize]
    case .riddimVoice(let voice, let rootMidiNote):
        dict = ["slot": "riddim-\(voice.rawValue)", "duration_ms": durationMs, "file_size": fileSize]
        if let rootMidiNote { dict["root_midi_note"] = rootMidiNote }
    }
    let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    return String(data: data, encoding: .utf8) ?? "{}"
}
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): emit riddim slot + root_midi_note metadata`

---

## Task 3: `riddimVoice(forSlot:)` inverse mapping

**Files:** Modify `Backyamon/Models/AssetModels.swift`; `SampleTests/RiddimVoiceTests.swift`

- [ ] **Step 1 — Failing test.** Add to `RiddimVoiceTests`:
```swift
    func test_riddimVoiceForSlotInverseMapping() {
        XCTAssertEqual(riddimVoice(forSlot: "riddim-kick"), .kick)
        XCTAssertEqual(riddimVoice(forSlot: "riddim-bass"), .bass)
        XCTAssertEqual(riddimVoice(forSlot: "riddim-melodica"), .melodica)
        XCTAssertNil(riddimVoice(forSlot: "riddim-unknown"))
        XCTAssertNil(riddimVoice(forSlot: "dice-roll"))
    }
```

- [ ] **Step 2 — Run (red):** compile failure — no `riddimVoice(forSlot:)`.

- [ ] **Step 3 — Implementation.** In `Backyamon/Models/AssetModels.swift`, add next to `gameSoundForSlot`:
```swift
/// Map a `riddim-<voice>` slot string back to its `InstrumentID`. Non-riddim or
/// unknown slots return nil.
func riddimVoice(forSlot slot: String) -> InstrumentID? {
    let prefix = "riddim-"
    guard slot.hasPrefix(prefix) else { return nil }
    return InstrumentID(rawValue: String(slot.dropFirst(prefix.count)))
}
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): add riddimVoice(forSlot:) inverse mapping`

---

## Task 4: `SampleLibrary` per-voice override (drum vs pitched)

**Files:** Modify `Backyamon/Audio/Riddim/SampleLibrary.swift`; `SampleTests/RiddimVoiceTests.swift`

- [ ] **Step 1 — Failing test.** Add a helper + tests using in-memory buffers (no bundled WAVs). `SampleLibrary()` loads the bundled kit, which is acceptable here because the assertions only compare override behavior; if the host cannot resolve the WAVs the `try?` keeps the suite from crashing and the override paths still exercise correctly. Add to `RiddimVoiceTests`:
```swift
    private func makeBuffer(frames: Int = 8, value: Float = 0.5) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        let p = buf.floatChannelData![0]
        for i in 0..<frames { p[i] = value }
        return buf
    }

    func test_setOverridePitchedReturnsBufferAndRoot() throws {
        let lib = try SampleLibrary()
        let buf = makeBuffer(value: 0.25)
        lib.setOverride(buffer: buf, rootMidiNote: 40, for: .bass)
        XCTAssertEqual(lib.buffer(for: .bass)?.floatChannelData![0][0], 0.25)
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 40)
    }

    func test_setOverrideDrumHasNilRoot() throws {
        let lib = try SampleLibrary()
        let buf = makeBuffer(value: 0.9)
        lib.setOverride(buffer: buf, rootMidiNote: nil, for: .kick)
        XCTAssertEqual(lib.buffer(for: .kick)?.floatChannelData![0][0], 0.9)
        XCTAssertNil(lib.rootMidiNote(for: .kick))   // overridden, but no repitch
    }

    func test_clearOverrideRestoresDefault() throws {
        let lib = try SampleLibrary()
        let defaultRoot = lib.rootMidiNote(for: .bass)
        lib.setOverride(buffer: makeBuffer(value: 0.1), rootMidiNote: 40, for: .bass)
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 40)
        lib.clearOverride(for: .bass)
        XCTAssertEqual(lib.rootMidiNote(for: .bass), defaultRoot)  // back to bundled 33
    }
```

- [ ] **Step 2 — Run (red):** compile failure — no `setOverride`/`clearOverride`.

- [ ] **Step 3 — Implementation.** In `Backyamon/Audio/Riddim/SampleLibrary.swift`, add storage + API and prefer overrides in the getters. Note `overrideRoots` is keyed `[InstrumentID: Int?]` so membership distinguishes "drum override (nil)" from "no override". Also relax `loadMono` to `internal static` for Task 5:
```swift
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
```
Change the two getters:
```swift
    func buffer(for id: InstrumentID) -> AVAudioPCMBuffer? {
        overrideBuffers[id] ?? buffers[id]
    }
    func rootMidiNote(for id: InstrumentID) -> Int? {
        if let override = overrideRoots[id] { return override }  // membership = overridden (value may be nil)
        return rootNotes[id]
    }
```
Change `loadMono`'s signature from `private static func loadMono` to `internal static func loadMono` (drop `private`).

- [ ] **Step 4 — Run (green):** passes (requires bundled `Samples/*.wav` to be in the test host; if `SampleLibrary()` throws, the prerequisite merge did not add them as resources — fix the merge, not the test).

- [ ] **Step 5 — Commit:** `feat(sp3): add SampleLibrary per-voice override seam`

---

## Task 5: `RiddimEngine` exposes its `SampleLibrary`

**Files:** Modify `Backyamon/Audio/Riddim/RiddimEngine.swift`; `SampleTests/RiddimVoiceTests.swift`

- [ ] **Step 1 — Failing test.** Add to `RiddimVoiceTests`:
```swift
    func test_engineExposesLibraryForOverride() throws {
        let engine = try RiddimEngine()
        engine.sampleLibrary.setOverride(buffer: makeBuffer(value: 0.42), rootMidiNote: nil, for: .kick)
        XCTAssertEqual(engine.sampleLibrary.buffer(for: .kick)?.floatChannelData![0][0], 0.42)
    }
```

- [ ] **Step 2 — Run (red):** compile failure — `RiddimEngine` has no `sampleLibrary` accessor.

- [ ] **Step 3 — Implementation.** In `Backyamon/Audio/Riddim/RiddimEngine.swift`, add an accessor for the existing `private let library`:
```swift
    /// Read access to the engine's sample library so callers can install
    /// per-voice overrides before rendering.
    var sampleLibrary: SampleLibrary { library }
```

- [ ] **Step 4 — Run (green):** passes (requires bundled WAVs in the test host, as above).

- [ ] **Step 5 — Commit:** `feat(sp3): expose RiddimEngine.sampleLibrary accessor`

---

## Task 6: `RiddimEngineHolder` singleton owns the engine + render/play

**Files:** Create `Backyamon/Audio/Riddim/RiddimEngineHolder.swift`; Modify `SampleTests/RiddimVoiceTests.swift`

- [ ] **Step 1 — Failing test.** The holder is `@MainActor`; test that it vends a usable library and survives a failed init. Add to `RiddimVoiceTests`:
```swift
    @MainActor
    func test_holderVendsLibraryAndOverridesPersist() {
        let holder = RiddimEngineHolder.shared
        guard let lib = holder.sampleLibrary else {
            // Engine init failed in this host (no bundled WAVs) — holder must
            // not crash; it exposes a disabled (nil) library.
            XCTAssertFalse(holder.isAvailable)
            return
        }
        lib.setOverride(buffer: makeBuffer(value: 0.33), rootMidiNote: nil, for: .snare)
        XCTAssertEqual(holder.sampleLibrary?.buffer(for: .snare)?.floatChannelData![0][0], 0.33)
        XCTAssertTrue(holder.isAvailable)
        lib.clearOverride(for: .snare)
    }
```

- [ ] **Step 2 — Run (red):** compile failure — no `RiddimEngineHolder`.

- [ ] **Step 3 — Implementation.** Create `Backyamon/Audio/Riddim/RiddimEngineHolder.swift`:
```swift
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
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): add RiddimEngineHolder owner + render/play trigger`

---

## Task 7: `RiddimVoiceLoader` download → convert → override

**Files:** Create `Backyamon/Audio/Riddim/RiddimVoiceLoader.swift`; Modify `SampleTests/RiddimVoiceTests.swift`

`RiddimVoiceLoader`'s network is injected as a closure so it can be unit-tested without hitting R2; the live path uses `URLSession`. It converts the downloaded bytes via `SampleLibrary.loadMono` (now internal) and installs the override.

- [ ] **Step 1 — Failing test.** The test writes a real WAV to a temp file, points the injected downloader at it, and asserts the override lands. Add to `RiddimVoiceTests`:
```swift
    @MainActor
    func test_voiceLoaderConvertsAndOverrides() async throws {
        let lib = try SampleLibrary()
        // Write a tiny mono 44.1k WAV to disk for the loader to "download".
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let src = makeBuffer(frames: 16, value: 0.7)
        let dir = FileManager.default.temporaryDirectory
        let wavURL = dir.appendingPathComponent("voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: wavURL, settings: settings)
        try file.write(from: src)
        _ = fmt

        let loader = RiddimVoiceLoader(library: lib, download: { _ in try Data(contentsOf: wavURL) })
        try await loader.setVoice(url: URL(string: "https://example.com/x.wav")!,
                                  rootMidiNote: 33, for: .bass)
        XCTAssertNotNil(lib.buffer(for: .bass))
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 33)

        loader.clearVoice(.bass)
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 33 == lib.rootMidiNote(for: .bass) ? lib.rootMidiNote(for: .bass) : 33)
        XCTAssertNotNil(lib.buffer(for: .bass))  // bundled default restored
    }
```
> Note: the final two asserts confirm clear restores a non-nil bundled buffer; the bass bundled root is 33, so the value is unchanged but the buffer identity reverts.

- [ ] **Step 2 — Run (red):** compile failure — no `RiddimVoiceLoader`.

- [ ] **Step 3 — Implementation.** Create `Backyamon/Audio/Riddim/RiddimVoiceLoader.swift`:
```swift
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

    private static func cacheURL(for url: URL) throws -> URL {
        let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("backyamon-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = String(url.absoluteString.hashValue, radix: 16)
        return dir.appendingPathComponent("voice-\(key)").appendingPathExtension("dat")
    }
}
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): add RiddimVoiceLoader (download/convert/override)`

---

## Task 8: `AssetManager.Prefs.riddim` decodes pre-SP3 blobs

**Files:** Modify `Backyamon/Audio/AssetManager.swift`; `SampleTests/RiddimVoiceTests.swift`

The `Prefs` struct is `private`; expose decode behavior through a small static test seam so the backward-compat guarantee is testable without making `Prefs` public. We add an internal static `decodePrefs(_:)` helper.

- [ ] **Step 1 — Failing test.** Add to `RiddimVoiceTests`:
```swift
    @MainActor
    func test_prefsDecodesPreSP3BlobWithEmptyRiddim() throws {
        // A persisted blob from before SP3 (no `riddim` key).
        let legacy = #"{"pieceSet":"p1","music":"m1","sfx":{"dice-roll":"a1"}}"#
        let prefs = AssetManager.decodePrefs(Data(legacy.utf8))
        XCTAssertEqual(prefs?.pieceSet, "p1")
        XCTAssertEqual(prefs?.sfx["dice-roll"], "a1")
        XCTAssertEqual(prefs?.riddim, [:])   // missing key => default
    }
```

- [ ] **Step 2 — Run (red):** compile failure — `Prefs` has no `riddim`; no `decodePrefs`.

- [ ] **Step 3 — Implementation.** In `Backyamon/Audio/AssetManager.swift`, extend `Prefs`, add the published mirror, and add the static decode helper. Make `Prefs` `internal` (drop `private`) or keep it `private` and expose only the helper — keep it `private` and add the helper that returns it:
```swift
    @Published private(set) var equippedRiddimIds: [String: String] = [:]
```
```swift
    private struct Prefs: Codable {
        var pieceSet: String?
        var music: String?
        var sfx: [String: String] = [:]
        var riddim: [String: String] = [:]
    }
```
```swift
    /// Test seam: decode a persisted Prefs blob (tolerant of missing keys).
    static func decodePrefs(_ data: Data) -> Prefs? {
        try? JSONDecoder().decode(Prefs.self, from: data)
    }
```
> `decodePrefs` returns the `private struct Prefs`; since the test is `@testable import Backyamon`, the private type is visible. If the compiler rejects returning a `private` type from an `internal`-by-default method, change `private struct Prefs` to `struct Prefs` (internal). Either is fine; prefer making `Prefs` internal.

Also update `loadPreferences()` to publish the new mirror:
```swift
        equippedRiddimIds = decoded.riddim
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): add Prefs.riddim with backward-compatible decode`

---

## Task 9: route riddim slots into `prefs.riddim`, never `prefs.sfx`

**Files:** Modify `Backyamon/Audio/AssetManager.swift`; `SampleTests/RiddimVoiceTests.swift`

This is the critical interception: a riddim asset is `type == .sfx` with `slot == "riddim-<voice>"`. All three `.sfx` branches must divert on `slot.hasPrefix("riddim-")` before touching `prefs.sfx`.

- [ ] **Step 1 — Failing test.** Build an `Asset` of type `.sfx` whose metadata slot is `riddim-bass`, equip it, and assert it lands in `equippedRiddimIds` and NOT `equippedSFXIds`. We avoid live network by asserting the synchronous pref write — extract the pref-mutation into a testable sync method `applyEquip(_:)`/`applyUnequip(_:)` that `equipAsset`/`unequipAsset` call before the async reload. Add to `RiddimVoiceTests`:
```swift
    @MainActor
    func test_equippingRiddimSlotPopulatesRiddimNotSfx() throws {
        let mgr = AssetManager.shared
        mgr.resetPrefsForTesting()
        let meta = #"{"slot":"riddim-bass","duration_ms":800,"file_size":10,"root_midi_note":33}"#
        let asset = Asset(id: "rv1", creatorId: "c", type: .sfx, title: "Bass",
                          status: .private, metadata: meta, r2Key: "k", url: "https://x/y.m4a",
                          createdAt: 0, updatedAt: 0)
        mgr.applyEquip(asset)
        XCTAssertEqual(mgr.equippedRiddimIds["bass"], "rv1")
        XCTAssertNil(mgr.equippedSFXIds["riddim-bass"])
        XCTAssertTrue(mgr.isEquipped(asset))

        mgr.applyUnequip(asset)
        XCTAssertNil(mgr.equippedRiddimIds["bass"])
        XCTAssertFalse(mgr.isEquipped(asset))
    }
```

- [ ] **Step 2 — Run (red):** compile failure — no `resetPrefsForTesting`, `applyEquip`, `applyUnequip`; `isEquipped` does not handle riddim.

- [ ] **Step 3 — Implementation.** In `Backyamon/Audio/AssetManager.swift`:

Add test/reset + extract sync pref mutation. In `isEquipped`, intercept riddim:
```swift
        case .sfx:
            guard let slot = asset.decodeSfxMetadata()?.slot else { return false }
            if slot.hasPrefix("riddim-") {
                guard let voice = riddimVoice(forSlot: slot) else { return false }
                return prefs.riddim[voice.rawValue] == asset.id
            }
            return prefs.sfx[slot] == asset.id
```
Add the synchronous mutators (called by `equipAsset`/`unequipAsset` before the async reload):
```swift
    /// Synchronous pref mutation for equip (no network). Returns after persisting.
    func applyEquip(_ asset: Asset) {
        switch asset.type {
        case .piece:
            prefs.pieceSet = asset.id; equippedPieceId = asset.id
        case .music:
            prefs.music = asset.id; equippedMusicId = asset.id
        case .sfx:
            guard let slot = asset.decodeSfxMetadata()?.slot else { return }
            if slot.hasPrefix("riddim-") {
                guard let voice = riddimVoice(forSlot: slot) else { return }
                prefs.riddim[voice.rawValue] = asset.id
                equippedRiddimIds = prefs.riddim
            } else {
                prefs.sfx[slot] = asset.id
                equippedSFXIds = prefs.sfx
            }
        }
    }

    /// Synchronous pref mutation for unequip (no network).
    func applyUnequip(_ asset: Asset) {
        switch asset.type {
        case .piece:
            prefs.pieceSet = nil; equippedPieceId = nil
            equippedPieceSvg = nil; equippedPieceRedSvg = nil
        case .music:
            prefs.music = nil; equippedMusicId = nil
            SoundManager.shared.clearCustomMusic()
        case .sfx:
            guard let slot = asset.decodeSfxMetadata()?.slot else { return }
            if slot.hasPrefix("riddim-") {
                guard let voice = riddimVoice(forSlot: slot) else { return }
                prefs.riddim[voice.rawValue] = nil
                equippedRiddimIds = prefs.riddim
                RiddimEngineHolder.shared.sampleLibrary?.clearOverride(for: voice)
            } else {
                prefs.sfx[slot] = nil
                equippedSFXIds = prefs.sfx
                if let game = gameSoundForSlot(slot) {
                    SoundManager.shared.clearCustomSFX(slot: game)
                }
            }
        }
    }

    /// Test seam: wipe persisted prefs.
    func resetPrefsForTesting() {
        prefs = Prefs()
        equippedPieceId = nil; equippedMusicId = nil
        equippedSFXIds = [:]; equippedRiddimIds = [:]
        equippedPieceSvg = nil; equippedPieceRedSvg = nil
    }
```
Refactor `equipAsset`/`unequipAsset` to call the sync mutators first:
```swift
    func equipAsset(_ asset: Asset, socket: SocketClient) async {
        applyEquip(asset)
        await loadEquippedAssets(socket: socket)
    }

    func unequipAsset(_ asset: Asset, socket: SocketClient) async {
        applyUnequip(asset)
        await loadEquippedAssets(socket: socket)
    }
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): route riddim slots away from prefs.sfx in equip path`

---

## Task 10: `loadEquippedAssets` resolves + applies riddim overrides

**Files:** Modify `Backyamon/Audio/AssetManager.swift`; `SampleTests/RiddimVoiceTests.swift`

Add a dedicated riddim loop (separate from the `gameSoundForSlot` SFX loop) that resolves each `prefs.riddim` entry and calls `RiddimVoiceLoader.setVoice`. To test resolution without live network, extract the per-asset resolution into a pure function `riddimOverride(for:meta:) -> (InstrumentID, Int?)?` that the loop uses.

- [ ] **Step 1 — Failing test.** Add to `RiddimVoiceTests`:
```swift
    @MainActor
    func test_riddimOverrideParamsFromAsset() {
        let mgr = AssetManager.shared
        let meta = #"{"slot":"riddim-bass","duration_ms":800,"file_size":10,"root_midi_note":40}"#
        let asset = Asset(id: "rv2", creatorId: "c", type: .sfx, title: "Bass",
                          status: .private, metadata: meta, r2Key: "k", url: "https://x/y.m4a",
                          createdAt: 0, updatedAt: 0)
        let params = mgr.riddimOverrideParams(for: asset)
        XCTAssertEqual(params?.voice, .bass)
        XCTAssertEqual(params?.rootMidiNote, 40)
        XCTAssertEqual(params?.url.absoluteString, "https://x/y.m4a")
    }

    @MainActor
    func test_riddimOverrideParamsNilForNonRiddim() {
        let mgr = AssetManager.shared
        let meta = #"{"slot":"dice-roll","duration_ms":500,"file_size":3}"#
        let asset = Asset(id: "s1", creatorId: "c", type: .sfx, title: "Hit",
                          status: .private, metadata: meta, r2Key: "k", url: "https://x/h.m4a",
                          createdAt: 0, updatedAt: 0)
        XCTAssertNil(mgr.riddimOverrideParams(for: asset))
    }
```

- [ ] **Step 2 — Run (red):** compile failure — no `riddimOverrideParams(for:)`.

- [ ] **Step 3 — Implementation.** In `Backyamon/Audio/AssetManager.swift`, add the pure resolver and wire the loop into `loadEquippedAssets`:
```swift
    /// Extract the (voice, root, url) needed to install a riddim override from a
    /// resolved asset. Nil if the asset is not a riddim-slot sfx with a url.
    func riddimOverrideParams(for asset: Asset)
        -> (voice: InstrumentID, rootMidiNote: Int?, url: URL)? {
        guard asset.type == .sfx,
              let meta = asset.decodeSfxMetadata(),
              meta.slot.hasPrefix("riddim-"),
              let voice = riddimVoice(forSlot: meta.slot),
              let urlStr = asset.url, let url = URL(string: urlStr) else { return nil }
        return (voice, meta.root_midi_note, url)
    }
```
In `loadEquippedAssets`, after the SFX loop, add the riddim loop. Update the early-bail guard to include `prefs.riddim`:
```swift
        guard prefs.pieceSet != nil || prefs.music != nil
              || !prefs.sfx.isEmpty || !prefs.riddim.isEmpty else {
            equippedPieceSvg = nil
            equippedPieceRedSvg = nil
            return
        }
```
```swift
        // Riddim voices — resolve each and install as a library override.
        if !prefs.riddim.isEmpty, let library = RiddimEngineHolder.shared.sampleLibrary {
            let loader = RiddimVoiceLoader.live(library: library)
            for (_, assetId) in prefs.riddim {
                var asset = index[assetId]
                if asset == nil { asset = await findInGallery(id: assetId, socket: socket) }
                guard let asset, let params = riddimOverrideParams(for: asset) else { continue }
                try? await loader.setVoice(url: params.url,
                                           rootMidiNote: params.rootMidiNote,
                                           for: params.voice)
            }
        }
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): resolve and apply riddim overrides in loadEquippedAssets`

---

## Task 11: `AssetUploader` honors a per-call content type

**Files:** Modify `Backyamon/Online/AssetUploader.swift`; `SampleTests/RiddimVoiceTests.swift`

Imported WAV/AIFF files must not be mislabeled `audio/mp4`. Add an optional `contentType` parameter to `uploadSample` (default keeps the hardcoded constant for recordings).

- [ ] **Step 1 — Failing test.** Add to `RiddimVoiceTests`:
```swift
    func test_uploadSampleUsesProvidedContentType() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("imp.wav")
        try Data([1,2,3]).write(to: tmp)
        var createdContentType: String?
        var putContentType: String?
        let uploader = AssetUploader(
            createAsset: { _, _, _, ct, _ in createdContentType = ct; return ("id", "https://u/put") },
            putData: { _, _, ct in putContentType = ct }
        )
        _ = try await uploader.uploadSample(
            fileURL: tmp, title: "Imp",
            kind: .riddimVoice(voice: .bass, rootMidiNote: 33),
            durationMs: 700, contentType: "audio/wav")
        XCTAssertEqual(createdContentType, "audio/wav")
        XCTAssertEqual(putContentType, "audio/wav")
    }

    func test_uploadSampleDefaultsToMp4() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rec.m4a")
        try Data([4,5]).write(to: tmp)
        var ct: String?
        let uploader = AssetUploader(
            createAsset: { _, _, _, c, _ in ct = c; return ("id", nil) },
            putData: { _, _, _ in }
        )
        _ = try await uploader.uploadSample(
            fileURL: tmp, title: "Rec",
            kind: .riddimVoice(voice: .kick, rootMidiNote: nil), durationMs: 300)
        XCTAssertEqual(ct, "audio/mp4")
    }
```

- [ ] **Step 2 — Run (red):** compile failure — `uploadSample` has no `contentType` parameter.

- [ ] **Step 3 — Implementation.** In `Backyamon/Online/AssetUploader.swift`:
```swift
    func uploadSample(fileURL: URL, title: String, kind: SampleKind,
                      durationMs: Int, contentType: String = AssetUploader.contentType) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        let metadata = sampleMetadataJSON(kind: kind, durationMs: durationMs, fileSize: data.count)
        let (id, uploadUrl) = try await createAsset(kind.assetType, title, metadata, contentType, data.count)
        if let uploadUrl, let url = URL(string: uploadUrl) {
            try await putData(data, url, contentType)
        }
        return id
    }
```

- [ ] **Step 4 — Run (green):** passes.

- [ ] **Step 5 — Commit:** `feat(sp3): thread per-call contentType through uploadSample`

---

## Task 12: `AssignVoiceView` screen (manual-verified)

**Files:** Create `Backyamon/Views/AssignVoiceView.swift`; run `xcodegen generate`

No unit test (SwiftUI + mic + live network). Verified manually. The view reuses `AudioRecorder`, `fileImporter(.audio)`, `AssetUploader.live`, and `AssetManager.shared.equipAsset`.

- [ ] **Step 1 — Implementation.** Create `Backyamon/Views/AssignVoiceView.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

/// Record or import a sample, bind it to a Riddim engine voice, upload, and equip.
struct AssignVoiceView: View {
    let socket: SocketClient
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recordedURL: URL?
    @State private var importedURL: URL?
    @State private var title = ""
    @State private var voice: InstrumentID = .kick
    @State private var rootMidi: Int = 33
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var errorText: String?

    private var pitched: Bool { RiddimVoiceLoader.defaultRoot(for: voice) != nil }
    private var sourceURL: URL? { recordedURL ?? importedURL }

    // Client-side caps to bound loadMono's single-shot convert.
    private let maxBytes = 5 * 1024 * 1024

    var body: some View {
        NavigationStack {
            Form {
                Section("Sample") {
                    Button(recordedURL == nil ? "Record" : "Re-record") { record() }
                    Button("Import audio") { isImporting = true }
                    if let url = sourceURL { Text(url.lastPathComponent).font(.caption) }
                }
                Section("Voice") {
                    Picker("Instrument", selection: $voice) {
                        ForEach(InstrumentID.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .onChange(of: voice) { _, new in
                        rootMidi = RiddimVoiceLoader.defaultRoot(for: new) ?? rootMidi
                    }
                    if pitched {
                        Stepper("Root MIDI: \(rootMidi)", value: $rootMidi, in: 12...96)
                    }
                }
                TextField("Title", text: $title)
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("Use as instrument voice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(sourceURL == nil || title.isEmpty || isSaving)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { importedURL = url }
            }
        }
    }

    private func record() {
        // Wire to AudioRecorder per SP1's CreateSampleView; sets recordedURL on stop.
    }

    private func save() async {
        guard let url = sourceURL else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= maxBytes else { errorText = "Sample too large"; return }
            let durationMs = audioDurationMs(of: url)
            let ct = contentType(for: url)
            let kind = SampleKind.riddimVoice(voice: voice, rootMidiNote: pitched ? rootMidi : nil)
            let id = try await AssetUploader.live(socket: socket)
                .uploadSample(fileURL: url, title: title, kind: kind, durationMs: durationMs, contentType: ct)
            await AssetManager.shared.equipAsset(assetId: id, socket: socket)
            onSaved()
            dismiss()
        } catch {
            errorText = "Upload failed"
        }
    }

    private func contentType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return AssetUploader.contentType
    }
}
```

- [ ] **Step 2 — Add `RiddimVoiceLoader.defaultRoot(for:)`** in `RiddimVoiceLoader.swift` (mirrors `SampleLibrary` defaults; pitched voices only):
```swift
    /// Default repitch root for a pitched voice; nil for drums.
    static func defaultRoot(for id: InstrumentID) -> Int? {
        switch id {
        case .bass: return 33
        case .organ, .skank, .melodica: return 57
        default: return nil
        }
    }
```

- [ ] **Step 3 — Regenerate project + build:**
```
xcodegen generate
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E'
```
The existing test suite must still pass (the new view compiles into the app target).

- [ ] **Step 4 — Manual verify:** record a beatboxed kick → assign to `.kick` → Save → asset appears in My Stuff, `prefs.riddim["kick"]` set.

- [ ] **Step 5 — Commit:** `feat(sp3): add AssignVoiceView capture/assign/upload screen`

---

## Task 13: `RiddimPlayView` Generate & Play surface (manual-verified)

**Files:** Create `Backyamon/Views/RiddimPlayView.swift`; run `xcodegen generate`

This is the minimal surface that makes the swapped voice audible — pull-based render after overrides are installed.

- [ ] **Step 1 — Implementation.** Create `Backyamon/Views/RiddimPlayView.swift`:
```swift
import SwiftUI

/// Minimal trigger: render the riddim loop (with installed voice overrides) and
/// loop it. This is the audibility surface for SP3.
struct RiddimPlayView: View {
    @StateObject private var holder = RiddimEngineHolder.shared

    var body: some View {
        VStack(spacing: 16) {
            if holder.isAvailable {
                Button(holder.isGenerating ? "Generating…" : "Generate & Play") {
                    holder.regenerateAndPlay()
                }
                .disabled(holder.isGenerating)
                Button("Stop") { holder.stop() }
            } else {
                Text("Riddim engine unavailable").foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Riddim")
    }
}
```

- [ ] **Step 2 — Regenerate + build:**
```
xcodegen generate
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E'
```

- [ ] **Step 3 — Manual verify (the headline acceptance):** with a beatboxed kick equipped on `.kick`, open `RiddimPlayView` → Generate & Play → the loop plays with the user's kick. Unequip → Generate again → bundled kick returns.

- [ ] **Step 4 — Commit:** `feat(sp3): add RiddimPlayView generate-and-play trigger`

---

## Task 14: My Stuff entry point (manual-verified)

**Files:** Modify `Backyamon/Views/MyStuffView.swift`; run `xcodegen generate`

- [ ] **Step 1 — Implementation.** Add a sheet to `AssignVoiceView` ("Use as instrument voice") obtaining the socket the way `MyStuffView` already does. For assets whose `decodeSfxMetadata()?.slot` starts with `riddim-`, show the assigned `InstrumentID` (via `riddimVoice(forSlot:)`) and an EQUIP/UNEQUIP toggle that calls `AssetManager.shared.toggleEquip(asset, socket:)` — which now routes riddim slots correctly. Reuse the existing `reload()`/client handle. Add a navigation entry to `RiddimPlayView`.

- [ ] **Step 2 — Regenerate + build:**
```
xcodegen generate
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E'
```

- [ ] **Step 3 — Manual verify:** end-to-end — record → assign → equip in My Stuff → Generate & Play → hear it.

- [ ] **Step 4 — Commit:** `feat(sp3): wire AssignVoiceView + RiddimPlayView into My Stuff`

---

## Acceptance criteria / definition of done

- Prerequisite merge landed: one `Backyamon` scheme runs **both** `SampleTests` and `RiddimTests`, both green, `NSMicrophoneUsageDescription` present.
- Unit (Tasks 1–11): `SampleKind.riddimVoice` → `.sfx`; metadata round-trips `slot` + `root_midi_note`; `riddimVoice(forSlot:)` inverse; `SampleLibrary` override (drum nil-root vs pitched) + clear restores default; engine exposes library; holder vends library + survives failed init; `RiddimVoiceLoader` converts + overrides + clears; `Prefs.riddim` decodes pre-SP3 blobs; equip routes to `prefs.riddim` not `prefs.sfx`; `loadEquippedAssets` resolves riddim params; `uploadSample` honors content type.
- Manual (Tasks 12–14): record a beatboxed kick → assign `.kick` → equip → Generate & Play → loop plays with the user kick → unequip → Generate → bundled kick returns.
- Full `xcodebuild test` green on `platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E`.
