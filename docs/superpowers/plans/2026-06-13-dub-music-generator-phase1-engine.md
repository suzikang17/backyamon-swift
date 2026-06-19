# Dub Music Generator — Phase 1 (Sound Engine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a sample-based reggae/dub riddim engine in the app that loops a 4-stem groove (drums/bass/melodic/sfx), voices a user-defined chord progression, runs it through a dub FX chain, and can render the loop to a playable audio file.

**Architecture:** A new `Backyamon/Audio/Riddim/` subsystem, separate from the reactive `MusicEngine`. Each instrument is a *voice* backed by a bundled sample one-shot; pitched voices (bass/organ/skank/melodica) are repitched per chord. Four stem mixers feed a master through `AVAudioUnitReverb` + `AVAudioUnitDelay`. Pure-logic units (chord voicing, repitch math, pattern timing) are unit-tested; the audio graph is verified via AVAudioEngine **offline (manual) rendering** asserting RMS/peak/length. Mirrors the proven AVAudioEngine patterns already in `Backyamon/Audio/MusicEngine.swift` and `SoundManager.swift`.

**Tech Stack:** Swift 5.10, AVFoundation (AVAudioEngine, AVAudioPCMBuffer, AVAudioUnitReverb, AVAudioUnitDelay, manual rendering mode), XCTest, XcodeGen.

---

## File Structure

**New source files**
- `Backyamon/Audio/Riddim/Chord.swift` — chord model + voicing (pure).
- `Backyamon/Audio/Riddim/Resampling.swift` — buffer repitch utility (pure-ish).
- `Backyamon/Audio/Riddim/RiddimPattern.swift` — step pattern, transport, event timing (pure).
- `Backyamon/Audio/Riddim/SampleLibrary.swift` — loads bundled one-shots into buffers.
- `Backyamon/Audio/Riddim/RiddimEngine.swift` — AVAudioEngine graph: stems, scheduling, FX, offline render.
- `Backyamon/Audio/Riddim/Presets.swift` — preset riddims (patterns + progressions).
- `Backyamon/Audio/Riddim/Samples/*.wav` — bundled curated kit (one-shots).

**Modified**
- `project.yml` — add `RiddimTests` unit-test target; ensure `.wav` resources bundle.
- `Backyamon/Audio/SoundManager.swift` — add `loadCustomMusic(fileURL:)` for a local rendered file.

**New tests**
- `RiddimTests/ChordTests.swift`
- `RiddimTests/ResamplingTests.swift`
- `RiddimTests/RiddimPatternTests.swift`
- `RiddimTests/SampleLibraryTests.swift`
- `RiddimTests/RiddimEngineRenderTests.swift`

---

## Task 0: Add a unit-test target (XcodeGen) + smoke test

**Files:**
- Modify: `project.yml`
- Create: `RiddimTests/SmokeTests.swift`

- [ ] **Step 1: Add the test target to `project.yml`**

Add a `RiddimTests` target and wire it into the scheme. Replace the existing `scheme:` block under the `Backyamon` target (`project.yml:26-27`) and append the new target.

In `targets:` (sibling of `Backyamon:`), add:

```yaml
  RiddimTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: RiddimTests
    dependencies:
      - target: Backyamon
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.backyamon.RiddimTests
        GENERATE_INFOPLIST_FILE: YES
```

And change the `Backyamon` target's scheme block from:

```yaml
    scheme:
      testTargets: []
```
to:
```yaml
    scheme:
      testTargets:
        - RiddimTests
```

- [ ] **Step 2: Write a smoke test**

Create `RiddimTests/SmokeTests.swift`:

```swift
import XCTest
@testable import Backyamon

final class SmokeTests: XCTestCase {
    func test_smoke() {
        XCTAssertEqual(2 + 2, 4)
    }
}
```

- [ ] **Step 3: Regenerate the project**

Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate`
Expected: `Created project at Backyamon.xcodeproj`

- [ ] **Step 4: Find an available simulator**

Run: `xcrun simctl list devices available | grep -i iphone | head -1`
Note the device name (e.g. `iPhone 16`). Use it as `<SIM>` in test commands below.

- [ ] **Step 5: Run the smoke test**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/SmokeTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add project.yml RiddimTests/SmokeTests.swift Backyamon.xcodeproj
git commit -m "test: add RiddimTests unit-test target"
```

---

## Task 1: Chord model + voicing (pure)

