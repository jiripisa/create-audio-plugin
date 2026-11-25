import Foundation
import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// What moves the knobs while the instrument plays: the velocity's amounts, the two LFOs, the
/// knobs themselves turned while a note sounds, and the wheels.
@Suite("Modulation")
struct ModulationTests: EngineHarness {

    /// One note of B2 at `velocity` on a fresh engine with `knobs`; `before` runs just before the
    /// note-on (for MIDI that sets the wheels).
    private func hit(_ knobs: [String: Float] = [:], velocity: Int32 = 110, seconds: Double = 1.5,
                     before: (OpaquePointer) -> Void = { _ in }) -> [Float] {
        let engine = makeEngine(knobs)
        defer { {{APP_C}}_destroy(engine) }
        before(engine)
        {{APP_C}}_midi(engine, 0x90, 47, velocity, 0)
        return render(engine, seconds: seconds)
    }

    // MARK: - Velocity

    // On Tune, a knob of the platform block that every instrument's velocity can move: the
    // instrument's own knobs may be switches, or may not change what a note sounds like.
    @Test("A VEL amount moves a soft note exactly as far as turning the knob down would")
    func velMatchesKnob() {
        let n0: Float = 0.6                                  // the knob's position at a full note
        let knob = TestKnobs.named("tune"), index = Int32(knob.index)
        let amount = "vel\(knob.identifier)"
        let moved = hit([amount: 60], velocity: 64) { {{APP_C}}_set_normalised($0, Self.keyboard, index, n0) }
        let turned = hit(velocity: 64) {
            {{APP_C}}_set_normalised($0, Self.keyboard, index, n0 - 0.6 * (1 - 64.0 / 127.0))
        }
        let unmoved = hit(velocity: 64) { {{APP_C}}_set_normalised($0, Self.keyboard, index, n0) }
        let r = residualDb(moved, turned)
        #expect(r < -100, "residual \(r) dB")
        #expect(residualDb(moved, unmoved) > -40)            // and the amount did move it
    }

    @Test("A full-velocity note ignores its VEL amounts")
    func velAtFull() {
        let all = Dictionary(uniqueKeysWithValues: Parameters.all.filter { $0.index >= TestKnobs.all.count && $0.identifier.hasPrefix("vel") }
            .map { ($0.identifier, Float(100)) })
        #expect(all.count > 5)
        #expect(hit(all, velocity: 127) == hit(velocity: 127))
    }

    @Test("VEL>Volume scales the level")
    func velVolume() {
        let scaled = hit(["velvolume": 100], velocity: 64)
        let plain = hit(velocity: 64).map { $0 * (64.0 / 127.0) }
        let r = residualDb(scaled, plain)
        #expect(r < -100, "residual \(r) dB")
    }

    @Test("Vel Sens makes a soft note quieter by its share")
    func velSens() {
        let soft = hit(["velsens": 50], velocity: 64)
        let full = hit(["velsens": 0], velocity: 64).map { $0 * Float(1 - 0.5 * (1 - 64.0 / 127.0)) }
        let r = residualDb(soft, full)
        #expect(r < -100, "residual \(r) dB")
    }

    // MARK: - LFOs

    /// Two notes `gap` seconds apart, each held 0.1 s and heard for the first second, the bus
    /// silent again (exactly 0: the voice has retired) before the second, so that nothing of the
    /// first is left in it. LFO 1 moves Tune (a sine), LFO 2 Pan (Steps, which draws random levels).
    private func twoHits(start: Float, gap: Double) -> (first: ArraySlice<Float>, second: ArraySlice<Float>) {
        let engine = makeEngine(["lfostart": start, "lfo1rate": 3, "lfo1tune": 40, "lfo2rate": 5, "lfo2shape": 5, "lfo2pan": 50])
        defer { {{APP_C}}_destroy(engine) }
        let second = Self.frames(gap)
        {{APP_C}}_midi(engine, 0x90, 47, 110, 0)
        var out = render(engine, seconds: 0.1)
        {{APP_C}}_midi(engine, 0x80, 47, 0, 0)
        out += render(engine, frames: second - out.count)
        #expect(out[(second - 128)...].allSatisfy { $0 == 0 }, "the first note is not silent yet")
        {{APP_C}}_midi(engine, 0x90, 47, 110, 0)
        out += render(engine, seconds: 0.1)
        {{APP_C}}_midi(engine, 0x80, 47, 0, 0)
        out += render(engine, seconds: 0.9)
        let one = Self.frames(1)
        return (out[0..<one], out[second..<(second + one)])
    }

