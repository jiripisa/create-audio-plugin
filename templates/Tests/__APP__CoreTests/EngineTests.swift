import Accelerate
import Foundation
import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// What the sound engine promises for every instrument: how notes share the voices and end,
/// how it keeps its pitch and its sound at every sample rate, how it shares its voices, and how
/// its C interface copes with what callers hand it.
@Suite("Engine")
struct EngineTests: EngineHarness {

    private static let B2: Int32 = 47

    /// Controllers no knob comes with.
    private static let free = TestKnobs.freeControllers.map(Int32.init)

    @Test("The default note at full velocity stays under the limiter and well above silence")
    func level() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 60, 127, 0)
        let peak = render(engine, seconds: 2).map(abs).max() ?? 0
        #expect(peak > 0.25 && peak < 0.6, "peak \(peak)")
    }

    // MARK: - Keys and voices

    // Every key sounds with a voice of its own; a note-on on a key that sounds takes that key's
    // voice again (continued or replaced, as the instrument plays a re-hit), not one more.
    @Test("Every key has a voice; a re-hit of a sounding key takes no second one")
    func voicePerKey() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        for note: Int32 in [47, 52, 47, 59, 52] {
            {{APP_C}}_midi(engine, 0x90, note, 100, 0)
            _ = render(engine, seconds: 0.05)
        }
        #expect({{APP_C}}_sounding_voices(engine) == 3)
    }

    @Test("A note-off releases its key's voice; a held key sounds on")
    func noteOffReleases() {
        func afterRelease(_ release: Bool) -> Double {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_midi(engine, 0x90, Self.B2, 110, 0)
            _ = render(engine, seconds: 0.3)
            if release { {{APP_C}}_midi(engine, 0x80, Self.B2, 0, 0) }
            _ = render(engine, seconds: 0.6)
            return rms(render(engine, seconds: 0.1))
        }
        let held = afterRelease(false), released = afterRelease(true)
        #expect(held > 0.01)
        #expect(released == 0 || 20 * log10(released / held) < -50, "released \(released), held \(held)")
    }

    @Test("Only the note-off of a voice's own key releases it")
    func noteOffOfAnotherKey() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, Self.B2, 110, 0)
        {{APP_C}}_midi(engine, 0x90, Self.B2 + 7, 110, 0)
        _ = render(engine, seconds: 0.2)
        {{APP_C}}_midi(engine, 0x80, Self.B2, 0, 0)
        {{APP_C}}_midi(engine, 0x80, Self.B2 + 1, 0, 0)       // a key that is not down
        _ = render(engine, seconds: 1.0)
        #expect({{APP_C}}_sounding_voices(engine) == 1)
    }

    @Test("All Sound Off and All Notes Off fade every voice out")
    func allOff() {
        for controller: Int32 in [120, 123] {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_midi(engine, 0x90, 47, 110, 0)
            {{APP_C}}_midi(engine, 0x90, 54, 110, 0)
            _ = render(engine, seconds: 0.2)
            #expect({{APP_C}}_sounding_voices(engine) == 2)
            {{APP_C}}_midi(engine, 0xB0, controller, 0, 0)
            _ = render(engine, seconds: 0.001)
            #expect({{APP_C}}_sounding_voices(engine) == 0, "CC \(controller)")
        }
    }

    // A voice fades 40 dB in 10 ms and leaves at -100 dB, 25 ms on, so nothing is left in the bus.
    @Test("After All Sound Off or All Notes Off the output is silent within 50 ms")
    func allOffFallsSilent() {
        for controller: Int32 in [120, 123] {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_midi(engine, 0x90, 47, 110, 0)
            {{APP_C}}_midi(engine, 0x90, 54, 110, 0)
            #expect((render(engine, seconds: 0.2).map(abs).max() ?? 0) > 0.05)
            {{APP_C}}_midi(engine, 0xB0, controller, 0, 0)
            _ = render(engine, seconds: 0.05)
            #expect(render(engine, seconds: 0.1).allSatisfy { $0 == 0 }, "CC \(controller): still sounding 50 ms after it")
        }
    }

    // The voice leaves the pool once the instrument says it is over: what stops then is far below
    // hearing, at full velocity and at the softest.
    @Test("A note ends without a step when its voice retires")
    func retireIsSilent() throws {
        for velocity: Int32 in [127, 1] {
            let engine = makeEngine(["velsens": 0])
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_midi(engine, 0x90, Self.B2, velocity, 0)
            var y = render(engine, seconds: 0.2), retired: Int?
            {{APP_C}}_midi(engine, 0x80, Self.B2, 0, 0)
            while y.count < Self.frames(6) {
                y += render(engine, frames: 128)
                if retired == nil && {{APP_C}}_sounding_voices(engine) == 0 { retired = y.count }
            }
            let retire = try #require(retired, "the voice has not retired within 6 s")
            let around = y[(retire - Self.frames(0.05))..<min(y.count, retire + Self.frames(0.05))]
            let step = zip(around.dropFirst(), around).map { abs($0 - $1) }.max() ?? 0
            #expect(step == 0 || 20 * log10(step) < -90, "velocity \(velocity): a step of \(20 * log10(step)) dBFS at retire")
        }
    }

    @Test("Silence is exact 20 s after the last note")
    func silenceIsExact() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 47, 127, 0)
        {{APP_C}}_midi(engine, 0x90, 54, 90, 64)
        _ = render(engine, seconds: 20)
        #expect({{APP_C}}_sounding_voices(engine) == 0)
        let tail = render(engine, seconds: 1)
        #expect(tail.allSatisfy { $0 == 0 && $0.sign == .plus })
    }

    @Test("A requested reset silences at the next block")
    func requestedReset() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_post_midi(engine, 0x90, Self.B2, 127, 0)
        #expect((render(engine, seconds: 0.5).map(abs).max() ?? 0) > 0.05)
        {{APP_C}}_request_reset(engine)             // what a host's AudioUnitReset does, from any thread
        #expect(render(engine, frames: 128).allSatisfy { $0 == 0 })
        #expect(render(engine, seconds: 0.5).allSatisfy { $0 == 0 })
        #expect({{APP_C}}_sounding_voices(engine) == 0)
    }

    @Test("A reset forgets the last note; MIDI posted before a requested reset plays after it")
    func resetAndPostedMidi() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 43, 110, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_last_note(engine) == 43)
        {{APP_C}}_reset(engine)
        #expect({{APP_C}}_last_note(engine) == -1)

        {{APP_C}}_post_midi(engine, 0x90, 36, 110, 0)
        {{APP_C}}_request_reset(engine)
        #expect((render(engine, seconds: 0.2).map(abs).max() ?? 0) > 0.05)
        #expect({{APP_C}}_last_note(engine) == 36)
    }

    // A block plays at most 256 events. Posted ones beyond that wait for the next block, so a
    // dense controller stream (a large offline block) does not lose the note at its end.
    @Test("MIDI posted beyond a block's 256 events plays in the next block")
    func postedMidiBeyondABlock() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_post_midi(engine, 0x90, 47, 110, 0)
        for _ in 0..<298 { {{APP_C}}_post_midi(engine, 0xB0, 1, 0, 0) }    // the mod wheel at rest
        {{APP_C}}_post_midi(engine, 0x90, 52, 110, 0)                       // the 300th event
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_last_note(engine) == 47, "the first note did not play, or the last one played in the first block")
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_last_note(engine) == 52, "the last note was lost")
    }

    @Test("MIDI at a sample offset starts the note at that sample")
    func sampleOffset() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, Self.B2, 110, 37)
        let out = render(engine, frames: 128)
        #expect(out[..<37].allSatisfy { $0 == 0 })
        #expect(out[37...].contains { $0 != 0 })
    }

    @Test("Each set keeps its own knobs and program")
    func setsAreSeparate() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let volume = Self.index("volume"), other = Int32(TestKnobs.otherProgram)
        let knob = TestKnobs.programKnob
        {{APP_C}}_set_plain(engine, 5, volume, -20)
        {{APP_C}}_set_program(engine, 3, other)
        #expect(abs({{APP_C}}_get_plain(engine, Self.keyboard, volume)) < 1e-5)               // stored normalised
        #expect(abs({{APP_C}}_get_plain(engine, 5, volume) + 20) < 1e-4)
        #expect({{APP_C}}_get_program(engine, 3) == other && {{APP_C}}_get_program(engine, Self.keyboard) == 0)
        let want = Programs.value(program: TestKnobs.otherProgram, parameter: knob)
        #expect(abs({{APP_C}}_get_plain(engine, 3, Int32(knob.index)) - want) <= 1e-4 * max(1, abs(want)))
        {{APP_C}}_set_normalised(engine, 16, volume, 0.25)
        #expect({{APP_C}}_get_normalised(engine, 16, volume) == 0.25)
    }

    @Test("Recording a set's program changes no knob")
    func programIndexOnly() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let volume = Self.index("volume"), other = Int32(TestKnobs.otherProgram)
        {{APP_C}}_set_plain(engine, 4, volume, -20)
        {{APP_C}}_set_program_index(engine, 4, other)
        #expect({{APP_C}}_get_program(engine, 4) == other)
        #expect(abs({{APP_C}}_get_plain(engine, 4, volume) + 20) < 1e-4)
        {{APP_C}}_set_program_index(engine, 4, -1)
        {{APP_C}}_set_program_index(engine, 4, {{APP_C}}_num_programs())
        #expect({{APP_C}}_get_program(engine, 4) == other)
        {{APP_C}}_set_program_index(engine, -1, 1)
        {{APP_C}}_set_program_index(engine, 17, 1)
        {{APP_C}}_set_program_index(nil, 0, 1)
        #expect({{APP_C}}_get_program(engine, Self.keyboard) == 0)
    }

    @Test("The C interface tolerates a null engine and indices out of range")
    func outOfRange() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let volume = Self.index("volume")
        for set: Int32 in [-1, 17] {
            {{APP_C}}_set_plain(engine, set, volume, -20)
            {{APP_C}}_set_normalised(engine, set, volume, 1)
            {{APP_C}}_set_program(engine, set, 1)
            #expect({{APP_C}}_get_plain(engine, set, volume) == 0 && {{APP_C}}_get_normalised(engine, set, volume) == 0)
            #expect({{APP_C}}_get_program(engine, set) == 0)
        }
        for index: Int32 in [-1, Int32({{APP_C}}_num_params())] {
            {{APP_C}}_set_plain(engine, Self.keyboard, index, -20)
            #expect({{APP_C}}_get_plain(engine, Self.keyboard, index) == 0)
        }
        {{APP_C}}_set_program(engine, Self.keyboard, -1)
        {{APP_C}}_set_program(engine, Self.keyboard, {{APP_C}}_num_programs())
        #expect({{APP_C}}_get_program(engine, Self.keyboard) == 0)
        {{APP_C}}_set_mode(engine, 7)
        #expect({{APP_C}}_get_mode(engine) == Int32({{APP_UPPER}}_MODE_KEYBOARD))
        for pad: Int32 in [-1, 16] {
            {{APP_C}}_set_pad_note(engine, pad, 40)
            {{APP_C}}_set_pad_group(engine, pad, 2)
            {{APP_C}}_send_to_pad(engine, pad)
            #expect({{APP_C}}_pad_note(engine, pad) == -1 && {{APP_C}}_pad_group(engine, pad) == 0)
        }
        let group = {{APP_C}}_pad_group(engine, 0)
        {{APP_C}}_set_pad_group(engine, 0, 17)
        {{APP_C}}_set_pad_group(engine, 0, -1)
        #expect({{APP_C}}_pad_group(engine, 0) == group)
        #expect(abs({{APP_C}}_get_plain(engine, Self.keyboard, volume)) < 1e-5)

        // A null engine: every call returns quietly.
        var left = [Float](repeating: 1, count: 16)
        {{APP_C}}_destroy(nil)
        {{APP_C}}_prepare(nil, 48_000); {{APP_C}}_reset(nil); {{APP_C}}_request_reset(nil)
        {{APP_C}}_set_plain(nil, 0, volume, 1); {{APP_C}}_set_normalised(nil, 0, volume, 1); {{APP_C}}_set_program(nil, 0, 1)
        {{APP_C}}_set_mode(nil, 1); {{APP_C}}_set_pad_note(nil, 0, 40); {{APP_C}}_set_pad_group(nil, 0, 1)
        {{APP_C}}_send_to_pad(nil, 0); {{APP_C}}_load_default_kit(nil)
        {{APP_C}}_post_midi(nil, 0x90, 36, 100, 0); {{APP_C}}_midi(nil, 0x90, 36, 100, 0)
        left.withUnsafeMutableBufferPointer { {{APP_C}}_process(nil, $0.baseAddress, nil, 16) }
        #expect(left.allSatisfy { $0 == 0 })
        #expect({{APP_C}}_get_plain(nil, 0, volume) == 0 && {{APP_C}}_get_program(nil, 0) == 0 && {{APP_C}}_get_mode(nil) == 0)
        #expect({{APP_C}}_latency(nil) == 0 && {{APP_C}}_sounding_voices(nil) == 0 && {{APP_C}}_last_note(nil) == -1)
        #expect({{APP_C}}_pad_note(nil, 0) == -1 && {{APP_C}}_pad_group(nil, 0) == 0)

        var info = {{APP}}ParamInfo()
        {{APP_C}}_param_info(volume, &info)
        {{APP_C}}_param_info(-1, &info)
        #expect(info.identifier == nil && info.kind == 0 && info.maxValue == 0)
    }

    // MARK: - Sample rates and oversampling

    /// A note on 57, A3, rendered by `engine` at `rate`: its fundamental from 0.3 s
    /// to 0.55 s.
    private func steadyPitch(_ engine: OpaquePointer, rate: Double) -> Double {
        {{APP_C}}_midi(engine, 0x90, 57, 110, 0)
        let out = render(engine, seconds: 0.55, at: rate)
        return fundamental(Array(out[Self.frames(0.3, at: rate)...]), rate: rate, expected: 220)
    }

    @Test("The pitch is right at every rate", arguments: [44_100.0, 48_000, 88_200, 96_000, 192_000])
    func pitchAtEveryRate(rate: Double) {
        let engine = makeEngine(rate: rate)
        defer { {{APP_C}}_destroy(engine) }
        let hz = steadyPitch(engine, rate: rate)
        #expect(abs(hz / 220 - 1) < 0.001, "\(rate) Hz: \(hz) Hz")
    }

    /// The share of the power below 20 kHz that lies more than 20 Hz from every harmonic of
    /// `f0`, in dB: what aliasing folds between the harmonics. A Blackman-Harris window over
    /// 0.68-0.74 s from 0.3 s into the note, when the attack is over.
    private func aliasDb(_ x: [Float], rate: Double, f0: Double) -> Double {
        let log2n = vDSP_Length(rate < 88_200 ? 15 : 16)
        let n = 1 << Int(log2n)
        let start = Self.frames(0.3, at: rate)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { preconditionFailure("no FFT") }
        defer { vDSP_destroy_fftsetup(setup) }
        let frame = (0..<n).map { i -> Float in
            let p = 2 * Double.pi * Double(i) / Double(n - 1)
            let w = 0.35875 - 0.48829 * cos(p) + 0.14128 * cos(2 * p) - 0.01168 * cos(3 * p)
            return x[start + i] * Float(w)
        }
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBytes { bytes in
                    vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                power.withUnsafeMutableBufferPointer { m in vDSP_zvmags(&split, 1, m.baseAddress!, 1, vDSP_Length(n / 2)) }
            }
        }
        var between = 0.0, total = 0.0
        for bin in 1..<(n / 2) {
            let hz = Double(bin) * rate / Double(n)
            guard hz < 20_000 else { break }
            total += Double(power[bin])
            if abs(hz - f0 * (hz / f0).rounded()) > 20 { between += Double(power[bin]) }
        }
        return 10 * log10(between / total)
    }

    // A high note (A5 tuned 40 cents down, 860 Hz) at 44.1 kHz with every instrument knob at the
    // top of its travel: what the voices and the 2x stage leave between its harmonics stays far
    // under the -60 dB the platform allows.
    @Test("At 44.1 kHz a high, bright note's alias products stay 60 dB down")
    func aliasing() {
        let rate = 44_100.0
        let f0 = 440 * pow(2, (81 - 40.0 / 100 - 69) / 12)
        let engine = makeEngine(["tune": -40], rate: rate)
        defer { {{APP_C}}_destroy(engine) }
        for knob in TestKnobs.instrument where knob.kind == .continuous {
            {{APP_C}}_set_normalised(engine, Self.keyboard, Int32(knob.index), 1)
        }
        {{APP_C}}_midi(engine, 0x90, 81, 127, 0)
        let alias = aliasDb(render(engine, seconds: 1.2, at: rate), rate: rate, f0: f0)
        print(String(format: "aliasing at 44.1 kHz, 860 Hz, every knob at the top: %.1f dB", alias))
        #expect(alias < -60, "\(alias) dB")
    }

    // Below 88.2 kHz the output is the voices at twice the rate, decimated: the same note at the
    // doubled rate, taken every second sample, lags behind by the decimator's delay. The note is
    // 37 frames into the block at the host rate and 74 at the doubled rate: the same instant.
    @Test("Latency is the decimator's delay")
    func latency() {
        for rate in [44_100.0, 48_000] {
            let host = makeEngine(rate: rate), doubled = makeEngine(rate: 2 * rate)
            defer { {{APP_C}}_destroy(host); {{APP_C}}_destroy(doubled) }
            #expect({{APP_C}}_latency(doubled) == 0)
            let latency = Int({{APP_C}}_latency(host))
            #expect(latency == 29, "\(rate) Hz: the 119-tap filter's centre is 59 samples, 29 pairs and one, in")
            {{APP_C}}_midi(host, 0x90, Self.B2, 110, 37)
            {{APP_C}}_midi(doubled, 0x90, Self.B2, 110, 74)
            let y = render(host, seconds: 0.5, at: rate), z = render(doubled, seconds: 0.5, at: 2 * rate)
            func correlation(_ lag: Int) -> Double {
                var sum = 0.0
                for m in lag..<(y.count - 64) { sum += Double(y[m]) * Double(z[2 * (m - lag)]) }
                return sum
            }
            let best = (0...64).max { correlation($0) < correlation($1) }!
            #expect(abs(best - latency) <= 1, "\(rate) Hz: best lag \(best), latency \(latency)")
            // The decimator has unit gain: the host-rate output is the doubled-rate output taken every
            // second sample and delayed by the latency, to within -60 dB.
            let aligned = (latency..<(y.count - 64)).map { y[$0] }
            let taken = (latency..<(y.count - 64)).map { z[2 * ($0 - latency)] }
            let residual = residualDb(aligned, taken)
            #expect(residual < -60, "\(rate) Hz: the decimated output differs from the doubled-rate one by \(residual) dB")
        }
        for rate in [88_200.0, 96_000, 192_000] {
            let engine = makeEngine(rate: rate)
            defer { {{APP_C}}_destroy(engine) }
            #expect({{APP_C}}_latency(engine) == 0, "\(rate) Hz")
        }
    }

    // A rate change mid-note starts from silence: the first block is exactly zero, and what is
    // played then is what a fresh engine at that rate plays, sample for sample.
    @Test("Re-preparing changes the rate cleanly")
    func rePrepareChangesRate() {
        let engine = makeEngine(rate: 96_000)
        defer { {{APP_C}}_destroy(engine) }
        #expect(abs(steadyPitch(engine, rate: 96_000) / 220 - 1) < 0.001)
        for rate in [44_100.0, 96_000] {
            {{APP_C}}_prepare(engine, rate)                       // the last note still sounds
            let first = render(engine, frames: 128)
            #expect(first.allSatisfy { $0 == 0 }, "\(rate) Hz: the first block after prepare")
            let hz = steadyPitch(engine, rate: rate)
            #expect(abs(hz / 220 - 1) < 0.001, "\(rate) Hz: \(hz) Hz")
            {{APP_C}}_reset(engine)
            {{APP_C}}_midi(engine, 0x90, 57, 110, 0)
            let again = render(engine, seconds: 0.5, at: rate)
            let fresh = makeEngine(rate: rate)
            defer { {{APP_C}}_destroy(fresh) }
            {{APP_C}}_midi(fresh, 0x90, 57, 110, 0)
            #expect(again == render(fresh, seconds: 0.5, at: rate), "\(rate) Hz: differs from a fresh engine")
        }
    }

    // Every knob at its minimum and every knob at its maximum (Pan too: one channel is silent),
    // each played from the lowest note to the highest, hard and soft. (At the minimum every amount
    // is -100 %: the soft notes' VEL amounts move their knobs up, and the LFOs turn Volume up.)
    @Test("Extreme knobs stay finite", arguments: [44_100.0, 96_000])
    func extremeKnobsStayFinite(rate: Double) {
        func play(_ setKnobs: (OpaquePointer) -> Void, notes: [Int32]) -> (left: [Float], right: [Float]) {
            let engine = makeEngine(rate: rate)
            defer { {{APP_C}}_destroy(engine) }
            setKnobs(engine)
            var out: (left: [Float], right: [Float]) = ([], [])
            for note in notes {
                for velocity: Int32 in [127, 1] {
                    {{APP_C}}_midi(engine, 0x90, note, velocity, 0)
                    let part = renderStereo(engine, frames: Self.frames(0.25, at: rate))
                    out.left += part.left; out.right += part.right
                }
            }
            let tail = renderStereo(engine, frames: Self.frames(1, at: rate))
            return (out.left + tail.left, out.right + tail.right)
        }
        let everyNote: [Int32] = [0, 24, 36, 60, 84, 96, 108, 127]
        let all: (Float) -> (OpaquePointer) -> Void = { n in
            { engine in for i in 0..<{{APP_C}}_num_params() { {{APP_C}}_set_normalised(engine, Self.keyboard, i, n) } }
        }
        let cases: [(name: String, render: (left: [Float], right: [Float]))] = [
            ("all at minimum", play(all(0), notes: everyNote)),
            ("all at maximum", play(all(1), notes: everyNote)),
        ]
        for c in cases {
            let samples = c.render.left + c.render.right
            #expect(samples.allSatisfy { $0.isFinite }, "\(rate) Hz, \(c.name): NaN or Inf")
            let peak = samples.map(abs).max() ?? 0
            #expect(peak <= 1, "\(rate) Hz, \(c.name): peak \(peak)")
            #expect(peak > 0, "\(rate) Hz, \(c.name): silent")
        }
    }

    // MARK: - The voice pool

    /// Plays `hits` (note, velocity) at every 32nd note at 120 BPM for 4 s, in `mode`, with the
    /// first program in every set and every pad on C2 with its group Off, and checks the pool
    /// after every block.
    private func flood(rate: Double, mode: Int32, hits: (Int) -> [(note: Int32, velocity: Int32)]) {
        let engine = makeEngine(rate: rate)
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_set_mode(engine, mode)
        for set: Int32 in 0..<Int32({{APP_UPPER}}_NUM_SETS) {
            {{APP_C}}_set_program(engine, set, 0)
        }
        for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) { {{APP_C}}_set_pad_group(engine, pad, 0); {{APP_C}}_set_pad_note(engine, pad, 36) }
        let step = 60.0 / 120 / 8, total = Self.frames(4, at: rate)
        var out = [Float](repeating: 0, count: total)
        var nextStep = 0, start = 0, mostSounding: Int32 = 0
        out.withUnsafeMutableBufferPointer { buffer in
            while start < total {
                let count = min(128, total - start)
                while Self.frames(Double(nextStep) * step, at: rate) < start + count {
                    let offset = Int32(Self.frames(Double(nextStep) * step, at: rate) - start)
                    for hit in hits(nextStep) { {{APP_C}}_midi(engine, 0x90, hit.note, hit.velocity, offset) }
                    nextStep += 1
                }
                {{APP_C}}_process(engine, buffer.baseAddress! + start, nil, Int32(count))
                mostSounding = max(mostSounding, {{APP_C}}_sounding_voices(engine))
                start += count
            }
        }
        let name = mode == Int32({{APP_UPPER}}_MODE_PADS) ? "pads" : "keyboard"
        #expect(mostSounding <= Int32({{APP_UPPER}}_MAX_VOICES), "\(rate) Hz, \(name): \(mostSounding) voices sounded")
        #expect(mostSounding == Int32({{APP_UPPER}}_MAX_VOICES), "\(rate) Hz, \(name): the pool was never full")
        #expect(out.allSatisfy { $0.isFinite }, "\(rate) Hz, \(name): NaN or Inf")
        // No voice is cut: a stolen voice, and one a re-hit replaces, fades in 3 ms. The biggest
        // step is then sixteen loud low voices at once.
        let biggestStep = zip(out.dropFirst(), out).map { abs($0 - $1) }.max() ?? 0
        let bound: Float = rate < 88_200 ? 0.45 : 0.25
        #expect(biggestStep <= bound, "\(rate) Hz, \(name): a step of \(biggestStep)")
    }

    // All 16 pads, each a voice of its own (Group Off), on every 32nd note, each a little softer
    // than the one before it in turn: sixteen pads keep their sixteen voices. And the keyboard
    // running up 24 keys, a key per 32nd note: 24 voices would sound.
    @Test("A flood of notes stays within 16 voices", arguments: [44_100.0, 96_000])
    func stealingStaysBounded(rate: Double) {
        flood(rate: rate, mode: Int32({{APP_UPPER}}_MODE_PADS)) { step in
            (0..<Int32({{APP_UPPER}}_NUM_PADS)).map { (Int32({{APP_UPPER}}_FIRST_PAD_NOTE) + $0, Int32(127 - 3 * ((Int($0) + step) % 16))) }
        }
        flood(rate: rate, mode: Int32({{APP_UPPER}}_MODE_KEYBOARD)) { step in [(Int32(36 + step % 24), Int32(127))] }
    }

    // Twelve keys sound for 5 s while the pads are flooded: the pool of 16 is shared by both
    // origins, so the pads steal keyboard voices and one another, and never more than 16 sound.
    @Test("Pads flooded over sounding keys stay within 16 voices", arguments: [44_100.0, 96_000])
    func mixedFloodStaysBounded(rate: Double) {
        let engine = makeEngine(rate: rate)
        defer { {{APP_C}}_destroy(engine) }
        for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) { {{APP_C}}_set_pad_group(engine, pad, 0) }
        for key: Int32 in 0..<12 { {{APP_C}}_midi(engine, 0x90, 48 + key, 100, 0) }       // twelve keys sound
        var out = render(engine, seconds: 0.2, at: rate)
        #expect({{APP_C}}_sounding_voices(engine) == 12)
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
        let step = 60.0 / 120 / 8, total = Self.frames(3, at: rate)
        var nextStep = 0, start = 0, mostSounding: Int32 = 0
        var padOut = [Float](repeating: 0, count: total)
        padOut.withUnsafeMutableBufferPointer { buffer in
            while start < total {
                let count = min(128, total - start)
                while Self.frames(Double(nextStep) * step, at: rate) < start + count {
                    let offset = Int32(Self.frames(Double(nextStep) * step, at: rate) - start)
                    for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) {
                        {{APP_C}}_midi(engine, 0x90, Int32({{APP_UPPER}}_FIRST_PAD_NOTE) + pad, Int32(127 - 3 * ((Int(pad) + nextStep) % 16)), offset)
                    }
                    nextStep += 1
                }
                {{APP_C}}_process(engine, buffer.baseAddress! + start, nil, Int32(count))
                mostSounding = max(mostSounding, {{APP_C}}_sounding_voices(engine))
                #expect({{APP_C}}_sounding_voices(engine) <= Int32({{APP_UPPER}}_MAX_VOICES))
                start += count
            }
        }
        out += padOut
        #expect(mostSounding <= Int32({{APP_UPPER}}_MAX_VOICES), "\(rate) Hz: \(mostSounding) voices sounded")
        #expect(mostSounding == Int32({{APP_UPPER}}_MAX_VOICES), "\(rate) Hz: the pool was never full")
        #expect(out.allSatisfy { $0.isFinite }, "\(rate) Hz: NaN or Inf")
    }

    // Sixteen keys sound, the first one soft, and a 17th steals the soft key's voice: it fades out
    // in 3 ms as the 17th starts, and from then on what is heard is the other fifteen and the
    // 17th, as if the soft one had never been played.
    @Test("The quietest voice is stolen, with a 3 ms fade")
    func stealsTheQuietest() {
        func play(withSoft: Bool) -> [Float] {
            let engine = makeEngine(["volume": -24])
            defer { {{APP_C}}_destroy(engine) }
            if withSoft { {{APP_C}}_midi(engine, 0x90, 40, 20, 0) }
            for note: Int32 in 41..<56 { {{APP_C}}_midi(engine, 0x90, note, 127, 0) }
            _ = render(engine, seconds: 0.2)
            #expect({{APP_C}}_sounding_voices(engine) == (withSoft ? 16 : 15))
            {{APP_C}}_midi(engine, 0x90, 60, 127, 0)
            let out = render(engine, seconds: 0.3)
            #expect({{APP_C}}_sounding_voices(engine) == 16)
            return out
        }
        let stolen = play(withSoft: true), without = play(withSoft: false)
        let fade = Self.frames(0.010)
        #expect(residualDb(stolen[fade...], without[fade...]) < -100, "after the fade")
        #expect(residualDb(stolen[..<Self.frames(0.002)], without[..<Self.frames(0.002)]) > -60, "the soft voice was cut, not faded")
    }

    @Test("Pad hits are counted per pad, in pad mode only")
    func padHitsCount() {
        let synth = Synth(sampleRate: Self.rate)
        func play(_ frames: Int = 512) {
            var out = [Float](repeating: 0, count: frames)
            out.withUnsafeMutableBufferPointer { synth.render(left: $0.baseAddress!, right: nil, frames: frames) }
        }
        synth.noteOn(36)                                   // keyboard mode: no pad is hit
        play()
        #expect((0..<16).allSatisfy { synth.padHits($0) == 0 })
        synth.mode = .pads
        synth.noteOn(36); play()
        synth.noteOn(36); play()
        synth.noteOn(37); play()
        #expect(synth.padHits(0) == 2 && synth.padHits(1) == 1 && synth.padHits(2) == 0)
        synth.noteOn(60); play()                           // outside 36-51: ignored in pad mode
        #expect(synth.padHits(0) == 2)
        synth.prepare(sampleRate: Self.rate)               // a reset leaves the count alone
        #expect(synth.padHits(0) == 2)
        #expect(synth.padHits(-1) == 0 && synth.padHits(16) == 0)
        #expect({{APP_C}}_pad_hits(nil, 0) == 0)
    }

    // Not a promise but a measure: sixteen voices of the default sound (every pad a voice of its
    // own) for 2 s at 48 kHz, where they run at 96 kHz. The time per voice is printed for the
    // phase's records; it is meaningful in a release build (`swift test -c release`).
    @Test("Sixteen voices render, and the time each takes is measured")
    func cpuPerVoice() {
        let rate = 48_000.0
        let engine = makeEngine(rate: rate)
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
        for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) {
            {{APP_C}}_set_program(engine, pad + 1, 0)
            {{APP_C}}_set_pad_group(engine, pad, 0)
            {{APP_C}}_midi(engine, 0x90, Int32({{APP_UPPER}}_FIRST_PAD_NOTE) + pad, 100, 0)
        }
        let seconds = 2.0
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = render(engine, seconds: seconds, at: rate) }
        #expect({{APP_C}}_sounding_voices(engine) == 16)
        let share = Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds)
        print(String(format: "CPU: 16 voices for %.0f s at 48 kHz took %.3f s: %.2f %% of one core per voice",
                     seconds, share, 100 * share / seconds / 16))
    }

    // MARK: - MIDI controllers

    /// Every knob of every pad's set, normalised.
    private func padSets(_ engine: OpaquePointer) -> [[Float]] {
        (1...Int32({{APP_UPPER}}_NUM_PADS)).map { set in (0..<{{APP_C}}_num_params()).map { {{APP_C}}_get_normalised(engine, set, $0) } }
    }

    /// The knobs: the parameters that come with a controller.
    private static let numKnobs = Int32(Parameters.all.filter { Controllers.standard(for: $0) != nil }.count)

    @Test("A controller moves its keyboard knob: 127 the top, 64 the middle of a bipolar knob; no pad moves")
    func controllerMovesKnob() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))         // a controller moves the keyboard set in pad mode too
        let pads = padSets(engine)
        let first = Int32(TestKnobs.first.index), pan = Self.index("pan")
        let before = {{APP_C}}_changes(engine)

        {{APP_C}}_midi(engine, 0xB0, {{APP_C}}_standard_controller(first), 127, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_get_normalised(engine, Self.keyboard, first) == 1)
        let top = TestKnobs.first.range.upperBound
        #expect(abs({{APP_C}}_get_plain(engine, Self.keyboard, first) - top) <= 1e-5 * max(1, abs(top)))
        #expect({{APP_C}}_changes(engine) != before)

        let moved = {{APP_C}}_changes(engine)
        #expect({{APP_C}}_get_controller(engine, pan) == 10)
        {{APP_C}}_midi(engine, 0xB5, 10, 64, 0)                     // channel 6: any channel will do
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_get_normalised(engine, Self.keyboard, pan) == 0.5)
        #expect({{APP_C}}_get_plain(engine, Self.keyboard, pan) == 0)
        #expect({{APP_C}}_changes(engine) != moved)

        for controller: Int32 in 0...127 where ![120, 121, 123].contains(controller) {
            {{APP_C}}_midi(engine, 0xB0, controller, 127 - controller, 0)
        }
        _ = render(engine, frames: 128)
        #expect(padSets(engine) == pads)
    }

    @Test("A controller is applied at its sample offset, in the order of the block's events")
    func controllerAtItsOffset() {
        let volume = Self.index("volume")
        func sounding() -> OpaquePointer {
            let engine = makeEngine()
            {{APP_C}}_midi(engine, 0x90, Self.B2, 120, 0)
            _ = render(engine, seconds: 0.1)
            return engine
        }
        let atOffset = sounding(), split = sounding(), atStart = sounding(), untouched = sounding()
        defer { for engine in [atOffset, split, atStart, untouched] { {{APP_C}}_destroy(engine) } }

        {{APP_C}}_midi(atOffset, 0xB0, 7, 0, 50)
        let a = render(atOffset, frames: 128)
        var b = render(split, frames: 50)
        {{APP_C}}_midi(split, 0xB0, 7, 0, 0)
        b += render(split, frames: 78)
        {{APP_C}}_midi(atStart, 0xB0, 7, 0, 0)
        let c = render(atStart, frames: 128)

        #expect({{APP_C}}_get_normalised(atOffset, Self.keyboard, volume) == 0)
        #expect(a == b, "the controller did not land at frame 50")
        #expect(Array(a[..<50]) == render(untouched, frames: 50), "the controller acted before frame 50")
        #expect(a != c)
    }

    @Test("A note after a controller in the same block plays the controller's knob")
    func controllerBeforeANote() {
        let first = TestKnobs.first
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let cc = {{APP_C}}_get_controller(engine, Int32(first.index))
        {{APP_C}}_midi(engine, 0x90, Self.B2, 110, 20)
        {{APP_C}}_midi(engine, 0xB0, cc, 0, 10)                       // the knob at its bottom, before the note
        let played = render(engine, frames: 4_096)

        let reference = makeEngine([first.identifier: first.range.lowerBound])
        defer { {{APP_C}}_destroy(reference) }
        {{APP_C}}_midi(reference, 0x90, Self.B2, 110, 20)
        #expect(played == render(reference, frames: 4_096))
    }

    @Test("A knob that learns takes the next controller that moves, and its value")
    func learnTakesNextCC() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let rate = Self.index("lfo1rate")
        let standard = {{APP_C}}_standard_controller(rate)
        #expect({{APP_C}}_learning(engine) == -1)
        {{APP_C}}_learn(engine, rate)
        #expect({{APP_C}}_learning(engine) == rate)
        let before = {{APP_C}}_changes(engine)

        {{APP_C}}_midi(engine, 0xB3, Self.free[0], 127, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_learning(engine) == -1)
        #expect({{APP_C}}_get_controller(engine, rate) == Self.free[0])
        #expect({{APP_C}}_get_normalised(engine, Self.keyboard, rate) == 1)
        #expect({{APP_C}}_changes(engine) != before)

        {{APP_C}}_midi(engine, 0xB0, standard, 0, 0)                 // the one it came with moves it no more
        {{APP_C}}_midi(engine, 0xB0, Self.free[1], 0, 0)             // nor does the next one: learning is over
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_get_normalised(engine, Self.keyboard, rate) == 1)
        #expect({{APP_C}}_get_controller(engine, rate) == Self.free[0])

        {{APP_C}}_learn(engine, rate)
        {{APP_C}}_learn(engine, -1)                                   // called off
        {{APP_C}}_midi(engine, 0xB0, Self.free[2], 0, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_get_controller(engine, rate) == Self.free[0])
        for param: Int32 in [Int32({{APP_C}}_lfo_amount(0, Self.index("tune"))), {{APP_C}}_num_params(), -2] {
            {{APP_C}}_learn(engine, param)                            // an amount, or no parameter: nobody learns
            #expect({{APP_C}}_learning(engine) == -1)
        }
    }

    @Test("A reserved controller is not given to a knob, and does not end a learn")
    func reservedNotTaken() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let rate = Self.index("lfo1rate")
        let standard = {{APP_C}}_standard_controller(rate)
        let reserved: [Int32] = [0, 1, 6, 32, 38, 64] + Array(96...101) + Array(120...127)
        for controller in reserved {
            #expect({{APP_C}}_controller_reserved(controller) == 1, "CC \(controller)")
            {{APP_C}}_set_controller(engine, rate, controller)
            #expect({{APP_C}}_get_controller(engine, rate) == standard, "CC \(controller)")
        }
        #expect({{APP_C}}_controller_reserved(-1) == 1 && {{APP_C}}_controller_reserved(128) == 1)
        {{APP_C}}_set_controller(engine, rate, 128)
        #expect({{APP_C}}_get_controller(engine, rate) == standard)

        {{APP_C}}_learn(engine, rate)
        for controller in reserved where ![120, 121, 123].contains(controller) { {{APP_C}}_midi(engine, 0xB0, controller, 100, 0) }
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_learning(engine) == rate)
        #expect({{APP_C}}_get_controller(engine, rate) == standard)
    }

    @Test("One controller serves one knob")
    func oneControllerOneKnob() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let rate = Self.index("lfo1rate"), firstKnob = Int32(TestKnobs.first.index)
        let cc = {{APP_C}}_standard_controller(firstKnob)
        {{APP_C}}_set_controller(engine, rate, cc)                   // the first instrument knob's
        #expect({{APP_C}}_get_controller(engine, rate) == cc)
        #expect({{APP_C}}_get_controller(engine, firstKnob) == -1)
        let firstBefore = {{APP_C}}_get_normalised(engine, Self.keyboard, firstKnob)
        {{APP_C}}_midi(engine, 0xB0, cc, 127, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_get_normalised(engine, Self.keyboard, rate) == 1)
        #expect({{APP_C}}_get_normalised(engine, Self.keyboard, firstKnob) == firstBefore)

        {{APP_C}}_learn(engine, firstKnob)                                // learnt back
        {{APP_C}}_midi(engine, 0xB0, cc, 0, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_get_controller(engine, firstKnob) == cc && {{APP_C}}_get_controller(engine, rate) == -1)

        {{APP_C}}_set_controller(engine, firstKnob, -1)
        #expect({{APP_C}}_get_controller(engine, firstKnob) == -1)
        {{APP_C}}_reset_controllers(engine)
        for knob: Int32 in 0..<Self.numKnobs {
            #expect({{APP_C}}_get_controller(engine, knob) == {{APP_C}}_standard_controller(knob))
        }
    }

    @Test("Controllers nobody listens to, a changed map and a learn called off leave the sound bit for bit")
    func sameSoundWithoutCC() {
        // Notes on and off over 3 s: (frame, note, velocity), velocity 0 a note-off.
        let notes: [(frame: Int, note: Int32, velocity: Int32)] = (0..<24).flatMap { i -> [(frame: Int, note: Int32, velocity: Int32)] in
            let at = Self.frames(0.1 + Double(i) * 0.12), note = Int32(48 + (i * 5) % 24)
            return [(at, note, Int32(60 + (i * 13) % 60)), (at + Self.frames(0.2), note, 0)]
        }.sorted { $0.frame < $1.frame }
        // Reserved ones with no meaning to the engine (64, the sustain pedal, has one: VoiceModeTests).
        let unheard = Array(Self.free.prefix(4)) + [0, 6, 38, 127]
        func play(_ engine: OpaquePointer, noise: Bool) -> [Float] {
            var out: [Float] = []
            var next = 0
            for block in 0..<Self.frames(3) / 128 {
                let start = block * 128
                while next < notes.count, notes[next].frame < start + 128 {
                    let e = notes[next]
                    {{APP_C}}_midi(engine, e.velocity == 0 ? 0x80 : 0x90, e.note, e.velocity, Int32(e.frame - start))
                    next += 1
                }
                if noise {
                    for controller in unheard {
                        {{APP_C}}_midi(engine, 0xB0, controller, Int32(block % 128), Int32(block % 128))
                    }
                }
                out += render(engine, frames: 128)
            }
            return out
        }
        let quiet = makeEngine()
        defer { {{APP_C}}_destroy(quiet) }
        let busy = makeEngine()
        defer { {{APP_C}}_destroy(busy) }
        {{APP_C}}_set_controller(busy, Self.index("lfo1rate"), {{APP_C}}_standard_controller(Int32(TestKnobs.first.index)))
        {{APP_C}}_set_controller(busy, Self.index("volume"), -1)
        {{APP_C}}_reset_controllers(busy)
        {{APP_C}}_learn(busy, Self.index("volume"))
        {{APP_C}}_learn(busy, -1)
        let before = {{APP_C}}_changes(busy)
        #expect(play(busy, noise: true) == play(quiet, noise: false))
        #expect({{APP_C}}_changes(busy) == before)
    }

    @Test("The controller calls tolerate a null engine and parameters out of range")
    func controllersOutOfRange() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        for param: Int32 in [-1, {{APP_C}}_num_params(), Int32({{APP_C}}_vel_amount(Self.index("volume")))] {
            #expect({{APP_C}}_standard_controller(param) == -1)
            {{APP_C}}_set_controller(engine, param, 40)
            #expect({{APP_C}}_get_controller(engine, param) == -1)
        }
        {{APP_C}}_set_controller(nil, 0, 40); {{APP_C}}_reset_controllers(nil); {{APP_C}}_learn(nil, 0)
        #expect({{APP_C}}_get_controller(nil, 0) == -1 && {{APP_C}}_learning(nil) == -1 && {{APP_C}}_changes(nil) == 0)
    }
}
