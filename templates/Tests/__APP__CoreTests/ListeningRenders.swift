import Foundation
import Testing
@testable import {{APP}}Core

/// Renders for the author to judge by ear, written as 24-bit stereo WAV files into the directory
/// named by `{{APP_UPPER}}_LISTEN_DIR`. Skipped when it is not set. The files carry the engine's real
/// output level (nothing is normalised; the spike's renders are normalised to -1 dBFS); a file
/// whose peak is above -0.5 dBFS fails the test.
@Suite("Listening renders")
struct ListeningRenders {

    private static let directory = ProcessInfo.processInfo.environment["{{APP_UPPER}}_LISTEN_DIR"]
    private static let blockSize = 128
    private static let peakLimitDb = -0.5

    /// Something that happens `time` seconds in: a MIDI message, a knob turned.
    private struct Cue {
        let time: Double
        let action: @Sendable (Synth) -> Void
    }

    private struct Render {
        let name: String
        let sampleRate: Double
        let seconds: Double
        let mode: PlayMode
        let cues: [Cue]
    }

    private struct Rendered {
        let left: [Float]
        let right: [Float]
        var peakDb: Double {
            let peak = max(left.map { abs($0) }.max() ?? 0, right.map { abs($0) }.max() ?? 0)
            return 20 * log10(Double(peak))
        }
    }

    // MARK: Building scores

    private static func midi(_ time: Double, _ status: UInt8, _ data1: UInt8, _ data2: UInt8) -> Cue {
        Cue(time: time) { $0.postMIDI(status: status, data1: data1, data2: data2) }
    }

    private static func set(_ time: Double, _ identifier: String, _ value: Float, in set: SoundSet = .keyboard) -> Cue {
        guard let parameter = Parameters.named(identifier) else { preconditionFailure("unknown knob \(identifier)") }
        return Cue(time: time) { $0.setValue(value, of: parameter, in: set) }
    }

    private static func cues(_ events: [GrooveEvent]) -> [Cue] {
        events.map { midi($0.time, $0.status, $0.data1, $0.data2) }
    }

    /// `count` messages from `from` to `to` seconds, each carrying `value(progress)`, progress 0...1.
    private static func ramp(from: Double, to: Double, every interval: Double = 0.02,
                             _ make: (Double, Double) -> Cue) -> [Cue] {
        let count = Int(((to - from) / interval).rounded())
        return (0...count).map { make(from + Double($0) * interval, Double($0) / Double(count)) }
    }

    private static func bend(_ time: Double, _ position: Int) -> Cue {
        midi(time, 0xE0, UInt8(position & 0x7F), UInt8((position >> 7) & 0x7F))
    }

    // MARK: The renders

    /// The prototype's melody, its first note at 0.2 s.
    private static let melody = PrototypeScores.render(named: "01_tone_melody")

