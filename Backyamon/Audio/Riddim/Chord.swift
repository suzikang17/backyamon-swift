import Foundation

/// Chord qualities the riddim engine can voice.
enum ChordQuality: CaseIterable {
    case minor, major, dominant7, minor7, major7, sus4

    /// Semitone intervals from the chord root.
    var intervals: [Int] {
        switch self {
        case .minor:      return [0, 3, 7]
        case .major:      return [0, 4, 7]
        case .dominant7:  return [0, 4, 7, 10]
        case .minor7:     return [0, 3, 7, 10]
        case .major7:     return [0, 4, 7, 11]
        case .sus4:       return [0, 5, 7]
        }
    }

    var label: String {
        switch self {
        case .minor: return "m"
        case .major: return ""
        case .dominant7: return "7"
        case .minor7: return "m7"
        case .major7: return "maj7"
        case .sus4: return "sus4"
        }
    }
}

/// A chord, where `root` is a semitone offset from the progression's key tonic.
struct Chord: Equatable {
    var root: Int
    var quality: ChordQuality

    /// Absolute semitone offsets (from the key tonic) for every chord tone.
    func voicing() -> [Int] {
        quality.intervals.map { $0 + root }
    }

    /// Whether this chord is idiomatic for roots/dub in the given key flavour.
    /// Natural-minor scale degrees: 0,2,3,5,7,8,10. Recommended roots: i, iv,
    /// v, bVI, bVII, bIII.
    func isDubRecommended(keyIsMinor: Bool) -> Bool {
        guard keyIsMinor else { return true }
        let recommendedRoots: Set<Int> = [0, 5, 7, 8, 10, 3]
        return recommendedRoots.contains(((root % 12) + 12) % 12)
    }
}
