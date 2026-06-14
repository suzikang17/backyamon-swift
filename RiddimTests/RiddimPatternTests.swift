import XCTest
@testable import Backyamon

final class RiddimPatternTests: XCTestCase {
    func test_secondsPerStepAtTempo() {
        let p = RiddimPattern(bpm: 120, bars: 1, stepsPerBar: 8, swing: 0.5)
        XCTAssertEqual(p.secondsPerStep, 0.25, accuracy: 1e-9)
    }

    func test_eventTimesNoSwing() {
        let p = RiddimPattern(bpm: 120, bars: 1, stepsPerBar: 8, swing: 0.5)
        XCTAssertEqual(p.time(ofStep: 0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(p.time(ofStep: 2), 0.5, accuracy: 1e-9)
    }

    func test_swingPushesOddSteps() {
        let p = RiddimPattern(bpm: 120, bars: 1, stepsPerBar: 8, swing: 0.6)
        let straight = 1.0 * p.secondsPerStep
        XCTAssertGreaterThan(p.time(ofStep: 1), straight)
    }

    func test_activeStepsForTrack() {
        var p = RiddimPattern(bpm: 72, bars: 1, stepsPerBar: 8, swing: 0.56)
        p.setTrack(.kick, steps: [false,false,true,false,false,false,true,false])
        XCTAssertEqual(p.activeSteps(.kick), [2, 6])
    }
}
