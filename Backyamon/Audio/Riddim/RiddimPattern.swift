import Foundation

/// Instruments the engine can sequence. Pitched ones follow the progression.
enum InstrumentID: String, CaseIterable {
    case kick, snare, hat, shaker, perc   // drums stem
    case bass                             // bass stem
    case organ, skank, melodica           // melodic stem
}

/// A loopable step pattern with tempo + swing. Pure data + timing math.
struct RiddimPattern {
    var bpm: Double
    var bars: Int
    var stepsPerBar: Int
    /// 0.5 = straight; >0.5 pushes offbeat (odd) steps later.
    var swing: Double
    private(set) var tracks: [InstrumentID: [Bool]] = [:]

    var totalSteps: Int { bars * stepsPerBar }

    /// Seconds per step assuming `stepsPerBar` divides a 4/4 bar evenly.
    var secondsPerStep: Double {
        let secondsPerBar = (60.0 / bpm) * 4.0
        return secondsPerBar / Double(stepsPerBar)
    }

    mutating func setTrack(_ id: InstrumentID, steps: [Bool]) {
        precondition(steps.count == totalSteps || steps.count == stepsPerBar,
                     "track length must equal stepsPerBar or totalSteps")
        if steps.count == stepsPerBar && bars > 1 {
            tracks[id] = Array(repeating: steps, count: bars).flatMap { $0 }
        } else {
            tracks[id] = steps
        }
    }

    func activeSteps(_ id: InstrumentID) -> [Int] {
        guard let t = tracks[id] else { return [] }
        return t.enumerated().compactMap { $0.element ? $0.offset : nil }
    }

    /// Start time (s) of a step, applying swing to offbeat 8th positions.
    func time(ofStep step: Int) -> Double {
        let base = Double(step) * secondsPerStep
        if step % 2 == 1 {
            let pairDelay = (swing - 0.5) * 2.0 * secondsPerStep
            return base + pairDelay
        }
        return base
    }

    /// Which bar index a step falls in (for chord lookup).
    func bar(ofStep step: Int) -> Int { step / stepsPerBar }
}
