import Testing
@testable import {{APP}}Core

/// Guards the sound itself: the references below were taken from the engine, so a change in
/// `{{APP}}DSP` that alters a single sample fails here.
///
/// Each reference holds two things: a fingerprint of every sample, and the level of each second.
/// They tell two cases apart:
/// - levels differ: the sound really changed;
/// - only fingerprints differ, for every score at once and without a change in the engine: a new
///   compiler or macOS rounds differently.
///
/// When a change of the sound is deliberate, say so in the CHANGELOG, run the suite and copy the
/// lines it prints over `references`.
@Suite("Sound")
struct SoundRegressionTests {

    private struct Case {
        let name: String
        let mode: PlayMode
        let setup: @Sendable (Synth) -> Void
        let events: [GrooveEvent]
        let duration: Double
    }

    private static let melody = PrototypeScores.render(named: "01_tone_melody")

    /// A melody on the keyboard with both LFOs and a VEL amount at work, and the default kit's groove.
    private static let scores: [Case] = [
        Case(name: "melody with lfo and vel", mode: .keyboard,
             setup: { synth in
                 for (id, value) in ["lfo1tune": 10, "lfo1rate": 5, "lfo2brightness": 40, "lfo2rate": 0.7, "velattack": -50] as [String: Float] {
                     synth.setValue(value, of: Parameters.named(id)!)
                 }
             },
             events: PrototypeScores.midiEvents(melody), duration: melody.seconds),
        Case(name: "default kit groove", mode: .pads, setup: { _ in },
             events: Grooves.defaultKit, duration: Grooves.defaultKitLength),
    ]
    private static let rates = [48_000.0]
    private static let blockSize = 128

    private struct Reference {
        let score: String
        let sampleRate: Double
        /// FNV-1a over the bits of every sample.
        let fingerprint: UInt64
        /// RMS of each second (the last one is shorter).
        let levels: [Double]

        /// This reference as a line of `references`.
        var sourceLine: String {
            let levelList = levels.map { "\(($0 * 1_000_000).rounded() / 1_000_000)" }.joined(separator: ", ")
            return "Reference(score: \"\(score)\", sampleRate: \(Int(sampleRate)), "
                + "fingerprint: 0x\(String(fingerprint, radix: 16, uppercase: true)), levels: [\(levelList)]),"
        }
    }

    /// Taken on 2026-11-25 from the placeholder engine (Tone), with its level set by its fullest
    /// gesture (`kOutputLevel` 0.125: every level is that of 2026-11-24 times 0.125 / 0.44). A
    /// debug build and a release build rendered the same samples.
    private static let references: [Reference] = [
        Reference(score: "melody with lfo and vel", sampleRate: 48000, fingerprint: 0xBD88F5C63C5EA9AA, levels: [0.041935, 0.037913, 0.043934, 0.041188, 0.033056, 0.034885, 0.0, 0.0]),
        Reference(score: "default kit groove", sampleRate: 48000, fingerprint: 0xB175020558379799, levels: [0.050266, 0.049547, 0.056446, 0.054428, 0.050724, 0.056277, 0.053187, 0.050638, 0.055971, 0.046864, 0.004798, 0.000166, 6e-06]),
    ]

    private static func render(_ score: Case, sampleRate: Double) -> [Float] {
        let synth = Synth(sampleRate: sampleRate)
        synth.mode = score.mode
        score.setup(synth)
        let blocks = Int(score.duration * sampleRate) / blockSize
        var samples: [Float] = []
        samples.reserveCapacity(blocks * blockSize)
        var left = [Float](repeating: 0, count: blockSize)
        var right = [Float](repeating: 0, count: blockSize)
        var next = 0
        for block in 0..<blocks {
            let time = Double(block * blockSize) / sampleRate
            while next < score.events.count, score.events[next].time <= time {
                let event = score.events[next]
                synth.postMIDI(status: event.status, data1: event.data1, data2: event.data2)
                next += 1
            }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    synth.render(left: l.baseAddress!, right: r.baseAddress!, frames: blockSize)
                }
            }
            samples.append(contentsOf: left)
        }
        return samples
    }

    private static func fingerprint(of samples: [Float]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for sample in samples {
            var bits = sample.bitPattern
            for _ in 0..<4 {
                hash = (hash ^ UInt64(bits & 0xFF)) &* 0x0000_0100_0000_01B3
                bits >>= 8
            }
        }
        return hash
    }

    private static func levels(of samples: [Float], sampleRate: Double) -> [Double] {
        let second = Int(sampleRate)
        return stride(from: 0, to: samples.count, by: second).map { start in
            let window = samples[start..<min(start + second, samples.count)]
            let energy = window.reduce(0.0) { $0 + Double($1) * Double($1) }
            return (energy / Double(window.count)).squareRoot()
        }
    }

    @Test("Every score sounds as it did when its reference was taken",
          arguments: SoundRegressionTests.scores.map(\.name), SoundRegressionTests.rates)
    func unchanged(name: String, sampleRate: Double) throws {
        let score = try #require(Self.scores.first { $0.name == name })
        let samples = Self.render(score, sampleRate: sampleRate)
        #expect(samples.allSatisfy { $0.isFinite })
        let actual = Reference(score: name, sampleRate: sampleRate,
                               fingerprint: Self.fingerprint(of: samples),
                               levels: Self.levels(of: samples, sampleRate: sampleRate))
        let expected = try #require(Self.references.first { $0.score == name && $0.sampleRate == sampleRate },
                                    "no reference yet; add: \(actual.sourceLine)")

        try #require(actual.levels.count == expected.levels.count)
        for (second, (level, reference)) in zip(actual.levels, expected.levels).enumerated() {
            #expect(abs(level - reference) <= max(reference * 0.001, 0.000_001),
                    "\(name) at \(Int(sampleRate)) Hz: the level of second \(second) changed from \(reference) to \(level)")
        }
        #expect(actual.fingerprint == expected.fingerprint,
                "\(name) at \(Int(sampleRate)) Hz no longer renders the same samples; now: \(actual.sourceLine)")
    }
}
