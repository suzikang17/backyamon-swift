import Foundation

/// A starting-point riddim: a seeded pattern + a default progression.
struct RiddimPreset {
    let name: String
    let pattern: RiddimPattern
    let progression: [Chord]

    /// One-drop roots groove (kick/snare on beat 3, offbeat skank+organ).
    static let oneDrop: RiddimPreset = {
        var p = RiddimPattern(bpm: 72, bars: 4, stepsPerBar: 8, swing: 0.56)
        p.setTrack(.kick,  steps: [false,false,false,false,true,false,false,false])
        p.setTrack(.snare, steps: [false,false,false,false,true,false,false,false])
        p.setTrack(.hat,   steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.shaker,steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.bass,  steps: [true,false,false,true,false,true,false,false])
        p.setTrack(.organ, steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.skank, steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.melodica, steps: [false,false,false,false,false,false,false,false])
        let prog = [Chord(root: 0, quality: .minor), Chord(root: 10, quality: .major),
                    Chord(root: 8, quality: .major), Chord(root: 10, quality: .major)]
        return RiddimPreset(name: "One Drop", pattern: p, progression: prog)
    }()
}
