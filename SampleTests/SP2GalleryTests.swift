// SampleTests/SP2GalleryTests.swift
import XCTest
@testable import Backyamon

final class SP2GalleryTests: XCTestCase {
    /// Smoke: the SP2 test file is wired into the SampleTests target.
    func test_sp2TestFileIsWired() {
        XCTAssertTrue(true)
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
