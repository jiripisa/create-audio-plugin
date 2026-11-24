import AudioToolbox
import Foundation
import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// Melodic playing on the keyboard: Voice Mode (Poly, Mono, Legato), Glide and the sustain pedal
/// (CC 64). Pads play as they always do, whatever the voice mode, and the pedal holds no pad.
@Suite("Voice modes")
struct VoiceModeTests: EngineHarness {

    static let poly: Float = 0, mono: Float = 1, legato: Float = 2

    private func noteOn(_ engine: OpaquePointer, _ note: Int32, velocity: Int32 = 100) {
        {{APP_C}}_midi(engine, 0x90, note, velocity, 0)
    }
    private func noteOff(_ engine: OpaquePointer, _ note: Int32) { {{APP_C}}_midi(engine, 0x80, note, 0, 0) }
    private func controller(_ engine: OpaquePointer, _ cc: Int32, _ value: Int32) { {{APP_C}}_midi(engine, 0xB0, cc, value, 0) }
    private func pedal(_ engine: OpaquePointer, down: Bool) { controller(engine, 64, down ? 127 : 0) }
    private func sounding(_ engine: OpaquePointer) -> Int { Int({{APP_C}}_sounding_voices(engine)) }

    /// A note's frequency at Octave 0, Tune 0 and no bend.
    static func hz(_ note: Double) -> Double { 440 * exp2((note - 69) / 12) }

    /// The fundamental of `x` as a (fractional) MIDI note.
    private func note(of x: [Float], expected: Double) -> Double {
        69 + 12 * log2(fundamental(x, rate: Self.rate, expected: Self.hz(expected)) / 440)
    }

    /// The note `engine` sounds over its next 0.2 s.
    private func sounded(_ engine: OpaquePointer, expected: Double) -> Double {
        note(of: render(engine, seconds: 0.2), expected: expected)
    }

    private func peakDb<C: Collection>(_ x: C) -> Double where C.Element == Float {
        20 * log10(Double(x.map { abs($0) }.max() ?? 0) + 1e-12)
    }

    /// Renders until no voice sounds, for at most the tail time and a second: whether it got there.
    private func fallsSilent(_ engine: OpaquePointer) -> Bool {
        for _ in 0..<Int(({{APP_C}}_tail_time() + 1) * Self.rate / 128) {
            _ = render(engine, frames: 128)
            if sounding(engine) == 0 { return true }
        }
        return false
    }

    /// How far below the voice left alone the one `release` releases is, 0.2 ... 0.3 s later: the
    /// same `history` on two engines, one of which then gets `release`.
    private func releaseDrop(_ knobs: [String: Float], history: (OpaquePointer) -> Void,
                             release: (OpaquePointer) -> Void) -> Double {
        let held = makeEngine(knobs), released = makeEngine(knobs)
        defer { {{APP_C}}_destroy(held); {{APP_C}}_destroy(released) }
        history(held)
        history(released)
        release(released)
        let window = Self.frames(0.2)...
        let a = render(held, seconds: 0.3)[window], b = render(released, seconds: 0.3)[window]
        return 20 * log10(rms(a) / max(rms(b), 1e-12))
    }

    // MARK: - Poly, Mono, Legato

    @Test("Poly: a chord sounds a voice per note")
    func polyChordSoundsThreeVoices() {
        let engine = makeEngine(["voicemode": Self.poly])
        defer { {{APP_C}}_destroy(engine) }
        for note: Int32 in [60, 64, 67] { noteOn(engine, note) }
        _ = render(engine, seconds: 0.1)
        #expect(sounding(engine) == 3)
    }

    @Test("Mono: one voice, the last note held; letting it go returns to the note still held, letting that go releases")
    func monoLastNotePriority() {
        let engine = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(engine) }
        noteOn(engine, 60)
        _ = render(engine, seconds: 0.1)
        noteOn(engine, 64)
        _ = render(engine, seconds: 0.05)
        #expect(sounding(engine) == 1)
        let newest = sounded(engine, expected: 64)
        #expect(abs(newest - 64) * 100 < 5, "\(newest)")
        noteOff(engine, 64)
        _ = render(engine, seconds: 0.02)
        #expect(sounding(engine) == 1)
        let back = sounded(engine, expected: 60)
        #expect(abs(back - 60) * 100 < 5, "\(back)")

