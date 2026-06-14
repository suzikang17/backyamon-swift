# User Sample Record & Upload (SP1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let players record (mic) or import an audio sample in-app, upload it to their account via the existing server `create-asset` presigned-R2 flow, and have it appear in My Stuff, equippable as a custom SFX or music asset.

**Architecture:** New `Backyamon/Audio/Capture/` (recording) + `Backyamon/Online/` upload units + a `CreateSampleView` screen, plus a `SocketClient.createAsset` RPC against the existing backend contract. Pure helpers (metadata JSON, create-asset payload, ack parsing, upload-request building, uploader orchestration) are unit-tested behind injectable seams; mic capture, the SwiftUI screen, and live network are verified manually.

**Tech Stack:** Swift 5.10, AVFoundation (AVAudioRecorder, AVAudioFile), URLSession, SocketIO, SwiftUI, XCTest, XcodeGen.

---

## File Structure

**New source**
- `Backyamon/Online/SampleUpload.swift` — pure helpers: `SampleKind`, metadata JSON, create-asset payload dict, ack parsing, upload `URLRequest` builder.
- `Backyamon/Online/AssetUploader.swift` — orchestrates create-asset → PUT (injectable closures).
- `Backyamon/Audio/Capture/AudioRecorder.swift` — `AVAudioRecorder` wrapper + permission.
- `Backyamon/Views/CreateSampleView.swift` — capture/name/type screen + view model.

**Modified**
- `project.yml` — add `SampleTests` unit-test target; add `NSMicrophoneUsageDescription`.
- `Backyamon/Models/AssetModels.swift` — add `SocketClient.createAsset(...)` to the existing `SocketClient` asset extension.
- `Backyamon/Views/MyStuffView.swift` — add a “＋ Create Sample” entry point; replace the web-only empty-state copy.

**New tests**
- `SampleTests/SmokeTests.swift`
- `SampleTests/SampleUploadTests.swift`
- `SampleTests/AssetUploaderTests.swift`
- `SampleTests/AudioRecorderTests.swift`

---

## Task 0: Test target + mic permission

**Files:** Modify `project.yml`; Create `SampleTests/SmokeTests.swift`

- [ ] **Step 1: Add the test target + mic permission to `project.yml`**

Add under `targets:` (sibling of `Backyamon:`):
```yaml
  SampleTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: SampleTests
    dependencies:
      - target: Backyamon
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.backyamon.SampleTests
        GENERATE_INFOPLIST_FILE: YES
```
Change the `Backyamon` target's `scheme:` block from `testTargets: []` to:
```yaml
    scheme:
      testTargets:
        - SampleTests
```
Add to the `Backyamon` target's `info.properties:` map (sibling of the existing `CFBundle*` keys):
```yaml
        NSMicrophoneUsageDescription: "Record your own sounds and samples to use in the game."
```

- [ ] **Step 2: Smoke test** — Create `SampleTests/SmokeTests.swift`:
```swift
import XCTest
@testable import Backyamon

final class SmokeTests: XCTestCase {
    func test_smoke() { XCTAssertEqual(2 + 2, 4) }
}
```

- [ ] **Step 3: Regenerate** — Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate` (Expected: `Created project at Backyamon.xcodeproj`).

- [ ] **Step 4: Find a simulator** — Run: `xcrun simctl list devices available | grep "iPhone" | head -1`. Use its full UDID as `<SIM_ID>` below.

- [ ] **Step 5: Run smoke test** — Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:SampleTests/SmokeTests 2>&1 | tail -20` (Expected: `** TEST SUCCEEDED **`).

- [ ] **Step 6: Commit**
```bash
git add project.yml SampleTests/SmokeTests.swift Backyamon.xcodeproj
git commit -m "test: add SampleTests target + mic usage description"
```

---

## Task 1: Pure upload helpers

**Files:** Create `Backyamon/Online/SampleUpload.swift`; Test `SampleTests/SampleUploadTests.swift`

