import AppKit

/// APILA's own feedback sounds, synthesized at launch (no audio files):
/// a soft two-step shutter when a capture opens, a short rising "bloop" on
/// copy. Off with Settings → General → Sounds.
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

    /// Two muffled clicks 55 ms apart, each a lowpassed noise tick on a low thump.
    static func shutter() -> [Float] {
        var out = [Float](repeating: 0, count: Int(rate * 0.16))
        var seed: UInt32 = 0x4150
        for (start, gain, pitch) in [(0.0, 0.55, 190.0), (0.055, 0.4, 240.0)] {
            var low: Double = 0
            for i in 0..<Int(rate * 0.06) {
                let t = Double(i) / rate
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Double(seed) / Double(UInt32.max) * 2 - 1
                low += 0.35 * (noise - low)                                   // one-pole lowpass
                let tick = low * exp(-t / 0.004)
                let thump = sin(2 * .pi * pitch * t) * exp(-t / 0.018) * 0.6
                out[Int(start * rate) + i] += Float(gain * (tick + thump))
            }
        }
        return out
    }

    /// A sine gliding up a fifth (A5 → E6) with a soft attack and quick fade.
    static func bloop() -> [Float] {
        var phase = 0.0
        return (0..<Int(rate * 0.18)).map { i in
            let t = Double(i) / rate
            let f = 880 * pow(1.5, min(t / 0.05, 1))
            phase += 2 * .pi * f / rate
            let envelope = min(t / 0.004, 1) * exp(-t / 0.045)
            return Float(0.35 * envelope * (sin(phase) + 0.15 * sin(2 * phase)))
        }
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
