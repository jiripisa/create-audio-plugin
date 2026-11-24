import Foundation
import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// Pad mode: sixteen pads, each a key press frozen with its own knob set and pitch; the pads of a
/// group share one voice; Send to pad, and the kit the engine starts with.
@Suite("Pads")
struct PadTests: EngineHarness {

    static let pads = Int32({{APP_UPPER}}_MODE_PADS)
    static let firstPadNote = Int32({{APP_UPPER}}_FIRST_PAD_NOTE)

    /// A fresh engine in pad mode. Every pad plays the first program with `knobs`, at note 47
    /// (B2) with its group Off; the keyboard set has the same knobs.
    private func makePads(_ knobs: [String: Float] = [:]) -> OpaquePointer {
        let sound = knobs
        let engine = makeEngine(sound)
        {{APP_C}}_set_mode(engine, Self.pads)
        for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) {
            {{APP_C}}_set_program(engine, pad + 1, 0)
            setKnobs(engine, sound, set: pad + 1)
            {{APP_C}}_set_pad_note(engine, pad, 47)
            {{APP_C}}_set_pad_group(engine, pad, 0)
        }
        return engine
    }

    private func hitPad(_ engine: OpaquePointer, _ pad: Int32, velocity: Int32 = 110) {
        {{APP_C}}_midi(engine, 0x90, Self.firstPadNote + pad, velocity, 0)
    }

    /// `seconds` of a fresh pad engine with `knobs`, prepared by `setup`, playing `hits`: each a
    /// pad and the time it is hit at, in order.
    private func play(_ hits: [(pad: Int32, at: Double)], seconds: Double = 1.5, _ knobs: [String: Float] = [:],
                      setup: (OpaquePointer) -> Void = { _ in }) -> [Float] {
        let engine = makePads(knobs)
        defer { {{APP_C}}_destroy(engine) }
        setup(engine)
        var out: [Float] = []
        for hit in hits {
            out += render(engine, frames: Self.frames(hit.at) - out.count)
            hitPad(engine, hit.pad)
        }
        return out + render(engine, frames: Self.frames(seconds) - out.count)
    }

    private func sum(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { $0 + $1 } }

    // MARK: - A pad is a frozen key press

    @Test("A pad hit is a frozen key press")
    func frozenKeyPress() {
        // A set unlike the defaults, at a pitch moved by its own Octave and Tune.
        let first = TestKnobs.first
        let sound: [String: Float] = [first.identifier: first.plain(0.7), "pan": 20, "octave": -1, "tune": 30]
        let key = makeEngine(sound)
        defer { {{APP_C}}_destroy(key) }
        {{APP_C}}_midi(key, 0x90, 55, 110, 0)
        let played = render(key, seconds: 1.5)

        let engine = makeEngine(sound)
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 55, 110, 0)
        _ = render(engine, frames: 128)
        {{APP_C}}_send_to_pad(engine, 5)
        {{APP_C}}_reset(engine)                       // silence; the pads stay as they are
        {{APP_C}}_set_mode(engine, Self.pads)
        hitPad(engine, 5)
        let r = residualDb(render(engine, seconds: 1.5), played)
        #expect(r < -100, "residual \(r) dB")
    }

    // Volume, which a voice reads at every control tick, turned to the bottom halfway into a
    // note.
    @Test("Pads ignore later knob changes; keyboard voices follow them")
    func padsAreFrozen() {
        func play(_ mode: Int32, turnAtHalf: Bool) -> [Float] {
            let engine = makePads()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, mode)
            {{APP_C}}_midi(engine, 0x90, 36, 110, 0)
            var out = render(engine, seconds: 0.5)
            if turnAtHalf {
                for set: Int32 in 0..<Int32({{APP_UPPER}}_NUM_SETS) { {{APP_C}}_set_plain(engine, set, Self.index("volume"), -40) }
            }
            out += render(engine, seconds: 0.5)
            return out
        }
        let pad = play(Self.pads, turnAtHalf: true)
        #expect(rms(pad) > 0.001)
        #expect(pad == play(Self.pads, turnAtHalf: false))
        let half = Self.frames(0.5)
        let keyboard = Int32({{APP_UPPER}}_MODE_KEYBOARD)
        let drop = 20 * log10(rms(play(keyboard, turnAtHalf: true)[half...]) / rms(play(keyboard, turnAtHalf: false)[half...]))
        #expect(drop < -30, "the keyboard voice changed by \(drop) dB")
    }

    @Test("Pad mode ignores notes outside 36–51")
    func padModeIgnoresOtherNotes() {
        let engine = makePads()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 35, 110, 0)
        {{APP_C}}_midi(engine, 0x90, 52, 110, 0)
        #expect(render(engine, seconds: 0.5).allSatisfy { $0 == 0 })
        #expect({{APP_C}}_sounding_voices(engine) == 0)
        {{APP_C}}_midi(engine, 0x90, 36, 110, 0)
        {{APP_C}}_midi(engine, 0x90, 51, 110, 0)
        _ = render(engine, frames: 128)
        #expect({{APP_C}}_sounding_voices(engine) == 2)
    }

    // MARK: - Groups: the pads of a group share one voice

    // Volume -12 dB keeps the two notes under the limiter, so that the bus adds them linearly.
    @Test("Same-pitch pads with Group Off sound over each other")
    func groupOffRingsOver() {
        let knobs: [String: Float] = ["volume": -12]
        let both = play([(0, 0), (1, 0.5)], knobs)
        let lone = sum(play([(0, 0)], knobs), play([(1, 0.5)], knobs))
        let r = residualDb(both, lone)
        #expect(r < -100, "residual \(r) dB")
    }

    // Two alike pads of one group: a hit on the second while the first sounds is a hit on the
    // group's one voice, as a second hit on the first pad would be, however the instrument plays
    // a hit on a sounding voice. Without the group the two pads are two voices.
    @Test("The pads of a group share one voice")
    func groupSharesAVoice() {
        let group1: (OpaquePointer) -> Void = { {{APP_C}}_set_pad_group($0, 0, 1); {{APP_C}}_set_pad_group($0, 1, 1) }
        #expect(play([(0, 0), (1, 0.5)], setup: group1) == play([(0, 0), (0, 0.5)], setup: group1))
        for (grouped, voices) in [(true, Int32(1)), (false, 2)] {
            let engine = makePads()
            defer { {{APP_C}}_destroy(engine) }
            if grouped { group1(engine) }
            hitPad(engine, 0)
            _ = render(engine, seconds: 0.5)
            hitPad(engine, 1)
            _ = render(engine, seconds: 0.1)
            #expect({{APP_C}}_sounding_voices(engine) == voices, "grouped: \(grouped)")
        }
    }

    // Pad 2 of the group at another pitch and with its own Tune: once its hit has taken the
    // group's voice, the voice sounds at pad 2's pitch.
    @Test("A hit on a group's voice plays the hit pad's set and pitch")
    func groupHitTakesItsPad() {
        let out = play([(0, 0), (1, 0.5)], seconds: 1.0) { engine in
            {{APP_C}}_set_pad_group(engine, 0, 1); {{APP_C}}_set_pad_group(engine, 1, 1)
            {{APP_C}}_set_pad_note(engine, 1, 54)
            self.setKnobs(engine, ["tune": 50], set: 2)
        }
        let expected = 440 * pow(2, (54 + 0.5 - 69) / 12.0)
        let hz = fundamental(Array(out[Self.frames(0.7)...]), rate: Self.rate, expected: expected)
        #expect(abs(hz / expected - 1) < 0.002, "\(hz) Hz, expected \(expected) Hz")
    }

    /// `first` sounds from 0 s and `second` is hit at 0.5 s, with Volume -12 dB: what the two play
    /// together is the sum of the two alone, so the second hit is not on the first's voice.
    private func ringOver(_ first: Int32, _ second: Int32, setup: @escaping (OpaquePointer) -> Void) -> Double {
        let knobs: [String: Float] = ["volume": -12]
        let both = play([(first, 0), (second, 0.5)], knobs, setup: setup)
        return residualDb(both, sum(play([(first, 0)], knobs, setup: setup), play([(second, 0.5)], knobs, setup: setup)))
    }

    @Test("A hit leaves the voice of another group alone")
    func otherGroupRingsOn() {
        let r = ringOver(0, 1) { {{APP_C}}_set_pad_group($0, 0, 2); {{APP_C}}_set_pad_group($0, 1, 1) }
        #expect(r < -100, "residual \(r) dB")
    }

    @Test("A grouped hit leaves a pad with Group Off alone, and the other way round")
    func groupOffIsApart() {
        let grouped = ringOver(0, 1) { {{APP_C}}_set_pad_group($0, 1, 1) }      // pad 1 Off sounds, pad 2 in group 1 hits
        #expect(grouped < -100, "residual \(grouped) dB")
        let off = ringOver(0, 1) { {{APP_C}}_set_pad_group($0, 0, 1) }          // pad 1 in group 1 sounds, pad 2 Off hits
        #expect(off < -100, "residual \(off) dB")
    }

    @Test("After a reset a hit plays as on a fresh engine, on the keyboard and on the pads")
    func resetPlaysAsFresh() {
        for mode in [Int32({{APP_UPPER}}_MODE_KEYBOARD), Self.pads] {
            let engine = makePads()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, mode)
            {{APP_C}}_midi(engine, 0x90, 36, 110, 0)
            let first = render(engine, seconds: 0.5)
            {{APP_C}}_reset(engine)
            {{APP_C}}_midi(engine, 0x90, 36, 110, 0)
            #expect(render(engine, seconds: 0.5) == first, "mode \(mode)")
        }
    }

    @Test("A velocity-0 note-on is a note-off")
    func velocityZeroIsNoteOff() {
        func release(_ status: Int32?) -> [Float] {
            let engine = makePads()
            defer { {{APP_C}}_destroy(engine) }
            hitPad(engine, 0)
            _ = render(engine, seconds: 0.5)
            if let status { {{APP_C}}_midi(engine, status, 36, 0, 0) }
            _ = render(engine, seconds: 0.4)
            return render(engine, seconds: 0.2)
        }
        let noteOn0 = release(0x90), noteOff = release(0x80), held = release(nil)
        #expect(noteOn0 == noteOff)
        #expect(rms(held) > 0.001)
        #expect(noteOn0 != held)
    }

    // The keyboard's VEL amount on the first instrument knob is 0, pad 4's +100 %, with Vel Sens
    // 0 everywhere and the knob at the top of its travel: a soft hit on the pad moves the knob to
    // the bottom, a soft key does not move it.
    @Test("A pad hit applies its own set's VEL amounts")
    func padVelAmounts() throws {
        let first = TestKnobs.first
        let vel = try #require(Velocity.amount(of: first))
        func level(_ mode: Int32, velocity: Int32) -> Double {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            for set: Int32 in 0..<Int32({{APP_UPPER}}_NUM_SETS) {
                {{APP_C}}_set_plain(engine, set, Self.index("velsens"), 0)
                {{APP_C}}_set_normalised(engine, set, Int32(first.index), 1)
            }
            {{APP_C}}_set_plain(engine, 3 + 1, Int32(vel.index), 100)
            {{APP_C}}_set_plain(engine, Self.keyboard, Int32(vel.index), 0)
            {{APP_C}}_set_mode(engine, mode)
            {{APP_C}}_midi(engine, 0x90, mode == Self.pads ? Self.firstPadNote + 3 : 60, velocity, 0)
            return rms(render(engine, seconds: 0.3))
        }
        let keys = Int32({{APP_UPPER}}_MODE_KEYBOARD)
        let pad = 20 * log10(level(Self.pads, velocity: 127) / level(Self.pads, velocity: 1))
        let key = 20 * log10(level(keys, velocity: 127) / level(keys, velocity: 1))
        #expect(abs(pad) > 6, "pad 4: hard and soft differ by \(pad) dB")
        #expect(abs(key) < 0.1, "keyboard: hard and soft differ by \(key) dB")
    }

    // MARK: - Send to pad and the kit

    @Test("Send to pad copies the set and the last note, and keeps the group")
    func sendToPad() {
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_set_program(engine, Self.keyboard, Int32(TestKnobs.otherProgram))
        setKnobs(engine, [TestKnobs.first.identifier: TestKnobs.first.plain(0.8), "volume": -6, "octave": 1, "lfo1tune": 40])

        {{APP_C}}_send_to_pad(engine, 2)                       // no note played yet: C2
        #expect({{APP_C}}_pad_note(engine, 2) == 36)

        {{APP_C}}_set_pad_group(engine, 3, 5)
        {{APP_C}}_midi(engine, 0x90, 43, 110, 0)
        _ = render(engine, frames: 128)
        {{APP_C}}_send_to_pad(engine, 3)
        #expect({{APP_C}}_pad_note(engine, 3) == 43 && {{APP_C}}_pad_group(engine, 3) == 5)
        #expect({{APP_C}}_get_program(engine, 4) == Int32(TestKnobs.otherProgram))
        for i in 0..<{{APP_C}}_num_params() {
            #expect({{APP_C}}_get_normalised(engine, 4, i) == {{APP_C}}_get_normalised(engine, Self.keyboard, i), "parameter \(i)")
        }

        {{APP_C}}_reset(engine)                                // forgets the last note
        #expect({{APP_C}}_last_note(engine) == -1)
        {{APP_C}}_send_to_pad(engine, 4)
        #expect({{APP_C}}_pad_note(engine, 4) == 36)
    }

    /// Every pad's note, group, program and knobs.
    private func padState(_ engine: OpaquePointer) -> [[Float]] {
        (0..<Int32({{APP_UPPER}}_NUM_PADS)).map { pad in
            [Float({{APP_C}}_pad_note(engine, pad)), Float({{APP_C}}_pad_group(engine, pad)), Float({{APP_C}}_get_program(engine, pad + 1))]
                + (0..<{{APP_C}}_num_params()).map { {{APP_C}}_get_plain(engine, pad + 1, $0) }
        }
    }

    @Test("A new engine's pads hold the default kit: a program in every set, Octave 0")
    func defaultKit() {
        let engine = {{APP_C}}_create()!
        defer { {{APP_C}}_destroy(engine) }
        let octave = Self.index("octave")
        for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) {
            let program = {{APP_C}}_get_program(engine, pad + 1)
            #expect(program >= 0 && program < {{APP_C}}_num_programs(), "pad \(pad + 1)")
            #expect({{APP_C}}_get_plain(engine, pad + 1, octave) == 0, "pad \(pad + 1)")
            #expect((0...127).contains({{APP_C}}_pad_note(engine, pad)), "pad \(pad + 1)")
            #expect((0...Int32({{APP_UPPER}}_NUM_GROUPS)).contains({{APP_C}}_pad_group(engine, pad)), "pad \(pad + 1)")
        }
    }

    @Test("A reset leaves the pads alone; Load Default Kit puts the kit back")
    func resetKeepsPads() {
        let fresh = {{APP_C}}_create()!
        defer { {{APP_C}}_destroy(fresh) }
        let kit = padState(fresh)
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        let other = Int32(TestKnobs.otherProgram)
        for set: Int32 in 1...16 { {{APP_C}}_set_program(engine, set, other); {{APP_C}}_set_plain(engine, set, Self.index("octave"), 2) }
        for pad: Int32 in 0..<16 { {{APP_C}}_set_pad_note(engine, pad, 60); {{APP_C}}_set_pad_group(engine, pad, 16) }
        {{APP_C}}_reset(engine)
        #expect({{APP_C}}_get_program(engine, 1) == other && {{APP_C}}_get_plain(engine, 1, Self.index("octave")) == 2)
        #expect({{APP_C}}_pad_note(engine, 0) == 60 && {{APP_C}}_pad_group(engine, 0) == 16)
        {{APP_C}}_load_default_kit(engine)
        #expect(padState(engine) == kit)
    }

    // MARK: - Modes and wheels

    @Test("Mode switch leaves sounding voices alone")
    func modeSwitch() {
        func play(from: Int32, switching: Bool) -> [Float] {
            let engine = makePads()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, from)
            {{APP_C}}_midi(engine, 0x90, 37, 110, 0)
            var out = render(engine, seconds: 0.5)
            if switching { {{APP_C}}_set_mode(engine, 1 - from) }
            out += render(engine, seconds: 1.0)
            return out
        }
        for mode in [Int32({{APP_UPPER}}_MODE_KEYBOARD), Self.pads] {
            let switched = play(from: mode, switching: true)
            #expect(rms(switched[Self.frames(0.5)...]) > 0.001, "from mode \(mode)")
            #expect(switched == play(from: mode, switching: false), "from mode \(mode)")
        }
    }

    /// A hit on note 36 in `first` mode, and at 0.5 s another on note 36 in the other mode: with
    /// Volume -12 dB, the sum of the two alone. The keyboard's voice and a pad's are not one.
    private func acrossModes(from first: Int32) -> Double {
        func play(firstHit: Bool, secondHit: Bool) -> [Float] {
            let engine = makePads(["volume": -12])
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, first)
            if firstHit { {{APP_C}}_midi(engine, 0x90, 36, 110, 0) }
            var out = render(engine, seconds: 0.5)
            {{APP_C}}_set_mode(engine, 1 - first)
            if secondHit { {{APP_C}}_midi(engine, 0x90, 36, 110, 0) }
            out += render(engine, seconds: 1.0)
            return out
        }
        return residualDb(play(firstHit: true, secondHit: true),
                          sum(play(firstHit: true, secondHit: false), play(firstHit: false, secondHit: true)))
    }

    @Test("A pad hit leaves a sounding key of the same note alone, and the other way round")
    func keysAndPadsApart() {
        let padOverKey = acrossModes(from: Int32({{APP_UPPER}}_MODE_KEYBOARD))
        #expect(padOverKey < -100, "residual \(padOverKey) dB")
        let keyOverPad = acrossModes(from: Self.pads)
        #expect(keyOverPad < -100, "residual \(keyOverPad) dB")
    }

    @Test("Wheels change keyboard voices, not sounding pad voices")
    func wheelsLeavePadsAlone() {
        func play(_ mode: Int32, wheels: Bool) -> [Float] {
            let engine = makePads()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, mode)
            {{APP_C}}_midi(engine, 0x90, 36, 110, 0)
            var out = render(engine, seconds: 0.3)
            if wheels {
                {{APP_C}}_midi(engine, 0xB0, 1, 127, 0)        // mod wheel
                {{APP_C}}_midi(engine, 0xD0, 127, 0, 0)        // aftertouch
                {{APP_C}}_midi(engine, 0xE0, 0x7F, 0x7F, 0)    // pitch bend: the pitch
            }
            out += render(engine, seconds: 1.0)
            return out
        }
        let pad = play(Self.pads, wheels: true)
        #expect(rms(pad) > 0.001)
        #expect(pad == play(Self.pads, wheels: false))
        #expect(play(Int32({{APP_UPPER}}_MODE_KEYBOARD), wheels: true) != play(Int32({{APP_UPPER}}_MODE_KEYBOARD), wheels: false))
    }
}