**Files:**
- Create: `Backyamon/Audio/Riddim/Chord.swift`
- Test: `RiddimTests/ChordTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `RiddimTests/ChordTests.swift`:

```swift
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
    // root is a semitone offset from the key tonic; voicing is absolute semitones.
    func test_voicingAddsRoot() {
        let c = Chord(root: 5, quality: .minor)   // iv in a minor key
        XCTAssertEqual(c.voicing(), [5, 8, 12])
    }
    func test_isDubRecommendedInMinor() {
        // In natural minor, i, iv, v, bVI, bVII, bIII are recommended.
        XCTAssertTrue(Chord(root: 0, quality: .minor).isDubRecommended(keyIsMinor: true))   // i
        XCTAssertTrue(Chord(root: 10, quality: .major).isDubRecommended(keyIsMinor: true))  // bVII
        XCTAssertFalse(Chord(root: 1, quality: .major).isDubRecommended(keyIsMinor: true))  // bII - not idiomatic
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/ChordTests 2>&1 | tail -20`
Expected: FAIL (compile error: `ChordQuality` / `Chord` not found).

- [ ] **Step 3: Implement**

Create `Backyamon/Audio/Riddim/Chord.swift`:

```swift
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
    /// v, bVI, bVII, bIII. (Major-key support is a Phase 2 nicety.)
    func isDubRecommended(keyIsMinor: Bool) -> Bool {
        guard keyIsMinor else { return true }
        let recommendedRoots: Set<Int> = [0, 5, 7, 8, 10, 3]
        return recommendedRoots.contains(((root % 12) + 12) % 12)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/ChordTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Backyamon/Audio/Riddim/Chord.swift RiddimTests/ChordTests.swift Backyamon.xcodeproj
git commit -m "feat: chord model + dub-recommended voicing"
```

---

## Task 2: Buffer repitch / resample utility

**Files:**
- Create: `Backyamon/Audio/Riddim/Resampling.swift`
- Test: `RiddimTests/ResamplingTests.swift`

Repitch by linear-interpolation resampling: a shift of `s` semitones reads the
source at rate `2^(s/12)`, so the output length ≈ `inputLength / rate`.

- [ ] **Step 1: Write the failing tests**

Create `RiddimTests/ResamplingTests.swift`:

```swift
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
        let out = repitch(src, semitones: 12)   // up an octave -> rate 2 -> half length
        XCTAssertEqual(Int(out.frameLength), 500, accuracy: 2)
    }

    func test_octaveDownDoublesLength() {
        let src = makeBuffer(frames: 1000)
        let out = repitch(src, semitones: -12)   // down an octave -> rate 0.5 -> double
        XCTAssertEqual(Int(out.frameLength), 2000, accuracy: 2)
    }

    func test_zeroShiftPreservesLengthAndContent() {
        let src = makeBuffer(frames: 100, fill: 0.5)
        let out = repitch(src, semitones: 0)
        XCTAssertEqual(Int(out.frameLength), 100, accuracy: 1)
        XCTAssertEqual(out.floatChannelData![0][50], 0.5, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/ResamplingTests 2>&1 | tail -20`
Expected: FAIL (`repitch` not found).

- [ ] **Step 3: Implement**

Create `Backyamon/Audio/Riddim/Resampling.swift`:

```swift
import AVFoundation

/// Repitch a mono PCM buffer by `semitones` via linear-interpolation resampling.
/// Positive = higher/shorter, negative = lower/longer. Sample rate is unchanged;
/// only the playback content is stretched, so pitch shifts on playback.
func repitch(_ source: AVAudioPCMBuffer, semitones: Double) -> AVAudioPCMBuffer {
    let rate = pow(2.0, semitones / 12.0)
    let inFrames = Int(source.frameLength)
    let outFrames = max(1, Int(Double(inFrames) / rate))
    let fmt = source.format
    let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(outFrames))!
    out.frameLength = AVAudioFrameCount(outFrames)

    let src = source.floatChannelData![0]
    let dst = out.floatChannelData![0]
    var pos = 0.0
    for i in 0..<outFrames {
        let i0 = Int(pos)
        let frac = Float(pos - Double(i0))
        let a = src[min(i0, inFrames - 1)]
        let b = src[min(i0 + 1, inFrames - 1)]
        dst[i] = a + (b - a) * frac
        pos += rate
    }
    return out
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/ResamplingTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Backyamon/Audio/Riddim/Resampling.swift RiddimTests/ResamplingTests.swift Backyamon.xcodeproj
git commit -m "feat: linear-interpolation buffer repitch"
```

---

## Task 3: Pattern + transport model (pure)

**Files:**
- Create: `Backyamon/Audio/Riddim/RiddimPattern.swift`
- Test: `RiddimTests/RiddimPatternTests.swift`

Model the loop as a fixed number of bars, a steps-per-bar grid, bpm, and swing.
Each instrument track is a `[Bool]` of length `bars * stepsPerBar`. Event times
are computed in seconds; odd (offbeat) 8th steps are pushed by `swing`.

- [ ] **Step 1: Write the failing tests**

Create `RiddimTests/RiddimPatternTests.swift`:

```swift
import XCTest
@testable import Backyamon

final class RiddimPatternTests: XCTestCase {
    func test_secondsPerStepAtTempo() {
        // 8 steps/bar at 120 bpm: a beat = 0.5s, an 8th = 0.25s.
        let p = RiddimPattern(bpm: 120, bars: 1, stepsPerBar: 8, swing: 0.5)
        XCTAssertEqual(p.secondsPerStep, 0.25, accuracy: 1e-9)
    }

    func test_eventTimesNoSwing() {
        let p = RiddimPattern(bpm: 120, bars: 1, stepsPerBar: 8, swing: 0.5)
        XCTAssertEqual(p.time(ofStep: 0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(p.time(ofStep: 2), 0.5, accuracy: 1e-9)
    }

    func test_swingPushesOddSteps() {
        // swing 0.6 pushes each offbeat 8th later by 0.1 of a step pair.
        let p = RiddimPattern(bpm: 120, bars: 1, stepsPerBar: 8, swing: 0.6)
        let straight = 1.0 * p.secondsPerStep        // step 1 with no swing
        XCTAssertGreaterThan(p.time(ofStep: 1), straight)
    }

    func test_activeStepsForTrack() {
        var p = RiddimPattern(bpm: 72, bars: 1, stepsPerBar: 8, swing: 0.56)
        p.setTrack(.kick, steps: [false,false,true,false,false,false,true,false])
        XCTAssertEqual(p.activeSteps(.kick), [2, 6])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimPatternTests 2>&1 | tail -20`
Expected: FAIL (`RiddimPattern` not found).

- [ ] **Step 3: Implement**

Create `Backyamon/Audio/Riddim/RiddimPattern.swift`:

```swift
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
        // Only swing when the grid is 8ths-or-coarser pairs; push odd steps.
        if step % 2 == 1 {
            let pairDelay = (swing - 0.5) * 2.0 * secondsPerStep
            return base + pairDelay
        }
        return base
    }

    /// Which bar index a step falls in (for chord lookup).
    func bar(ofStep step: Int) -> Int { step / stepsPerBar }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimPatternTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Backyamon/Audio/Riddim/RiddimPattern.swift RiddimTests/RiddimPatternTests.swift Backyamon.xcodeproj
git commit -m "feat: riddim step pattern + swing timing"
```

---

## Task 4: Bundle the sample kit + SampleLibrary loader

**Files:**
- Create: `Backyamon/Audio/Riddim/Samples/` (10 `.wav` one-shots)
- Create: `Backyamon/Audio/Riddim/SampleLibrary.swift`
- Modify: `project.yml` (ensure `.wav` under `Backyamon` bundles as a resource — XcodeGen bundles non-source files in a `sources` path automatically; no change needed if the kit lives under `Backyamon/`).
- Test: `RiddimTests/SampleLibraryTests.swift`

The curated kit (one short mono/stereo 44.1k WAV per voice). For Phase 1 use the
free TidalCycles Dirt-Samples one-shots validated in the prototype (see
`.superpowers/brainstorm/gen_hybrid.py`); **before shipping**, swap to a
license-vetted kit. Each pitched sample is tagged with the MIDI note it was
recorded at so `repitch` can target chord tones.

- [ ] **Step 1: Add the sample files**

Copy the validated kit into the project (filenames are the loader's contract):

```bash
mkdir -p Backyamon/Audio/Riddim/Samples
# from the prototype download dir (re-download if absent — see gen_hybrid.py):
cp /tmp/dirt/kick.wav   Backyamon/Audio/Riddim/Samples/kick.wav
cp /tmp/dirt/snare.wav  Backyamon/Audio/Riddim/Samples/snare.wav
cp /tmp/dirt/hatc.wav   Backyamon/Audio/Riddim/Samples/hat.wav
cp /tmp/dirt/perc.wav   Backyamon/Audio/Riddim/Samples/perc.wav
cp /tmp/dirt/perc.wav   Backyamon/Audio/Riddim/Samples/shaker.wav
cp /tmp/dirt/c_bass3.wav Backyamon/Audio/Riddim/Samples/bass.wav
cp /tmp/dirt/stab.wav   Backyamon/Audio/Riddim/Samples/organ.wav
cp /tmp/dirt/stab.wav   Backyamon/Audio/Riddim/Samples/skank.wav
cp /tmp/dirt/stab.wav   Backyamon/Audio/Riddim/Samples/melodica.wav
```

(If `/tmp/dirt` is gone, re-run the download block from the design doc / `gen_hybrid.py` header.) Note in the commit message that these are placeholder free samples pending license vetting.

- [ ] **Step 2: Write the failing tests**

Create `RiddimTests/SampleLibraryTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import Backyamon

final class SampleLibraryTests: XCTestCase {
    func test_loadsEveryInstrument() throws {
        let lib = try SampleLibrary()
        for id in InstrumentID.allCases {
            let buf = lib.buffer(for: id)
            XCTAssertNotNil(buf, "missing sample for \(id)")
            XCTAssertGreaterThan(buf!.frameLength, 0)
        }
    }

    func test_pitchedVoicesHaveRootNote() throws {
        let lib = try SampleLibrary()
        XCTAssertNotNil(lib.rootMidiNote(for: .bass))
        XCTAssertNil(lib.rootMidiNote(for: .kick))   // drums are unpitched
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate && xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/SampleLibraryTests 2>&1 | tail -20`
Expected: FAIL (`SampleLibrary` not found).

- [ ] **Step 4: Implement**

Create `Backyamon/Audio/Riddim/SampleLibrary.swift`:

```swift
import AVFoundation

/// Loads the bundled one-shot kit into mono 44.1k PCM buffers.
final class SampleLibrary {
    enum LibraryError: Error { case missing(String) }

    private var buffers: [InstrumentID: AVAudioPCMBuffer] = [:]

    /// MIDI note each pitched sample was recorded at (its repitch reference).
    /// Drums are absent (played at native pitch). Values match the chosen kit;
    /// the bass sample (zgump ~55 Hz) is ≈ A1 = MIDI 33; the stab ≈ A3 = 57.
    private let rootNotes: [InstrumentID: Int] = [
        .bass: 33, .organ: 57, .skank: 57, .melodica: 57,
    ]

    /// File stem per instrument (all under Audio/Riddim/Samples/).
    private let fileNames: [InstrumentID: String] = [
        .kick: "kick", .snare: "snare", .hat: "hat", .shaker: "shaker",
        .perc: "perc", .bass: "bass", .organ: "organ", .skank: "skank",
        .melodica: "melodica",
    ]

    init() throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        for (id, name) in fileNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                throw LibraryError.missing(name)
            }
            buffers[id] = try Self.loadMono(url: url, format: fmt)
        }
    }

    func buffer(for id: InstrumentID) -> AVAudioPCMBuffer? { buffers[id] }
    func rootMidiNote(for id: InstrumentID) -> Int? { rootNotes[id] }

    /// Read a WAV, downmixing to mono and converting to the engine format.
    private static func loadMono(url: URL, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                     frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw LibraryError.missing(url.lastPathComponent)
        }
        let outCapacity = AVAudioFrameCount(Double(file.length) * format.sampleRate / file.processingFormat.sampleRate) + 64
        let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity)!
        var done = false
        try converter.convert(to: outBuf, error: nil) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true; status.pointee = .haveData; return inBuf
        }
        return outBuf
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/SampleLibraryTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Backyamon/Audio/Riddim/Samples Backyamon/Audio/Riddim/SampleLibrary.swift RiddimTests/SampleLibraryTests.swift project.yml Backyamon.xcodeproj
git commit -m "feat: bundle riddim sample kit + loader (placeholder free samples, license TBD)"
```

---

## Task 5: Render a stem buffer from a pattern (the sequencer core)

**Files:**
- Create: `Backyamon/Audio/Riddim/RiddimEngine.swift` (start it here)
- Test: `RiddimTests/RiddimEngineRenderTests.swift` (start it here)

This task adds **pure buffer assembly** (no live AVAudioEngine yet): given the
library, a pattern, and a progression, mix one looped 4-stem buffer offline. This
is fully testable via RMS/peak/length, mirroring the prototype's diagnostics.

- [ ] **Step 1: Write the failing test**

Create `RiddimTests/RiddimEngineRenderTests.swift`:

```swift
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
        // 4 bars at 72 bpm = (60/72)*16 s at 44.1k.
        let expected = Int((60.0/72.0)*16.0*44100.0)
        XCTAssertEqual(Int(buf.frameLength), expected, accuracy: 4410)  // ±0.1s
        XCTAssertGreaterThan(rms(buf), 0.02, "loop should be audible")
        XCTAssertLessThanOrEqual(buf.floatChannelData![0].pointee, 1.0)
    }

    func test_bassFollowsProgression() throws {
        // Two different progressions must produce different bass content.
        let e1 = try RiddimEngine(); e1.load(preset: .oneDrop)
        let e2 = try RiddimEngine(); e2.load(preset: .oneDrop)
        e2.setProgression([Chord(root: 0, quality: .minor), Chord(root: 5, quality: .minor),
                           Chord(root: 7, quality: .minor), Chord(root: 3, quality: .major)])
        XCTAssertNotEqual(rms(e1.renderLoopBuffer()), rms(e2.renderLoopBuffer()), accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests 2>&1 | tail -20`
Expected: FAIL (`RiddimEngine` / `.oneDrop` not found).

- [ ] **Step 3: Implement the offline assembler**

Create `Backyamon/Audio/Riddim/RiddimEngine.swift`:

```swift
import AVFoundation

/// Sample-based riddim engine. This task implements offline buffer assembly;
/// Tasks 6-8 add chord voicing depth, the live graph, FX, and file render.
final class RiddimEngine {
    private let library: SampleLibrary
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat

    private(set) var pattern: RiddimPattern
    private(set) var progression: [Chord]

    init() throws {
        self.library = try SampleLibrary()
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let preset = RiddimPreset.oneDrop
        self.pattern = preset.pattern
        self.progression = preset.progression
    }

    func load(preset: RiddimPreset) {
        pattern = preset.pattern
        progression = preset.progression
    }

    func setProgression(_ chords: [Chord]) { progression = chords }

    /// Mix the full looped pattern into one mono buffer (drums+bass+melodic).
    func renderLoopBuffer() -> AVAudioPCMBuffer {
        let frames = Int(Double(pattern.totalSteps) * pattern.secondsPerStep * sampleRate)
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        out.frameLength = AVAudioFrameCount(frames)
        let dst = out.floatChannelData![0]
        for i in 0..<frames { dst[i] = 0 }

        for id in InstrumentID.allCases {
            for step in pattern.activeSteps(id) {
                let t = pattern.time(ofStep: step)
                let startFrame = Int(t * sampleRate)
                let hit = sampleForHit(id, step: step)
                mix(hit, into: dst, at: startFrame, total: frames, gain: gain(for: id))
            }
        }
        // Soft limit.
        for i in 0..<frames { dst[i] = tanhf(dst[i]) }
        return out
    }

    // MARK: - Per-hit sample selection (chord-aware for pitched voices)

    private func sampleForHit(_ id: InstrumentID, step: Int) -> AVAudioPCMBuffer {
        guard let base = library.buffer(for: id) else { return emptyBuffer() }
        guard let root = library.rootMidiNote(for: id) else { return base }  // drums
        let bar = pattern.bar(ofStep: step)
        let chord = progression[bar % progression.count]
        // Bass plays the chord root low; melodic voices play the chord's 3rd.
        let targetSemis: Int
        switch id {
        case .bass: targetSemis = chord.root - 12       // an octave down for depth
        default:    targetSemis = chord.voicing().count > 1 ? chord.voicing()[1] : chord.root
        }
        let baseMidi = root
        let shift = Double((baseMidi + targetSemis) - baseMidi)   // = targetSemis
        return repitch(base, semitones: shift)
    }

    private func gain(for id: InstrumentID) -> Float {
        switch id {
        case .kick: return 1.0
        case .snare: return 0.8
        case .hat: return 0.5
        case .shaker, .perc: return 0.5
        case .bass: return 1.2
        case .organ: return 0.9
        case .skank: return 0.9
        case .melodica: return 0.6
        }
    }

    private func mix(_ src: AVAudioPCMBuffer, into dst: UnsafeMutablePointer<Float>,
                     at start: Int, total: Int, gain: Float) {
        let s = src.floatChannelData![0]; let n = Int(src.frameLength)
        for i in 0..<n {
            let j = start + i
            if j >= 0 && j < total { dst[j] += s[i] * gain }
        }
    }

    private func emptyBuffer() -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!; b.frameLength = 1; return b
    }
}
```

- [ ] **Step 4: Create the preset referenced by the test**

Create `Backyamon/Audio/Riddim/Presets.swift`:

```swift
import Foundation

/// A starting-point riddim: a seeded pattern + a default progression.
struct RiddimPreset {
    let name: String
    let pattern: RiddimPattern
    let progression: [Chord]

    /// One-drop roots groove (kick/snare on beat 3, offbeat skank+organ).
    static let oneDrop: RiddimPreset = {
        var p = RiddimPattern(bpm: 72, bars: 4, stepsPerBar: 8, swing: 0.56)
        // step index within an 8-step bar: 0..7 (8ths). Beat 3 = step 4.
        p.setTrack(.kick,  steps: [false,false,false,false,true,false,false,false])
        p.setTrack(.snare, steps: [false,false,false,false,true,false,false,false])
        p.setTrack(.hat,   steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.shaker,steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.bass,  steps: [true,false,false,true,false,true,false,false])
        p.setTrack(.organ, steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.skank, steps: [false,true,false,true,false,true,false,true])
        p.setTrack(.melodica, steps: [false,false,false,false,false,false,false,false])
        // Am - G - F - G (roots descending), as semitone roots in A-minor.
        let prog = [Chord(root: 0, quality: .minor), Chord(root: 10, quality: .major),
                    Chord(root: 8, quality: .major), Chord(root: 10, quality: .major)]
        return RiddimPreset(name: "One Drop", pattern: p, progression: prog)
    }()
}

extension RiddimEngine {
    /// Convenience for tests / callers referencing presets by enum-like value.
    func load(preset: RiddimPresetRef) { load(preset: preset.value) }
}

/// Lightweight reference so call sites can write `.oneDrop`.
enum RiddimPresetRef { case oneDrop; var value: RiddimPreset { switch self { case .oneDrop: return .oneDrop } } }
```

Note: in the test, `engine.load(preset: .oneDrop)` resolves to `RiddimPresetRef.oneDrop`. Keep the `RiddimPreset.oneDrop` static as the source of truth.

- [ ] **Step 5: Run to verify pass**

Run: `cd /Users/suki/dev/backyamon-swift && xcodegen generate && xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Backyamon/Audio/Riddim/RiddimEngine.swift Backyamon/Audio/Riddim/Presets.swift RiddimTests/RiddimEngineRenderTests.swift Backyamon.xcodeproj
git commit -m "feat: offline riddim loop assembly + one-drop preset"
```

---

## Task 6: Proper chord voicing for melodic stems

**Files:**
- Modify: `Backyamon/Audio/Riddim/RiddimEngine.swift`
- Test: `RiddimTests/RiddimEngineRenderTests.swift` (add a case)

Currently melodic voices play a single chord tone. Make organ/skank play the
**full chord** (root+3rd+5th, +7th) by layering repitched copies, so quality
(maj/min/7) is audible — fulfilling the free chord builder requirement.

- [ ] **Step 1: Add the failing test**

Append to `RiddimEngineRenderTests`:

```swift
func test_chordQualityChangesMelodicContent() throws {
    let e1 = try RiddimEngine(); e1.load(preset: .oneDrop)
    e1.setProgression([Chord(root: 0, quality: .minor)])
    let e2 = try RiddimEngine(); e2.load(preset: .oneDrop)
    e2.setProgression([Chord(root: 0, quality: .major)])
    // Minor vs major triad on the same root must render differently.
    XCTAssertNotEqual(rms(e1.renderLoopBuffer()), rms(e2.renderLoopBuffer()), accuracy: 1e-6)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests/test_chordQualityChangesMelodicContent 2>&1 | tail -20`
Expected: FAIL (organ currently uses only the 3rd, so maj/min may render near-identically).

- [ ] **Step 3: Implement chord layering**

In `RiddimEngine.swift`, replace `sampleForHit` so melodic voices layer the whole
voicing. Add a helper and route `.organ`/`.skank`/`.melodica` through it:

```swift
private func sampleForHit(_ id: InstrumentID, step: Int) -> AVAudioPCMBuffer {
    guard let base = library.buffer(for: id) else { return emptyBuffer() }
    guard let _ = library.rootMidiNote(for: id) else { return base }   // drums
    let bar = pattern.bar(ofStep: step)
    let chord = progression[bar % progression.count]
    if id == .bass {
        return repitch(base, semitones: Double(chord.root - 12))
    }
    // Melodic: sum repitched copies for each chord tone.
    return layeredChord(base: base, voicing: chord.voicing())
}

private func layeredChord(base: AVAudioPCMBuffer, voicing: [Int]) -> AVAudioPCMBuffer {
    let copies = voicing.map { repitch(base, semitones: Double($0)) }
    let maxLen = copies.map { Int($0.frameLength) }.max() ?? 0
    let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxLen))!
    out.frameLength = AVAudioFrameCount(maxLen)
    let dst = out.floatChannelData![0]
    for i in 0..<maxLen { dst[i] = 0 }
    let norm = Float(1.0 / Double(max(1, copies.count)))
    for c in copies {
        let s = c.floatChannelData![0]; let n = Int(c.frameLength)
        for i in 0..<n { dst[i] += s[i] * norm }
    }
    return out
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Backyamon/Audio/Riddim/RiddimEngine.swift RiddimTests/RiddimEngineRenderTests.swift
git commit -m "feat: voice full chords (maj/min/7) on melodic stems"
```

---

## Task 7: Dub FX chain (reverb + tape delay + master warmth)

**Files:**
- Modify: `Backyamon/Audio/Riddim/RiddimEngine.swift`
- Test: `RiddimTests/RiddimEngineRenderTests.swift` (add a case)

Process the assembled loop through AVFoundation FX using an **offline AVAudioEngine
manual-render** pass: a player node → `AVAudioUnitDelay` (tape echo) →
`AVAudioUnitReverb` (spring) → output, rendered to a buffer. This reuses Apple's
DSP instead of hand-rolling, and stays headless/testable.

- [ ] **Step 1: Add the failing test**

Append to `RiddimEngineRenderTests`:

```swift
func test_dubFXAddsTailEnergy() throws {
    let e = try RiddimEngine(); e.load(preset: .oneDrop)
    let dry = e.renderLoopBuffer()
    let wet = try e.renderProcessedLoop()    // delay+reverb tail extends the loop
    XCTAssertGreaterThan(Int(wet.frameLength), Int(dry.frameLength))
    let p = wet.floatChannelData![0]; let n = Int(wet.frameLength)
    // The reverb/echo tail (last 0.3s) should be non-silent.
    var tail: Float = 0; let start = max(0, n - Int(0.3*44100))
    for i in start..<n { tail += abs(p[i]) }
    XCTAssertGreaterThan(tail, 0.0)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests/test_dubFXAddsTailEnergy 2>&1 | tail -20`
Expected: FAIL (`renderProcessedLoop` not found).

- [ ] **Step 3: Implement offline FX render**

Add to `RiddimEngine.swift`:

```swift
/// Run the assembled loop through the dub FX chain offline (manual rendering),
/// returning a buffer that includes the reverb/echo tail.
func renderProcessedLoop(tailSeconds: Double = 1.5) throws -> AVAudioPCMBuffer {
    let source = renderLoopBuffer()
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()

    delay.delayTime = (60.0 / pattern.bpm) * 0.75   // dotted-8th tape echo
    delay.feedback = 40
    delay.lowPassCutoff = 2800
    delay.wetDryMix = 28
    reverb.loadFactoryPreset(.largeRoom)
    reverb.wetDryMix = 22

    engine.attach(player); engine.attach(delay); engine.attach(reverb)
    engine.connect(player, to: delay, format: format)
    engine.connect(delay, to: reverb, format: format)
    engine.connect(reverb, to: engine.mainMixerNode, format: format)

    let total = AVAudioFrameCount(Double(source.frameLength) + tailSeconds * sampleRate)
    try engine.enableManualRenderingMode(.offline, format: format,
                                         maximumFrameCount: 4096)
    try engine.start()
    player.scheduleBuffer(source, at: nil, options: [], completionHandler: nil)
    player.play()

    let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total)!
    let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
    while engine.manualRenderingSampleTime < AVAudioFramePosition(total) {
        let remaining = total - AVAudioFrameCount(engine.manualRenderingSampleTime)
        let toRender = min(chunk.frameCapacity, remaining)
        let status = try engine.renderOffline(toRender, to: chunk)
        guard status == .success else { break }
        appendBuffer(chunk, to: out)
    }
    engine.stop()
    return out
}

private func appendBuffer(_ src: AVAudioPCMBuffer, to dst: AVAudioPCMBuffer) {
    let n = Int(src.frameLength); let off = Int(dst.frameLength)
    let s = src.floatChannelData![0]; let d = dst.floatChannelData![0]
    let cap = Int(dst.frameCapacity)
    for i in 0..<n where off + i < cap { d[off + i] = s[i] }
    dst.frameLength = AVAudioFrameCount(min(cap, off + n))
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Backyamon/Audio/Riddim/RiddimEngine.swift RiddimTests/RiddimEngineRenderTests.swift
git commit -m "feat: offline dub FX render (tape delay + spring reverb)"
```

---

## Task 8: Render to a playable file

**Files:**
- Modify: `Backyamon/Audio/Riddim/RiddimEngine.swift`
- Test: `RiddimTests/RiddimEngineRenderTests.swift` (add a case)

Write the processed loop (looped to a target length, e.g. ~30s) to a `.caf`/`.wav`
in the caches dir so it can be played/equipped.

- [ ] **Step 1: Add the failing test**

```swift
func test_writesPlayableFile() throws {
    let e = try RiddimEngine(); e.load(preset: .oneDrop)
    let url = try e.renderToFile(loops: 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    let f = try AVAudioFile(forReading: url)
    XCTAssertGreaterThan(f.length, 0)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests/test_writesPlayableFile 2>&1 | tail -20`
Expected: FAIL (`renderToFile` not found).

- [ ] **Step 3: Implement**

Add to `RiddimEngine.swift`:

```swift
/// Render the processed loop, tiled `loops` times, to a WAV file in caches.
func renderToFile(loops: Int = 1) throws -> URL {
    let one = try renderProcessedLoop()
    let dir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
    let url = dir.appendingPathComponent("riddim-\(UUID().uuidString).wav")
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    for _ in 0..<max(1, loops) { try file.write(from: one) }
    return url
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Backyamon/Audio/Riddim/RiddimEngine.swift RiddimTests/RiddimEngineRenderTests.swift
git commit -m "feat: render riddim loop to a playable WAV file"
```

---

## Task 9: Play a rendered file via SoundManager (end-to-end proof)

**Files:**
- Modify: `Backyamon/Audio/SoundManager.swift:132-150` (add a local-file loader)
- Test: `RiddimTests/RiddimEngineRenderTests.swift` (add a case)

`SoundManager.loadCustomMusic(url:)` currently *downloads* from a remote URL.
Add a sibling that loads a **local file** so a freshly-rendered riddim can be
auditioned/equipped without a round-trip. This is the Phase 1 end-to-end proof;
saving as a server `Asset` is Phase 2.

- [ ] **Step 1: Add the failing test**

```swift
@MainActor
func test_soundManagerLoadsLocalRender() throws {
    let e = try RiddimEngine(); e.load(preset: .oneDrop)
    let url = try e.renderToFile(loops: 1)
    SoundManager.shared.loadCustomMusic(fileURL: url)
    // No throw + file exists is the contract; playback is verified manually.
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests/test_soundManagerLoadsLocalRender 2>&1 | tail -20`
Expected: FAIL (`loadCustomMusic(fileURL:)` not found).

- [ ] **Step 3: Implement**

In `Backyamon/Audio/SoundManager.swift`, add below the existing
`loadCustomMusic(url:)` (after line 150):

```swift
/// Load a *local* audio file (e.g. a freshly-rendered riddim) for looped
/// playback. Unlike `loadCustomMusic(url:)` this does no network download.
func loadCustomMusic(fileURL: URL) {
    do {
        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.numberOfLoops = -1
        player.volume = 0.4
        player.prepareToPlay()
        self.musicPlayer?.stop()
        self.musicPlayer = player
    } catch {
        // Ignore — procedural music remains available.
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests/RiddimEngineRenderTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Full suite + manual listen**

Run: `xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,name=<SIM>' -only-testing:RiddimTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`

Manual check: in a scratch view or the app's debug path, call
`SoundManager.shared.loadCustomMusic(fileURL: try RiddimEngine().renderToFile())`
then `SoundManager.shared.playCustomMusic()` and confirm it sounds like the
hybrid dub loop validated in the prototype.

- [ ] **Step 6: Commit**

```bash
git add Backyamon/Audio/SoundManager.swift RiddimTests/RiddimEngineRenderTests.swift
git commit -m "feat: play locally-rendered riddim via SoundManager (Phase 1 end-to-end)"
```

---

## Self-Review

**Spec coverage (design §5 Phase 1):**
- Hybrid voice = swappable slot → Task 4 (`SampleLibrary`, sample-backed voices).
- 4-stem model → InstrumentID stems + per-id gains (Tasks 3, 5); *note:* Phase 1
  mixes stems into one buffer rather than exposing live faders — live per-stem
  fader nodes are a Phase 2 (UI) concern; the data model already groups by stem.
- Continuous loopable stems → Task 5 (`renderLoopBuffer`, looped file in Task 8).
- Free chord model + voicing → Tasks 1, 6.
- Dub recommendations → Task 1 (`isDubRecommended`); surfaced in Phase 2 UI.
- Dub FX bus (reverb/delay/master) → Task 7.
- Preset riddims → Task 4/5 (`RiddimPreset.oneDrop`); more presets are additive.
- Offline render → Tasks 7, 8.
- 44.1k → throughout. *Stereo is deferred:* Phase 1 renders mono (simpler,
  testable); stereo width is a Phase 2 polish (noted in design §8).
- Integration (equip) → Task 9 (local playback); server `Asset` save = Phase 2.

**Gaps deliberately deferred to Phase 2 (creator UI):** live per-stem faders,
step-grid editing UI, the chord-editor UI, punch-in FX triggers, swing/tempo/key
controls, save-as-Asset, stereo. All are UI/persistence layers on top of this
engine and belong in the Phase 2 spec.

**Placeholder scan:** none — every code step has complete code; commands have
expected output.

**Type consistency:** `InstrumentID`, `Chord`/`ChordQuality`, `RiddimPattern`
(`secondsPerStep`, `time(ofStep:)`, `activeSteps`, `bar(ofStep:)`),
`SampleLibrary` (`buffer(for:)`, `rootMidiNote(for:)`), `RiddimEngine`
(`load(preset:)`, `setProgression`, `renderLoopBuffer`, `renderProcessedLoop`,
`renderToFile`), `RiddimPreset.oneDrop` / `RiddimPresetRef.oneDrop`,
`SoundManager.loadCustomMusic(fileURL:)` — names are used consistently across
tasks.

**Known risk:** exact AVFoundation manual-rendering and `AVAudioConverter` call
shapes may need small compile-time adjustments on first build; the patterns
mirror `MusicEngine.swift`/`SoundManager.swift` which already compile in this
project. Treat the first `xcodebuild` of Tasks 4–7 as the integration checkpoint.
