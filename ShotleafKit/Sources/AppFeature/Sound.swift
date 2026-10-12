import AppKit

/// Shotleaf's own feedback sounds, synthesized at launch (no audio files):
/// a soft leaf "shhf" when a capture opens, two quick wooden notes on copy. Off with Settings → General → Sounds.
@MainActor
enum Sound {
    static let key = "sounds"
    private static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    private static let shutterSound = NSSound(data: Synth.wav(Synth.shutter()))
    private static let copySound = NSSound(data: Synth.wav(Synth.bloop()))

    static func shutter() { play(shutterSound) }
    static func copied() { play(copySound) }

    private static func play(_ sound: NSSound?) {
        guard on, let sound else { return }
        sound.stop()
        sound.play()
    }
}

/// Tiny synth: samples in -1…1 at 44.1 kHz, written as 16-bit mono WAV.
enum Synth {
    static let rate = 44_100.0

    /// A soft "shhf" like a leaf brushing past: band-limited noise that swells
    /// in and fades out, no clicks.
    static func shutter() -> [Float] {
        var seed: UInt32 = 0x4150
        var fast = 0.0, slow = 0.0
        let length = 0.16
        return (0..<Int(rate * length)).map { i in
            let t = Double(i) / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            fast += 0.45 * (noise - fast)            // drop the hiss
            slow += 0.04 * (fast - slow)             // and the rumble
            let swell = sin(.pi * min(t / length, 1))
            return Float(0.5 * (fast - slow) * swell * swell)
        }
    }

    /// Two quick wooden notes (E6, A6), marimba-like: a sine with a faint
    /// fourth partial, struck and fading. Steady pitch.
    static func bloop() -> [Float] {
        var out = [Float](repeating: 0, count: Int(rate * 0.22))
        for (start, f, gain) in [(0.0, 1318.5, 0.28), (0.06, 1760.0, 0.32)] {
            for i in 0..<Int(rate * 0.16) {
                let t = Double(i) / rate
                let envelope = min(t / 0.002, 1) * exp(-t / 0.04)
                let tone = sin(2 * .pi * f * t) + 0.12 * sin(2 * .pi * 4 * f * t) * exp(-t / 0.008)
                out[Int(start * rate) + i] += Float(gain * envelope * tone)
            }
        }
        return out
    }

    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        for s in samples { put(Int16(max(-1, min(1, s)) * Float(Int16.max))) }
        return data
    }
}
