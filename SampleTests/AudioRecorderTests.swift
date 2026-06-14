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
