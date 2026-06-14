import XCTest
@testable import Backyamon

final class ChordTests: XCTestCase {
    func test_minorTriadIntervals() {
        XCTAssertEqual(ChordQuality.minor.intervals, [0, 3, 7])
    }
    func test_majorTriadIntervals() {
        XCTAssertEqual(ChordQuality.major.intervals, [0, 4, 7])
    }
    func test_dominant7Intervals() {
        XCTAssertEqual(ChordQuality.dominant7.intervals, [0, 4, 7, 10])
    }
    func test_voicingAddsRoot() {
        let c = Chord(root: 5, quality: .minor)
        XCTAssertEqual(c.voicing(), [5, 8, 12])
    }
    func test_isDubRecommendedInMinor() {
        XCTAssertTrue(Chord(root: 0, quality: .minor).isDubRecommended(keyIsMinor: true))
        XCTAssertTrue(Chord(root: 10, quality: .major).isDubRecommended(keyIsMinor: true))
        XCTAssertFalse(Chord(root: 1, quality: .major).isDubRecommended(keyIsMinor: true))
    }
}
