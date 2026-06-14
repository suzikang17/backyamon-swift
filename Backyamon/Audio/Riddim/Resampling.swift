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
