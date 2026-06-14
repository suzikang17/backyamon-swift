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
