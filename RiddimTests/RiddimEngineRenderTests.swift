import XCTest
import AVFoundation
@testable import Backyamon

final class RiddimEngineRenderTests: XCTestCase {
    private func rms(_ b: AVAudioPCMBuffer) -> Float {
        let p = b.floatChannelData![0]; let n = Int(b.frameLength)
        var s: Float = 0; for i in 0..<n { s += p[i]*p[i] }
        return (s / Float(max(1, n))).squareRoot()
    }

    func test_rendersNonSilentLoopOfExpectedLength() throws {
        let engine = try RiddimEngine()
        engine.load(preset: .oneDrop)
        let buf = engine.renderLoopBuffer()
        let expected = Int((60.0/72.0)*16.0*44100.0)
        XCTAssertEqual(Int(buf.frameLength), expected, accuracy: 4410)
        XCTAssertGreaterThan(rms(buf), 0.02, "loop should be audible")
        XCTAssertLessThanOrEqual(buf.floatChannelData![0].pointee, 1.0)
    }

    func test_bassFollowsProgression() throws {
        let e1 = try RiddimEngine(); e1.load(preset: .oneDrop)
        let e2 = try RiddimEngine(); e2.load(preset: .oneDrop)
        e2.setProgression([Chord(root: 0, quality: .minor), Chord(root: 5, quality: .minor),
                           Chord(root: 7, quality: .minor), Chord(root: 3, quality: .major)])
        XCTAssertNotEqual(rms(e1.renderLoopBuffer()), rms(e2.renderLoopBuffer()), accuracy: 1e-6)
    }
}