    private static var renders: [Render] {
        var all: [Render] = []

        // The engine's version of every prototype render, under the prototype's name, to be
        // compared with it. Volume -12 dB in every set keeps the limiter out of them.
        for render in PrototypeScores.renders {
            let sets: [SoundSet] = render.pads ? (0..<16).map { .pad($0) } : [.keyboard]
            all.append(Render(name: render.name, sampleRate: 48_000, seconds: render.seconds,
                              mode: render.pads ? .pads : .keyboard,
                              cues: [Cue(time: 0) { PrototypeScores.setUp(render, in: $0) }]
                                  + sets.map { set(0, "volume", -12, in: $0) }
                                  + cues(PrototypeScores.midiEvents(render))))
        }

        // F01: the default kit, every pad, 4 bars at 100 BPM.
        all.append(Render(name: "F01_default_kit_groove", sampleRate: 48_000, seconds: Grooves.defaultKitLength,
                          mode: .pads, cues: cues(Grooves.defaultKit)))

        // F02: the melody with the mod wheel rising from 0 to 127 over 3 s: Brightness from 10 % to 60 %.
        all.append(Render(name: "F02_modwheel_brightness", sampleRate: 48_000, seconds: melody.seconds, mode: .keyboard,
                          cues: [set(0, "brightness", 10), midi(0.1, 0xB0, 1, 0)] + cues(PrototypeScores.midiEvents(melody))
                              + ramp(from: 1.0, to: 4.0) { time, p in midi(time, 0xB0, 1, UInt8((p * 127).rounded())) }))

        // F03: a long note while the bend goes down 2 st, up 2 st and back.
        let long: [GrooveEvent] = [GrooveEvent(0.3, 0x90, 60, 110), GrooveEvent(3.8, 0x80, 60, 0)]
        all.append(Render(name: "F03_pitchbend", sampleRate: 48_000, seconds: 5.5, mode: .keyboard,
                          cues: [set(0, "decay", 20)] + cues(long)
                              + ramp(from: 0.6, to: 1.2) { t, p in bend(t, 8192 - Int(p * 8192)) }
                              + ramp(from: 1.2, to: 2.0) { t, p in bend(t, Int(p * 16383)) }
                              + ramp(from: 2.6, to: 3.6) { t, p in bend(t, 16383 - Int(p * 8191)) }))

        // F04: LFO 1 > Tune at 5 Hz on long notes: off for the first, on (±25 ct) from 2.2 s.
        let held: [GrooveEvent] = [GrooveEvent(0.3, 0x90, 57, 110), GrooveEvent(2.0, 0x80, 57, 0),
                                   GrooveEvent(2.3, 0x90, 64, 100), GrooveEvent(4.3, 0x80, 64, 0)]
        all.append(Render(name: "F04_lfo1_tune_vibrato", sampleRate: 48_000, seconds: 5.5, mode: .keyboard,
                          cues: [set(0, "decay", 20), set(0, "lfo1rate", 5)] + cues(held) + [set(2.2, "lfo1tune", 12.5)]))

        // F05: the kit, the first 2 bars all centre, then spread hard left, hard right and centre.
        let bar = 4 * 60.0 / 100
        let spread: [(pad: Int, pan: Float)] = [(0, -50), (1, 50), (2, -100), (3, 100), (4, -100), (5, 100), (6, 0), (7, 0)]
        all.append(Render(name: "F05_pan_across_pads", sampleRate: 48_000, seconds: Grooves.defaultKitLength,
                          mode: .pads,
                          cues: cues(Grooves.defaultKit) + spread.map { set(0.2 + 2 * bar - 0.05, "pan", $0.pan, in: .pad($0.pad)) }))

        // F06: the melody, first without velocity modulation, then VEL>Attack -60 % and VEL>Brightness
        // 40 %: the soft notes slower at the onset and darker.
        all.append(Render(name: "F06_vel_attack_and_brightness", sampleRate: 48_000, seconds: melody.seconds, mode: .keyboard,
                          cues: cues(PrototypeScores.midiEvents(melody)) + [set(2.4, "velattack", -60), set(2.4, "velbrightness", 40)]))

        // F07: one default note at 44.1 kHz and the same at 96 kHz.
        let note = [GrooveEvent(0.2, 0x90, 60, 110), GrooveEvent(1.2, 0x80, 60, 0)]
        for (suffix, rate) in [("44k1", 44_100.0), ("96k", 96_000.0)] {
            all.append(Render(name: "F07_default_note_44k1_vs_96k_\(suffix)", sampleRate: rate, seconds: 2,
                              mode: .keyboard, cues: cues(note)))
        }
        return all
    }

    // MARK: Rendering and writing

    private static func render(_ spec: Render) -> Rendered {
        let synth = Synth(sampleRate: spec.sampleRate)
        synth.mode = spec.mode
        let cues = spec.cues.sorted { $0.time < $1.time }
        let blocks = Int((spec.seconds * spec.sampleRate).rounded(.up)) / blockSize + 1
        var left = [Float](repeating: 0, count: blocks * blockSize)
        var right = left
        var next = 0
        for block in 0..<blocks {
            let time = Double(block * blockSize) / spec.sampleRate
            while next < cues.count, cues[next].time <= time {
                cues[next].action(synth)
                next += 1
            }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    synth.render(left: l.baseAddress! + block * blockSize, right: r.baseAddress! + block * blockSize,
                                 frames: blockSize)
                }
            }
        }
        return Rendered(left: left, right: right)
    }

    /// A 24-bit PCM stereo WAV file, little-endian.
    private static func wav(_ audio: Rendered, sampleRate: Int) -> Data {
        let frames = audio.left.count
        let dataSize = frames * 6
        var data = Data()
        func append32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        append32(16); append16(1); append16(2); append32(sampleRate); append32(sampleRate * 6); append16(6); append16(24)
        data.append(contentsOf: Array("data".utf8)); append32(dataSize)
        data.reserveCapacity(44 + dataSize)
        for i in 0..<frames {
            for sample in [audio.left[i], audio.right[i]] {
                let value = Int32((min(max(sample, -1), 1) * 8_388_607).rounded())
                data.append(UInt8(truncatingIfNeeded: value))
                data.append(UInt8(truncatingIfNeeded: value >> 8))
                data.append(UInt8(truncatingIfNeeded: value >> 16))
            }
        }
        return data
    }

    @Test("Writes the listening renders", .enabled(if: ListeningRenders.directory != nil))
    func writeRenders() throws {
        let directory = URL(filePath: try #require(Self.directory), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let specs = Self.renders
        #expect(specs.count == PrototypeScores.renders.count + 8)
        for spec in specs {
            let audio = Self.render(spec)
            let url = directory.appending(path: spec.name + ".wav")
            try Self.wav(audio, sampleRate: Int(spec.sampleRate)).write(to: url)
            print(String(format: "%@  %.1f s  peak %.2f dBFS", spec.name, Double(audio.left.count) / spec.sampleRate, audio.peakDb))
            #expect(audio.peakDb <= Self.peakLimitDb, "\(spec.name) peaks at \(audio.peakDb) dBFS")
        }
    }
}