- [ ] **Step 1: Write the failing tests** — Create `SampleTests/SampleUploadTests.swift`:
```swift
import XCTest
@testable import Backyamon

final class SampleUploadTests: XCTestCase {
    func test_soundEffectMetadataRoundTrips() {
        let json = sampleMetadataJSON(kind: .soundEffect(slot: "dice-roll"), durationMs: 1200, fileSize: 4096)
        let asset = Asset(id: "a", creatorId: "c", type: .sfx, title: "t", status: .private,
                          metadata: json, r2Key: nil, url: nil, createdAt: 0, updatedAt: 0)
        let meta = asset.decodeSfxMetadata()
        XCTAssertEqual(meta?.slot, "dice-roll")
        XCTAssertEqual(meta?.duration_ms, 1200)
        XCTAssertEqual(meta?.file_size, 4096)
    }

    func test_musicMetadataRoundTrips() {
        let json = sampleMetadataJSON(kind: .music, durationMs: 8000, fileSize: 9000)
        let asset = Asset(id: "a", creatorId: "c", type: .music, title: "t", status: .private,
                          metadata: json, r2Key: nil, url: nil, createdAt: 0, updatedAt: 0)
        XCTAssertEqual(asset.decodeMusicMetadata()?.duration_ms, 8000)
    }

    func test_assetTypeForKind() {
        XCTAssertEqual(SampleKind.soundEffect(slot: "x").assetType, .sfx)
        XCTAssertEqual(SampleKind.music.assetType, .music)
    }

    func test_createAssetPayloadShape() {
        let p = createAssetPayload(type: .sfx, title: "My Hit", metadata: "{}", contentType: "audio/mp4", fileSize: 1234)
        XCTAssertEqual(p["type"] as? String, "sfx")
        XCTAssertEqual(p["title"] as? String, "My Hit")
        XCTAssertEqual(p["metadata"] as? String, "{}")
        XCTAssertEqual(p["needsUpload"] as? Bool, true)
        XCTAssertEqual(p["contentType"] as? String, "audio/mp4")
        XCTAssertEqual(p["fileSize"] as? Int, 1234)
    }

    func test_parseAckSuccess() throws {
        let r = try parseCreateAssetAck(["id": "abc", "uploadUrl": "https://u/put"])
        XCTAssertEqual(r.id, "abc")
        XCTAssertEqual(r.uploadUrl, "https://u/put")
    }

    func test_parseAckErrorThrows() {
        XCTAssertThrowsError(try parseCreateAssetAck(["error": "nope"]))
    }

    func test_uploadRequestIsPutWithContentType() {
        let req = makeUploadRequest(url: URL(string: "https://u/put")!, contentType: "audio/mp4")
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:SampleTests/SampleUploadTests 2>&1 | tail -20` (Expected: FAIL — symbols not found).

- [ ] **Step 3: Implement** — Create `Backyamon/Online/SampleUpload.swift`:
```swift
import Foundation

/// What a recorded/imported sample becomes when uploaded. Maps to the server's
/// existing `sfx` / `music` asset types (a dedicated `sample` type is future work).
enum SampleKind: Equatable {
    case soundEffect(slot: String)   // one-shot bound to a GameSound slot string
    case music                       // loop / track

    var assetType: AssetType {
        switch self {
        case .soundEffect: return .sfx
        case .music:       return .music
        }
    }
}

/// Build the JSON metadata string the server stores for a sample asset.
/// Shapes match `SfxMetadata` / `MusicMetadata` in AssetModels.swift.
func sampleMetadataJSON(kind: SampleKind, durationMs: Int, fileSize: Int) -> String {
    let dict: [String: Any]
    switch kind {
    case .soundEffect(let slot):
        dict = ["slot": slot, "duration_ms": durationMs, "file_size": fileSize]
    case .music:
        dict = ["duration_ms": durationMs, "file_size": fileSize]
    }
    let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    return String(data: data, encoding: .utf8) ?? "{}"
}

/// Payload dict for the server `create-asset` event (needsUpload always true here).
func createAssetPayload(type: AssetType, title: String, metadata: String,
                        contentType: String, fileSize: Int) -> [String: Any] {
    return [
        "type": type.rawValue,
        "title": title,
        "metadata": metadata,
        "needsUpload": true,
        "contentType": contentType,
        "fileSize": fileSize,
    ]
}

/// Parse the `create-asset` ack: `{id, uploadUrl}` on success or `{error}`.
func parseCreateAssetAck(_ dict: [String: Any]) throws -> (id: String, uploadUrl: String?) {
    if let err = dict["error"] as? String { throw SocketClientError.server(err) }
    guard let id = dict["id"] as? String else { throw SocketClientError.decoding("create-asset") }
    return (id, dict["uploadUrl"] as? String)
}

/// Build the presigned-R2 PUT request (body set by the caller / URLSession upload).
func makeUploadRequest(url: URL, contentType: String) -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = "PUT"
    req.setValue(contentType, forHTTPHeaderField: "Content-Type")
    return req
}
```