    // 2.1 s and not 2 s apart: at 3 Hz, 2 s is a whole number of cycles, so a free-running LFO
    // would come round to the same phase and the two tests could not tell Hit from Free.
    @Test("With LFO Start = Hit every note repeats exactly")
    func lfoHitRepeats() {
        let hits = twoHits(start: 0, gap: 2.1)
        #expect(Array(hits.first) == Array(hits.second))
    }

    @Test("With LFO Start = Free notes differ")
    func lfoFree() {
        let hits = twoHits(start: 1, gap: 2.1)
        let r = residualDb(hits.second, hits.first)
        #expect(r > -30, "residual \(r) dB")
    }

    @Test("An LFO amount moves the sound; amount 0 leaves it alone")
    func lfoAmount() {
        let still = hit()
        let moving = hit(["lfo1rate": 3, "lfo1tune": 40])
        #expect(residualDb(moving, still) > -30)
        // Rates, shapes and the start do nothing while every amount is 0.
        let idle = hit(["lfo1rate": 20, "lfo1shape": 4, "lfo2rate": 0.1, "lfo2shape": 6, "lfostart": 1])
        #expect(idle == still)
    }

    @Test("An LFO on Tune moves the pitch by its share of Tune's travel")
    func lfoOnTune() {
        // LFO 1 a square (+1 for the first half of its cycle) at 0.1 Hz: for the first 5 s it holds
        // Tune 25 % of its 200 cents up, +50 cents.
        let x = hit(["lfo1shape": 4, "lfo1rate": 0.1, "lfo1tune": 25], seconds: 0.6)
        let hz = fundamental(Array(x[Self.frames(0.3)...]), rate: Self.rate, expected: 127)
        let expected = 440 * pow(2, (47 + 0.5 - 69) / 12)
        #expect(abs(hz / expected - 1) < 0.001, "\(hz) Hz, expected \(expected) Hz")
    }

    // MARK: - Live knobs and wheels

    // Tune turned up 100 cents 0.15 s into a note: from there on the note is a semitone higher.
    // Early, so that a note that dies away fast still sounds.
    @Test("A keyboard voice follows the knobs while it sounds")
    func liveKnobs() {
        func play(turnAtHalf: Bool) -> [Float] {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_midi(engine, 0x90, 47, 110, 0)
            var out = render(engine, seconds: 0.15)
            if turnAtHalf { {{APP_C}}_set_plain(engine, Self.keyboard, Self.index("tune"), 100) }
            out += render(engine, seconds: 0.15)
            return out
        }
        let half = Self.frames(0.15)
        let still = play(turnAtHalf: false), turned = play(turnAtHalf: true)
        #expect(still[..<half] == turned[..<half])
        let expected = 440 * pow(2, (48 - 69) / 12.0)
        let hz = fundamental(Array(turned[Self.frames(0.16)...]), rate: Self.rate, expected: expected)
        #expect(abs(hz / expected - 1) < 0.001, "\(hz) Hz, expected \(expected) Hz")
    }

    @Test("Pitch bend bends the note up by Bend Up and down by Bend Down")
    func bend() {
        let b2 = 440 * pow(2, (47 - 69) / 12.0)
        func pitch(_ lsb: Int32, _ msb: Int32, expected: Double) -> Double {
            let x = hit(["bendup": 12, "benddown": 5], seconds: 0.6) { {{APP_C}}_midi($0, 0xE0, lsb, msb, 0) }
            return fundamental(Array(x[Self.frames(0.3)...]), rate: Self.rate, expected: expected)
        }
        let up = 2 * b2, down = b2 * pow(2, -5 / 12.0)               // Bend Up 12 st, Bend Down 5 st
        let bentUp = pitch(0x7F, 0x7F, expected: up), bentDown = pitch(0, 0, expected: down)
        #expect(abs(bentUp / up - 1) < 0.001, "full up: \(bentUp) Hz")
        #expect(abs(bentDown / down - 1) < 0.001, "full down: \(bentDown) Hz")
    }

    @Test("Reset All Controllers puts the wheels back at rest")
    func resetAllControllers() {
        let reset = hit { engine in
            {{APP_C}}_midi(engine, 0xB0, 1, 127, 0)
            {{APP_C}}_midi(engine, 0xD0, 127, 0, 0)
            {{APP_C}}_midi(engine, 0xE0, 0x7F, 0x7F, 0)
            {{APP_C}}_midi(engine, 0xB0, 121, 0, 0)
        }
        #expect(reset == hit())
        #expect(hit { {{APP_C}}_midi($0, 0xE0, 0x7F, 0x7F, 0) } != hit())
    }
}
