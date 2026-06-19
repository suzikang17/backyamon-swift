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
