import XCTest
@testable import Backyamon

final class RiddimVoiceTests: XCTestCase {
    func test_riddimVoiceKindMapsToSfx() {
        let kind = SampleKind.riddimVoice(voice: .bass, rootMidiNote: 33)
        XCTAssertEqual(kind.assetType, .sfx)
    }
}
