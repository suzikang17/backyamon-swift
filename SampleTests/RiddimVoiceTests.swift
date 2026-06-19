import XCTest
@testable import Backyamon

final class RiddimVoiceTests: XCTestCase {
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

    func test_riddimVoiceForSlotInverseMapping() {
        XCTAssertEqual(riddimVoice(forSlot: "riddim-kick"), .kick)
        XCTAssertEqual(riddimVoice(forSlot: "riddim-bass"), .bass)
        XCTAssertEqual(riddimVoice(forSlot: "riddim-melodica"), .melodica)
        XCTAssertNil(riddimVoice(forSlot: "riddim-unknown"))
        XCTAssertNil(riddimVoice(forSlot: "dice-roll"))
    }
}
