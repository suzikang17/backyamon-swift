// SampleTests/SP2GalleryTests.swift
import XCTest
@testable import Backyamon

final class SP2GalleryTests: XCTestCase {
    /// Smoke: the SP2 test file is wired into the SampleTests target.
    func test_sp2TestFileIsWired() {
        XCTAssertTrue(true)
    }

    func test_publishAssetPayloadShape() {
        let p = publishAssetPayload(assetId: "asset-123")
        XCTAssertEqual(p["assetId"] as? String, "asset-123")
        XCTAssertEqual(p.count, 1)
    }

    func test_filterAssets_typeOnly() {
        let rows = [sfx("1", title: "Drum Hit", slot: "dice-roll"),
                    music("2", title: "Reggae Loop"),
                    piece("3", title: "Gold Stone")]
        let result = filterAssets(rows, type: .sfx, search: "")
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func test_filterAssets_searchCaseInsensitive() {
        let rows = [sfx("1", title: "Drum Hit", slot: "dice-roll"),
                    music("2", title: "Reggae Loop")]
        let result = filterAssets(rows, type: nil, search: "reggae")
        XCTAssertEqual(result.map(\.id), ["2"])
    }

    func test_filterAssets_typeAndSearchCombined() {
        let rows = [sfx("1", title: "Snare", slot: "dice-roll"),
                    sfx("2", title: "Kick Drum", slot: "piece-move"),
                    music("3", title: "Drum Track")]
        let result = filterAssets(rows, type: .sfx, search: "drum")
        XCTAssertEqual(result.map(\.id), ["2"])
    }

    func test_filterAssets_preservesInputOrder() {
        // Rows arrive already newest-first (server desc(createdAt)); never re-sort.
        let rows = [music("a", title: "New", createdAt: 300),
                    music("b", title: "Mid", createdAt: 200),
                    music("c", title: "Old", createdAt: 100)]
        let result = filterAssets(rows, type: nil, search: "")
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }

    func test_filterAssets_searchMissReturnsEmpty() {
        let rows = [sfx("1", title: "Snare", slot: "dice-roll")]
        XCTAssertTrue(filterAssets(rows, type: nil, search: "zzz").isEmpty)
    }

    // MARK: - Helpers
    private func sfx(_ id: String, title: String, slot: String, createdAt: Int64 = 0) -> Asset {
        let meta = sampleMetadataJSON(kind: .soundEffect(slot: slot), durationMs: 1000, fileSize: 1)
        return Asset(id: id, creatorId: "c", type: .sfx, title: title, status: .published,
                     metadata: meta, r2Key: nil, url: "https://x/\(id)", createdAt: createdAt, updatedAt: createdAt)
    }
    private func music(_ id: String, title: String, createdAt: Int64 = 0) -> Asset {
        let meta = sampleMetadataJSON(kind: .music, durationMs: 1000, fileSize: 1)
        return Asset(id: id, creatorId: "c", type: .music, title: title, status: .published,
                     metadata: meta, r2Key: nil, url: "https://x/\(id)", createdAt: createdAt, updatedAt: createdAt)
    }
    private func piece(_ id: String, title: String) -> Asset {
        Asset(id: id, creatorId: "c", type: .piece, title: title, status: .published,
              metadata: "{}", r2Key: nil, url: nil, createdAt: 0, updatedAt: 0)
    }
}