        noteOff(engine, 60)
        #expect(fallsSilent(engine))
        let drop = releaseDrop(["voicemode": Self.mono], history: { engine in
            noteOn(engine, 60)
            _ = render(engine, seconds: 0.1)
            noteOn(engine, 64)
            _ = render(engine, seconds: 0.1)
            noteOff(engine, 64)
            _ = render(engine, seconds: 0.1)
        }, release: { noteOff($0, 60) })
        #expect(drop > 20, "\(drop) dB")
    }

    // A note held for a second has died away some; a new attack rises above it, a legato note
    // goes on from it.
    @Test("Legato: an overlapping note goes on without a new attack, at its own pitch; Mono attacks it anew")
    func legatoNoReattack() {
        func change(_ mode: Float) -> (rise: Double, note: Double) {
            let engine = makeEngine(["voicemode": mode])
            defer { {{APP_C}}_destroy(engine) }
            noteOn(engine, 60)
            let before = render(engine, seconds: 1.0).suffix(Self.frames(0.02))
            noteOn(engine, 64)
            let after = render(engine, seconds: 0.02)
            _ = render(engine, seconds: 0.03)
            return (peakDb(after) - peakDb(before), sounded(engine, expected: 64))
        }
        let legato = change(Self.legato), mono = change(Self.mono)
        #expect(legato.rise < 1, "\(legato.rise) dB")
        #expect(abs(legato.note - 64) * 100 < 5, "\(legato.note)")
        #expect(mono.rise > 6, "\(mono.rise) dB")
        #expect(abs(mono.note - 64) * 100 < 5, "\(mono.note)")
    }

    @Test("Glide: the pitch moves to the new note over the glide time, in Legato and in Mono")
    func glideTime() {
        for mode in [Self.legato, Self.mono] {
            let engine = makeEngine(["voicemode": mode, "glide": 100])
            defer { {{APP_C}}_destroy(engine) }
            noteOn(engine, 60)
            _ = render(engine, seconds: 0.5)
            noteOn(engine, 72)
            let out = render(engine, seconds: 0.35)
            let halfway = note(of: Array(out[Self.frames(0.045)..<Self.frames(0.055)]), expected: 66)
            #expect(halfway > 63 && halfway < 69, "mode \(mode): \(halfway)")
            let arrived = note(of: Array(out[Self.frames(0.15)...]), expected: 72)
            #expect(abs(arrived - 72) * 100 < 5, "mode \(mode): \(arrived)")
        }
    }

    @Test("A voice mode changed while voices sound leaves none hanging once every key is up")
    func modeChangeWhileSounding() {
        let engine = makeEngine(["voicemode": Self.poly])
        defer { {{APP_C}}_destroy(engine) }
        for note: Int32 in [60, 64, 67] { noteOn(engine, note) }
        _ = render(engine, seconds: 0.1)
        #expect(sounding(engine) == 3)
        setKnobs(engine, ["voicemode": Self.mono])
        _ = render(engine, seconds: 0.05)
        noteOn(engine, 70)
        _ = render(engine, seconds: 0.05)
        for note: Int32 in [60, 64, 67, 70] { noteOff(engine, note) }
        #expect(fallsSilent(engine))

        // And back: two notes held in Mono, then Poly.
        noteOn(engine, 60)
        noteOn(engine, 64)
        _ = render(engine, seconds: 0.05)
        setKnobs(engine, ["voicemode": Self.poly])
        _ = render(engine, seconds: 0.05)
        noteOff(engine, 64)
        noteOff(engine, 60)
        #expect(fallsSilent(engine))
    }

    @Test("Pitch bend bends a Mono voice")
    func bendInMono() {
        let engine = makeEngine(["voicemode": Self.mono, "bendup": 2])
        defer { {{APP_C}}_destroy(engine) }
        noteOn(engine, 60)
        {{APP_C}}_midi(engine, 0xE0, 0x7F, 0x7F, 0)       // all the way up
        _ = render(engine, seconds: 0.05)
        let bent = sounded(engine, expected: 62)
        #expect(abs(bent - 62) * 100 < 5, "\(bent)")
    }

    @Test("Pads play as always, whatever the voice mode")
    func padsIgnoreVoiceMode() {
        let engine = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
        for pad: Int32 in 0..<3 { {{APP_C}}_set_plain(engine, pad + 1, Self.index("voicemode"), Self.mono) }
        for pad: Int32 in 0..<3 { noteOn(engine, Int32({{APP_UPPER}}_FIRST_PAD_NOTE) + pad) }
        _ = render(engine, seconds: 0.05)
        #expect(sounding(engine) == 3)
    }

    // MARK: - Sustain

    @Test("Sustain holds a released key until the pedal comes up, which then releases it as its note-off would have")
    func sustainHoldsReleased() {
        let engine = makeEngine(["voicemode": Self.poly])
        defer { {{APP_C}}_destroy(engine) }
        pedal(engine, down: true)
        noteOn(engine, 60)
        var out = render(engine, seconds: 0.05)
        noteOff(engine, 60)
        out += render(engine, seconds: 0.5)
        #expect(sounding(engine) == 1)
        pedal(engine, down: false)
        out += render(engine, seconds: 1.0)

        // The same note, its key let go when the pedal came up.
        let plain = makeEngine(["voicemode": Self.poly])
        defer { {{APP_C}}_destroy(plain) }
        noteOn(plain, 60)
        var expected = render(plain, seconds: 0.05)
        expected += render(plain, seconds: 0.5)
        noteOff(plain, 60)
        expected += render(plain, seconds: 1.0)
        let r = residualDb(out, expected)
        #expect(r < -100, "residual \(r) dB")
        #expect(fallsSilent(engine))
    }

    @Test("Sustain in Mono: the last note sounds on after its key is let go; the pedal coming up releases it")
    func sustainWithMono() {
        let history: (OpaquePointer) -> Void = { engine in
            pedal(engine, down: true)
            noteOn(engine, 60)
            _ = render(engine, seconds: 0.1)
            noteOff(engine, 60)
            _ = render(engine, seconds: 0.1)
            noteOn(engine, 64)
            _ = render(engine, seconds: 0.1)
            noteOff(engine, 64)
            _ = render(engine, seconds: 0.3)
        }
        let engine = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(engine) }
        history(engine)
        #expect(sounding(engine) == 1)
        let held = sounded(engine, expected: 64)
        #expect(abs(held - 64) * 100 < 5, "\(held)")
        pedal(engine, down: false)
        #expect(fallsSilent(engine))

        let drop = releaseDrop(["voicemode": Self.mono], history: history, release: { pedal($0, down: false) })
        #expect(drop > 20, "\(drop) dB")
    }

    @Test("Pads ignore the pedal: a pad's note-off releases it")
    func padsIgnoreSustain() {
        func play(pedalDown: Bool) -> [Float] {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
            if pedalDown { pedal(engine, down: true) }
            let note = Int32({{APP_UPPER}}_FIRST_PAD_NOTE)
            noteOn(engine, note)
            var out = render(engine, seconds: 0.1)
            noteOff(engine, note)
            out += render(engine, seconds: 1.0)
            return out
        }
        let r = residualDb(play(pedalDown: true), play(pedalDown: false))
        #expect(r < -100, "residual \(r) dB")
    }

    @Test("Reset All Controllers and All Notes Off put the pedal up and forget the keys held")
    func resetsClearPedalAndKeys() {
        for cc: Int32 in [121, 123] {
            // The pedal: a key let go while it was down is released by the reset (121; 123 silences
            // it anyway), and a key let go after the reset is released at once.
            let drop = releaseDrop(["voicemode": Self.poly], history: { engine in
                pedal(engine, down: true)
                noteOn(engine, 60)
                _ = render(engine, seconds: 0.1)
                noteOff(engine, 60)
                _ = render(engine, seconds: 0.1)
            }, release: { controller($0, cc, 0) })
            #expect(drop > 20, "CC \(cc): \(drop) dB")
            let after = releaseDrop(["voicemode": Self.poly], history: { engine in
                pedal(engine, down: true)
                controller(engine, cc, 0)
                noteOn(engine, 62)
                _ = render(engine, seconds: 0.1)
            }, release: { noteOff($0, 62) })
            #expect(after > 20, "CC \(cc): \(after) dB")

            // The keys: two held in Mono, the reset, then a third let go releases the voice
            // instead of returning to one of the two.
            let keys = releaseDrop(["voicemode": Self.mono], history: { engine in
                noteOn(engine, 60)
                noteOn(engine, 64)
                _ = render(engine, seconds: 0.05)
                controller(engine, cc, 0)
                noteOn(engine, 67)
                _ = render(engine, seconds: 0.1)
            }, release: { noteOff($0, 67) })
            #expect(keys > 20, "CC \(cc): \(keys) dB")
        }
    }

    // MARK: - The Audio Unit

    @Test("The Audio Unit's saved state keeps the voice mode and the glide")
    @MainActor
    func auStateRoundTripsVoiceMode() throws {
        let saved = try Instrument()
        try saved.setParameter("voicemode", to: Self.legato)
        try saved.setParameter("glide", to: 250)
        _ = try saved.render()
        let state = try saved.classInfo()

        let restored = try Instrument()
        try restored.restore(state)
        _ = try restored.render()
        let mode = try #require(Parameters.named("voicemode")), glide = try #require(Parameters.named("glide"))
        #expect(try restored.parameter(mode.index) == Self.legato)
        #expect(abs(try restored.parameter(glide.index) - 250) < 0.01)
        let engine = try restored.engine()
        #expect({{APP_C}}_get_plain(engine, Self.keyboard, Int32(mode.index)) == Self.legato)
        #expect(abs({{APP_C}}_get_plain(engine, Self.keyboard, Int32(glide.index)) - 250) < 0.5)
    }
}
