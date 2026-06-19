import XCTest
import AVFoundation
@testable import Backyamon

final class RiddimVoiceTests: XCTestCase {
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

    func test_riddimVoiceKindMapsToSfx() {
        let kind = SampleKind.riddimVoice(voice: .bass, rootMidiNote: 33)
        XCTAssertEqual(kind.assetType, .sfx)
    }

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

    func test_engineExposesLibraryForOverride() throws {
        let engine = try RiddimEngine()
        engine.sampleLibrary.setOverride(buffer: makeBuffer(value: 0.42), rootMidiNote: nil, for: .kick)
        XCTAssertEqual(engine.sampleLibrary.buffer(for: .kick)?.floatChannelData![0][0], 0.42)
    }

    func test_riddimVoiceForSlotInverseMapping() {
        XCTAssertEqual(riddimVoice(forSlot: "riddim-kick"), .kick)
        XCTAssertEqual(riddimVoice(forSlot: "riddim-bass"), .bass)
        XCTAssertEqual(riddimVoice(forSlot: "riddim-melodica"), .melodica)
        XCTAssertNil(riddimVoice(forSlot: "riddim-unknown"))
        XCTAssertNil(riddimVoice(forSlot: "dice-roll"))
    }

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
        // Override with a DISTINCT root (40) so clearing back to the bundled
        // default (33) is a real assertion, not a no-op.
        try await loader.setVoice(url: URL(string: "https://example.com/x.wav")!,
                                  rootMidiNote: 40, for: .bass)
        XCTAssertNotNil(lib.buffer(for: .bass))
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 40)

        loader.clearVoice(.bass)
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 33)  // bundled default restored
        XCTAssertNotNil(lib.buffer(for: .bass))  // bundled default buffer restored
    }

    func test_overridePitchedVoiceWithNilRootReportsNil() throws {
        // A pitched voice (.bass, default 33) overridden with rootMidiNote: nil
        // must report nil — exercises the present-but-nil override membership
        // logic (`overrideRoots[id]` exists with a nil value).
        let lib = try SampleLibrary()
        XCTAssertEqual(lib.rootMidiNote(for: .bass), 33)
        lib.setOverride(buffer: makeBuffer(value: 0.5), rootMidiNote: nil, for: .bass)
        XCTAssertNil(lib.rootMidiNote(for: .bass))
    }

    @MainActor
    func test_prefsDecodesPreSP3BlobWithEmptyRiddim() throws {
        // A persisted blob from before SP3 (no `riddim` key).
        let legacy = #"{"pieceSet":"p1","music":"m1","sfx":{"dice-roll":"a1"}}"#
        let prefs = AssetManager.decodePrefs(Data(legacy.utf8))
        XCTAssertEqual(prefs?.pieceSet, "p1")
        XCTAssertEqual(prefs?.sfx["dice-roll"], "a1")
        XCTAssertEqual(prefs?.riddim, [:])   // missing key => default
    }

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
}