- [ ] **Step 4: Run to verify pass** — same command as Step 2 (Expected: `** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**
```bash
git add Backyamon/Online/SampleUpload.swift SampleTests/SampleUploadTests.swift Backyamon.xcodeproj
git commit -m "feat: pure helpers for sample upload (metadata, payload, ack, request)"
```

---

## Task 2: SocketClient.createAsset RPC

**Files:** Modify `Backyamon/Models/AssetModels.swift` (append to the existing `extension SocketClient`)

No new unit test (thin network wrapper over `emitWithAck`, which is verified elsewhere; the payload/ack logic is already tested in Task 1). Verification = compiles + existing SampleTests still pass.

- [ ] **Step 1: Implement** — In `Backyamon/Models/AssetModels.swift`, inside the existing `extension SocketClient { ... }` that defines `listMyAssets`/`deleteAsset`, add:
```swift
    /// Create an asset row on the server and get a presigned upload URL back.
    /// Mirrors the web `/create` flow. Returns the new asset id + optional PUT url.
    func createAsset(type: AssetType, title: String, metadata: String,
                     contentType: String, fileSize: Int) async throws -> (id: String, uploadUrl: String?) {
        let payload = createAssetPayload(type: type, title: title, metadata: metadata,
                                         contentType: contentType, fileSize: fileSize)
        let dict = try await emitWithAck(event: "create-asset", payload: payload)
        return try parseCreateAssetAck(dict)
    }
```

- [ ] **Step 2: Verify build** — Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate && xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:SampleTests 2>&1 | tail -20` (Expected: `** TEST SUCCEEDED **` — it builds the app target + tests).

- [ ] **Step 3: Commit**
```bash
git add Backyamon/Models/AssetModels.swift Backyamon.xcodeproj
git commit -m "feat: SocketClient.createAsset RPC (create-asset + presigned url)"
```

---

## Task 3: AssetUploader orchestration

**Files:** Create `Backyamon/Online/AssetUploader.swift`; Test `SampleTests/AssetUploaderTests.swift`

Injectable closures so orchestration is testable without socket/network.

- [ ] **Step 1: Write the failing tests** — Create `SampleTests/AssetUploaderTests.swift`:
```swift
import XCTest
@testable import Backyamon

final class AssetUploaderTests: XCTestCase {
    func test_uploadCallsCreateThenPutsBytes() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("t.m4a")
        try Data([1,2,3,4]).write(to: tmp)

        var createdType: AssetType?
        var putURL: URL?
        var putBytes: Int?
        let uploader = AssetUploader(
            createAsset: { type, _, _, _, fileSize in
                createdType = type
                XCTAssertEqual(fileSize, 4)
                return ("new-id", "https://u/put")
            },
            putData: { data, url, contentType in
                putURL = url; putBytes = data.count
                XCTAssertEqual(contentType, "audio/mp4")
            }
        )
        let id = try await uploader.uploadSample(
            fileURL: tmp, title: "Hit", kind: .soundEffect(slot: "dice-roll"), durationMs: 500)
        XCTAssertEqual(id, "new-id")
        XCTAssertEqual(createdType, .sfx)
        XCTAssertEqual(putURL?.absoluteString, "https://u/put")
        XCTAssertEqual(putBytes, 4)
    }

    func test_noUploadUrlSkipsPut() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("t2.m4a")
        try Data([9]).write(to: tmp)
        var putCalled = false
        let uploader = AssetUploader(
            createAsset: { _, _, _, _, _ in ("id2", nil) },
            putData: { _, _, _ in putCalled = true }
        )
        let id = try await uploader.uploadSample(fileURL: tmp, title: "X", kind: .music, durationMs: 1000)
        XCTAssertEqual(id, "id2")
        XCTAssertFalse(putCalled)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:SampleTests/AssetUploaderTests 2>&1 | tail -20` (Expected: FAIL — `AssetUploader` not found).

- [ ] **Step 3: Implement** — Create `Backyamon/Online/AssetUploader.swift`:
```swift
import Foundation

/// Orchestrates a single sample upload: create the asset row (presigned url),
/// then PUT the file bytes. Network/socket are injected as closures for testing.
struct AssetUploader {
    /// (type, title, metadata, contentType, fileSize) -> (id, uploadUrl?)
    var createAsset: (AssetType, String, String, String, Int) async throws -> (id: String, uploadUrl: String?)
    /// (data, url, contentType) -> Void  (PUT the bytes)
    var putData: (Data, URL, String) async throws -> Void

    static let contentType = "audio/mp4"

    /// Returns the new asset id. Throws on create or upload failure.
    func uploadSample(fileURL: URL, title: String, kind: SampleKind, durationMs: Int) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        let metadata = sampleMetadataJSON(kind: kind, durationMs: durationMs, fileSize: data.count)
        let (id, uploadUrl) = try await createAsset(kind.assetType, title, metadata, Self.contentType, data.count)
        if let uploadUrl, let url = URL(string: uploadUrl) {
            try await putData(data, url, Self.contentType)
        }
        return id
    }
}

extension AssetUploader {
    /// Production wiring: real socket + URLSession upload.
    static func live(socket: SocketClient) -> AssetUploader {
        AssetUploader(
            createAsset: { type, title, metadata, contentType, fileSize in
                try await socket.createAsset(type: type, title: title, metadata: metadata,
                                             contentType: contentType, fileSize: fileSize)
            },
            putData: { data, url, contentType in
                let req = makeUploadRequest(url: url, contentType: contentType)
                let (_, response) = try await URLSession.shared.upload(for: req, from: data)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw SocketClientError.server("Upload failed")
                }
            }
        )
    }
}
```

- [ ] **Step 4: Run to verify pass** — same command as Step 2 (Expected: `** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**
```bash
git add Backyamon/Online/AssetUploader.swift SampleTests/AssetUploaderTests.swift Backyamon.xcodeproj
git commit -m "feat: AssetUploader (create-asset then presigned PUT)"
```

---

## Task 4: AudioRecorder

**Files:** Create `Backyamon/Audio/Capture/AudioRecorder.swift`; Test `SampleTests/AudioRecorderTests.swift`

Mic capture can't be unit-tested on the simulator, but the recorder *settings* (a pure dict) and the temp-URL scheme can. Test those; the live capture path is manual.

- [ ] **Step 1: Write the failing tests** — Create `SampleTests/AudioRecorderTests.swift`:
```swift
import XCTest
import AVFoundation
@testable import Backyamon

final class AudioRecorderTests: XCTestCase {
    func test_recorderSettingsAreAACMono44k() {
        let s = AudioRecorder.recorderSettings
        XCTAssertEqual(s[AVFormatIDKey] as? UInt32, kAudioFormatMPEG4AAC)
        XCTAssertEqual(s[AVSampleRateKey] as? Double, 44100)
        XCTAssertEqual(s[AVNumberOfChannelsKey] as? Int, 1)
    }

    func test_newTempURLisM4AAndUnique() {
        let a = AudioRecorder.makeTempURL()
        let b = AudioRecorder.makeTempURL()
        XCTAssertEqual(a.pathExtension, "m4a")
        XCTAssertNotEqual(a, b)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:SampleTests/AudioRecorderTests 2>&1 | tail -20` (Expected: FAIL — `AudioRecorder` not found).

- [ ] **Step 3: Implement** — Create `Backyamon/Audio/Capture/AudioRecorder.swift`:
```swift
import AVFoundation
import Foundation

/// Records mic audio to a temporary `.m4a` (AAC) file. Mirrors SoundManager's
/// AVAudioSession usage. UI observes `isRecording`.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    static let recorderSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    static func makeTempURL() -> URL {
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
```

- [ ] **Step 4: Run to verify pass** — same command as Step 2 (Expected: `** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit**
```bash
git add Backyamon/Audio/Capture/AudioRecorder.swift SampleTests/AudioRecorderTests.swift Backyamon.xcodeproj
git commit -m "feat: AudioRecorder (AAC .m4a mic capture) + duration helper"
```

---

## Task 5: CreateSampleView (capture / name / type / save)

**Files:** Create `Backyamon/Views/CreateSampleView.swift`. Verification: builds + manual run (UI + mic + live upload). No unit test (UI + hardware + network).

- [ ] **Step 1: Implement** — Create `Backyamon/Views/CreateSampleView.swift`:
```swift
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Record or import an audio sample, name it, choose what it is, and upload it.
struct CreateSampleView: View {
    /// Pass a connected SocketClient (e.g. from MyStuffViewModel) and a reload hook.
    let socket: SocketClient
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var fileURL: URL?
    @State private var durationMs = 0
    @State private var title = ""
    @State private var isMusic = false
    @State private var slot = "piece-move"
    @State private var showImporter = false
    @State private var busy = false
    @State private var error: String?

    private let slots = ["dice-roll","piece-move","piece-hit","bear-off","victory",
                         "defeat","double-offered","ya-mon","turn-start"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    Button(recorder.isRecording ? "Stop Recording" : "Record") {
                        if recorder.isRecording {
                            fileURL = recorder.stop()
                            if let u = fileURL { durationMs = audioDurationMs(of: u) }
                        } else {
                            recorder.requestPermission { granted in
                                if granted { recorder.start() }
                                else { error = "Microphone access denied. Import a file instead." }
                            }
                        }
                    }
                    Button("Import from Files") { showImporter = true }
                    if let u = fileURL {
                        Text("Loaded: \(u.lastPathComponent) (\(durationMs) ms)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Details") {
                    TextField("Title", text: $title)
                    Toggle("Music loop/track", isOn: $isMusic)
                    if !isMusic {
                        Picker("Sound slot", selection: $slot) {
                            ForEach(slots, id: \.self) { Text($0) }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Create Sample")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(fileURL == nil || title.isEmpty || busy)
                }
                ToolbarItem(placement: .cancelAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { importFile(url) }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
    }

    private func importFile(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let dest = AudioRecorder.makeTempURL().deletingPathExtension()
            .appendingPathExtension(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            fileURL = dest
            durationMs = audioDurationMs(of: dest)
        } catch {
            self.error = "Could not import that file."
        }
    }

    private func save() async {
        guard let url = fileURL else { return }
        busy = true; error = nil
        let kind: SampleKind = isMusic ? .music : .soundEffect(slot: slot)
        do {
            _ = try await AssetUploader.live(socket: socket)
                .uploadSample(fileURL: url, title: title, kind: kind, durationMs: durationMs)
            busy = false
            onSaved()
            dismiss()
        } catch {
            busy = false
            self.error = "Upload failed. Check your connection and try again."
        }
    }
}
```

- [ ] **Step 2: Verify build** — Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate && xcodebuild build -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' 2>&1 | tail -15` (Expected: `** BUILD SUCCEEDED **`).

- [ ] **Step 3: Commit**
```bash
git add Backyamon/Views/CreateSampleView.swift Backyamon.xcodeproj
git commit -m "feat: CreateSampleView (record/import, name, type, upload)"
```

---

## Task 6: My Stuff entry point

**Files:** Modify `Backyamon/Views/MyStuffView.swift`. Verification: builds + manual run.

- [ ] **Step 1: Add the sheet state + presentation** — In `MyStuffView` (the `struct MyStuffView: View`), add a state property near `@State private var showGallery = false` (around line 12):
```swift
    @State private var showCreate = false
```
Then add this modifier next to the existing `.navigationDestination(isPresented: $showGallery)` (around line 63):
```swift
        .sheet(isPresented: $showCreate) {
            CreateSampleView(socket: vm.client) {
                Task { await vm.reload() }
            }
        }
```

- [ ] **Step 2: Replace the web-only empty-state copy** — In `private var emptyState` (around line 192-205), replace the body so it offers in-app creation. Change the existing `Text("Create assets on the web at backyamon.com/create — they'll show up here.")` block to:
```swift
            Text("Record or import your own samples to use in the game.")
                .font(Theme.serif(12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                showCreate = true
            } label: {
                Text("＋ CREATE SAMPLE")
                    .font(Theme.serifBold(12)).tracking(2)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Theme.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.top, 6)
```

- [ ] **Step 3: Add a header "＋" action always available** — In `private var header` (around line 91), so users can create even when the list is non-empty, wrap or augment as follows: add this `.overlay` to the `header`'s outermost `VStack` (after its `.padding(.bottom, 12)`):
```swift
        .overlay(alignment: .topTrailing) {
            Button { showCreate = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.gold)
                    .padding(.trailing, 16)
            }
            .accessibilityLabel("Create sample")
        }
```

- [ ] **Step 4: Verify build** — Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate && xcodebuild build -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' 2>&1 | tail -15` (Expected: `** BUILD SUCCEEDED **`).

- [ ] **Step 5: Full suite** — Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=<SIM_ID>' -only-testing:SampleTests 2>&1 | tail -20` (Expected: `** TEST SUCCEEDED **`).

- [ ] **Step 6: Manual verification** — On a simulator/device: open My Stuff → ＋ → record (grant mic) or import → name it → pick SFX slot or Music → Save. Confirm it uploads (no error) and appears in the My Stuff list after reload, and can be equipped.

- [ ] **Step 7: Commit**
```bash
git add Backyamon/Views/MyStuffView.swift Backyamon.xcodeproj
git commit -m "feat: My Stuff entry point for creating samples in-app"
```

---

## Self-Review

**Spec coverage (SP1):**
- Record (mic) → Task 4 (`AudioRecorder`). Import from Files → Task 5 (`.fileImporter`). ✓
- Upload via existing `create-asset` + presigned PUT → Tasks 2 (`createAsset`) + 3 (`AssetUploader`). ✓
- Reuse `sfx`/`music` types + metadata → Task 1 (`SampleKind`, `sampleMetadataJSON`). ✓
- Appears in My Stuff + equip → Task 6 (entry point + `vm.reload()`); equipping uses existing `AssetManager` (unchanged). ✓
- Mic permission → Task 0 (`NSMicrophoneUsageDescription`). ✓
- Errors/permission fallbacks → Task 5 (denied → import; upload failure surfaced). ✓
- Testable seams → Tasks 1, 3, 4 unit tests; UI/mic/network manual (Tasks 5, 6). ✓

**Deferred (per spec):** community browsing (SP2), instrument-voice samples (SP3), trimming, dedicated `sample` type, orphan cleanup.

**Placeholder scan:** none — every code step has complete code; commands have expected output.

**Type consistency:** `SampleKind` (`.soundEffect(slot:)`, `.music`, `.assetType`), `sampleMetadataJSON(kind:durationMs:fileSize:)`, `createAssetPayload(type:title:metadata:contentType:fileSize:)`, `parseCreateAssetAck(_)->(id,uploadUrl)`, `makeUploadRequest(url:contentType:)`, `SocketClient.createAsset(type:title:metadata:contentType:fileSize:)`, `AssetUploader(createAsset:putData:)` + `.uploadSample(fileURL:title:kind:durationMs:)` + `.live(socket:)`, `AudioRecorder.recorderSettings/.makeTempURL()/.start()/.stop()`, `audioDurationMs(of:)`, `CreateSampleView(socket:onSaved:)` — consistent across tasks. `MyStuffViewModel.client` and `.reload()` exist (used by Task 6).

**Known risks:** `AVAudioApplication.requestRecordPermission` is iOS 17+ (deployment target is 17.0 — OK); `URLSession.upload(for:from:)` is iOS 15+ (OK). First build of Tasks 5–6 is the SwiftUI integration checkpoint.
