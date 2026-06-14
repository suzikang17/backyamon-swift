import XCTest
import AVFoundation
@testable import Backyamon

final class ResamplingTests: XCTestCase {
    private func makeBuffer(frames: Int, fill: Float = 0.5) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
        b.frameLength = AVAudioFrameCount(frames)
        let p = b.floatChannelData![0]
        for i in 0..<frames { p[i] = fill }
        return b
    }

    func test_octaveUpHalvesLength() {
        let src = makeBuffer(frames: 1000)
        let out = repitch(src, semitones: 12)
        XCTAssertEqual(Int(out.frameLength), 500, accuracy: 2)
    }

    func test_octaveDownDoublesLength() {
        let src = makeBuffer(frames: 1000)
        let out = repitch(src, semitones: -12)
        XCTAssertEqual(Int(out.frameLength), 2000, accuracy: 2)
    }

    func test_zeroShiftPreservesLengthAndContent() {
        let src = makeBuffer(frames: 100, fill: 0.5)
        let out = repitch(src, semitones: 0)
        XCTAssertEqual(Int(out.frameLength), 100, accuracy: 1)
        XCTAssertEqual(out.floatChannelData![0][50], 0.5, accuracy: 0.001)
    }
}
