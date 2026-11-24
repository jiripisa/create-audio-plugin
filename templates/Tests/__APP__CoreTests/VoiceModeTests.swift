import AudioToolbox
import Foundation
import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// Melodic playing on the keyboard: Voice Mode (Poly, Mono, Legato), Glide and the sustain pedal
/// (CC 64). Pads play as they always do, whatever the voice mode, and the pedal holds no pad.
///
/// What the platform decides (a fresh start or a continuing one, a release, the note the voice of
/// Mono and Legato plays, how far its glide has to go) is read from the engine's probe
/// (`{{APP_C}}_voice_probe`), so that the tests hold for every instrument; what it sounds like is
/// checked only by pitch and against the same notes played another way.
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

    /// The probe after one more block, which plays the MIDI sent before it.
    private func probe(_ engine: OpaquePointer) -> {{APP}}VoiceProbe {
        _ = render(engine, frames: 128)
        return voiceProbe(engine)
    }

    /// A note's frequency at Octave 0, Tune 0 and no bend.
    static func hz(_ note: Double) -> Double { 440 * exp2((note - 69) / 12) }

    /// The fundamental of `x` as a (fractional) MIDI note.
    private func note(of x: [Float], expected: Double) -> Double {
        69 + 12 * log2(fundamental(x, rate: Self.rate, expected: Self.hz(expected)) / 440)
    }

    /// The note `engine` sounds over its next 0.1 s. Measured right after the event that set it,
    /// so that a voice that dies away fast is still well above silence.
    private func sounded(_ engine: OpaquePointer, expected: Double) -> Double {
        note(of: render(engine, seconds: 0.1), expected: expected)
    }

    // MARK: - Poly, Mono, Legato

    @Test("Poly: a chord sounds a voice per note")
    func polyChordSoundsThreeVoices() {
        let engine = makeEngine(["voicemode": Self.poly])
        defer { {{APP_C}}_destroy(engine) }
        for note: Int32 in [60, 64, 67] { noteOn(engine, note) }
        let p = probe(engine)
        #expect(sounding(engine) == 3)
        #expect(p.freshStarts == 3 && p.continuingStarts == 0 && p.keysUnreleased == 3 && p.keysHeld == 3 && p.monoNote == -1)
    }

    @Test("Mono: one voice, the last note held; letting it go returns to the note still held, letting that go releases")
    func monoLastNotePriority() {
        let engine = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(engine) }
        noteOn(engine, 60)
        _ = render(engine, seconds: 0.05)
        noteOn(engine, 64)
        var p = probe(engine)
        #expect(sounding(engine) == 1)
        #expect(p.monoNote == 64 && p.freshStarts == 2 && p.continuingStarts == 0 && p.keysUnreleased == 1 && p.keysHeld == 2)
        let newest = sounded(engine, expected: 64)
        #expect(abs(newest - 64) * 100 < 5, "\(newest)")

        noteOff(engine, 64)
        p = probe(engine)
        #expect(p.monoNote == 60 && p.freshStarts == 2 && p.continuingStarts == 1 && p.releases == 0 && p.keysUnreleased == 1)
        let back = sounded(engine, expected: 60)
        #expect(abs(back - 60) * 100 < 5, "\(back)")

        noteOff(engine, 60)
        p = probe(engine)
        #expect(p.releases == 1 && p.keysUnreleased == 0 && p.keysHeld == 0 && p.continuingStarts == 1)
    }

    @Test("Legato: an overlapping note goes on without a new attack, at its own pitch; Mono, and Legato without overlap, attack anew")
    func legatoNoReattack() {
        func change(_ mode: Float, overlapping: Bool) -> (probe: {{APP}}VoiceProbe, note: Double) {
            let engine = makeEngine(["voicemode": mode])
            defer { {{APP_C}}_destroy(engine) }
            noteOn(engine, 60)
            _ = render(engine, seconds: 0.05)
            if !overlapping { noteOff(engine, 60) }
            noteOn(engine, 64)
            let p = probe(engine)
            return (p, sounded(engine, expected: 64))
        }
        let legato = change(Self.legato, overlapping: true)
        #expect(legato.probe.freshStarts == 1 && legato.probe.continuingStarts == 1 && legato.probe.monoNote == 64)
        #expect(abs(legato.note - 64) * 100 < 5, "\(legato.note)")
        for (mode, overlapping) in [(Self.mono, true), (Self.mono, false), (Self.legato, false)] {
            let fresh = change(mode, overlapping: overlapping)
            #expect(fresh.probe.freshStarts == 2 && fresh.probe.continuingStarts == 0 && fresh.probe.monoNote == 64,
                    "mode \(mode), overlapping \(overlapping)")
            #expect(abs(fresh.note - 64) * 100 < 5, "mode \(mode), overlapping \(overlapping): \(fresh.note)")
            #expect(fresh.probe.keysUnreleased == 1, "mode \(mode), overlapping \(overlapping)")
        }
    }

    @Test("Glide: the pitch moves to the new note over the glide time, in Legato and in Mono, and back on a return")
    func glideTime() {
        for mode in [Self.legato, Self.mono] {
            let engine = makeEngine(["voicemode": mode, "glide": 100])
            defer { {{APP_C}}_destroy(engine) }
            noteOn(engine, 60)
            _ = render(engine, seconds: 0.05)
            noteOn(engine, 72)
            var out = render(engine, seconds: 0.05)
            var p = voiceProbe(engine)
            #expect(p.monoNote == 72 && abs(p.monoGlide + 6) < 0.1, "mode \(mode): \(p.monoGlide)")
            out += render(engine, seconds: 0.005)
            let halfway = note(of: Array(out[Self.frames(0.045)...]), expected: 66)
            #expect(halfway > 63 && halfway < 69, "mode \(mode): \(halfway)")
            _ = render(engine, seconds: 0.095)
            p = probe(engine)
            #expect(p.monoGlide == 0, "mode \(mode): \(p.monoGlide)")
            let arrived = sounded(engine, expected: 72)
            #expect(abs(arrived - 72) * 100 < 5, "mode \(mode): \(arrived)")

            noteOff(engine, 72)                                 // back to 60, gliding down from 72
            p = probe(engine)
            #expect(p.monoNote == 60 && p.monoGlide > 11 && p.monoGlide <= 12, "mode \(mode): \(p.monoGlide)")
        }

        // No glide at Glide 0, nor in Poly.
        let instant = makeEngine(["voicemode": Self.legato, "glide": 0])
        defer { {{APP_C}}_destroy(instant) }
        noteOn(instant, 60)
        noteOn(instant, 72)
        #expect(probe(instant).monoGlide == 0)
        let poly = makeEngine(["voicemode": Self.poly, "glide": 100])
        defer { {{APP_C}}_destroy(poly) }
        noteOn(poly, 60)
        noteOn(poly, 72)
        let p = probe(poly)
        #expect(p.monoNote == -1 && p.keysUnreleased == 2)
    }

    // A note-off the platform skips leaves a voice that no key and no pedal holds: a hang.
    @Test("A voice mode changed while keys and the pedal are down leaves no voice unreleased once every key and the pedal are up")
    func modeChangeWhileSounding() {
        for pedalDown in [false, true] {
            let engine = makeEngine(["voicemode": Self.poly])
            defer { {{APP_C}}_destroy(engine) }
            if pedalDown { pedal(engine, down: true) }
            for note: Int32 in [60, 64, 67] { noteOn(engine, note) }
            #expect(probe(engine).keysUnreleased == 3)
            setKnobs(engine, ["voicemode": Self.mono])
            noteOn(engine, 70)
            #expect(probe(engine).keysUnreleased == 4)
            for note: Int32 in [60, 64, 67, 70] { noteOff(engine, note) }
            var p = probe(engine)
            #expect(p.keysSustained == (pedalDown ? 4 : 0), "pedal \(pedalDown)")
            if pedalDown { pedal(engine, down: false) }
            p = probe(engine)
            #expect(p.keysUnreleased == 0 && p.keysSustained == 0 && p.keysHeld == 0, "pedal \(pedalDown): \(p.keysUnreleased) unreleased")
            #expect(p.releases == 4, "pedal \(pedalDown)")

            // And back: two keys held in Mono, then Poly.
            setKnobs(engine, ["voicemode": Self.mono])
            if pedalDown { pedal(engine, down: true) }
            noteOn(engine, 60)
            noteOn(engine, 64)
            #expect(probe(engine).keysUnreleased == 1)
            setKnobs(engine, ["voicemode": Self.poly])
            noteOff(engine, 64)                                 // no return in Poly: the voice is let go
            p = probe(engine)
            #expect(p.keysUnreleased == (pedalDown ? 1 : 0) && p.keysSustained == (pedalDown ? 1 : 0), "pedal \(pedalDown)")
            #expect(p.continuingStarts == 0, "pedal \(pedalDown)")
            noteOff(engine, 60)
            if pedalDown { pedal(engine, down: false) }
            p = probe(engine)
            #expect(p.keysUnreleased == 0 && p.keysSustained == 0 && p.keysHeld == 0, "pedal \(pedalDown)")
        }
    }

    @Test("Mono remembers the 16 newest keys held; the oldest fall out")
    func moreThanSixteenKeys() {
        let engine = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(engine) }
        for note: Int32 in 40...57 { noteOn(engine, note) }   // 18 keys
        var p = probe(engine)
        #expect(p.keysHeld == 16 && p.monoNote == 57 && p.freshStarts == 18)
        for note: Int32 in stride(from: 57, through: 43, by: -1) {
            noteOff(engine, note)
            p = probe(engine)
            #expect(p.monoNote == note - 1 && p.keysUnreleased == 1, "after \(note)")
        }
        #expect(p.continuingStarts == 15 && p.releases == 0)
        noteOff(engine, 42)                                     // 40 and 41 fell out: nothing to return to
        p = probe(engine)
        #expect(p.keysHeld == 0 && p.keysUnreleased == 0 && p.releases == 1)
        noteOff(engine, 41)
        noteOff(engine, 40)
        p = probe(engine)
        #expect(p.releases == 1 && p.continuingStarts == 15 && p.freshStarts == 18)
    }

    @Test("The same key twice: Mono attacks it anew, Legato goes on to it from another key held; one note-off ends it")
    func sameKeyTwice() {
        for mode in [Self.mono, Self.legato] {
            let engine = makeEngine(["voicemode": mode])
            defer { {{APP_C}}_destroy(engine) }
            noteOn(engine, 60)
            noteOn(engine, 60)
            var p = probe(engine)
            #expect(p.keysHeld == 1 && p.monoNote == 60 && p.freshStarts == 2 && p.continuingStarts == 0, "mode \(mode)")
            noteOff(engine, 60)
            p = probe(engine)
            #expect(p.keysHeld == 0 && p.keysUnreleased == 0 && p.releases == 1, "mode \(mode)")
        }

        // Legato: 60 and 64 held, 60 again goes on to it; letting it go returns to 64.
        let engine = makeEngine(["voicemode": Self.legato])
        defer { {{APP_C}}_destroy(engine) }
        noteOn(engine, 60)
        noteOn(engine, 64)
        noteOn(engine, 60)
        var p = probe(engine)
        #expect(p.keysHeld == 2 && p.monoNote == 60 && p.freshStarts == 1 && p.continuingStarts == 2)
        noteOff(engine, 60)
        p = probe(engine)
        #expect(p.keysHeld == 1 && p.monoNote == 64 && p.continuingStarts == 3 && p.releases == 0)
        noteOff(engine, 64)
        p = probe(engine)
        #expect(p.keysUnreleased == 0 && p.releases == 1)
    }

    @Test("The note-off of a key not held changes nothing")
    func noteOffOfAKeyNotHeld() {
        for mode in [Self.poly, Self.mono, Self.legato] {
            let engine = makeEngine(["voicemode": mode])
            defer { {{APP_C}}_destroy(engine) }
            noteOn(engine, 60)
            noteOn(engine, 64)
            let before = probe(engine)
            noteOff(engine, 62)
            noteOff(engine, 61)
            let after = probe(engine)
            #expect(after.keysHeld == 2 && after.keysUnreleased == before.keysUnreleased && after.releases == 0, "mode \(mode)")
            #expect(after.monoNote == before.monoNote && after.continuingStarts == before.continuingStarts, "mode \(mode)")
        }
    }

    @Test("Pitch bend bends a Mono voice")
    func bendInMono() {
        let engine = makeEngine(["voicemode": Self.mono, "bendup": 2])
        defer { {{APP_C}}_destroy(engine) }
        noteOn(engine, 60)
        {{APP_C}}_midi(engine, 0xE0, 0x7F, 0x7F, 0)       // all the way up
        _ = render(engine, frames: 128)
        let bent = sounded(engine, expected: 62)
        #expect(abs(bent - 62) * 100 < 5, "\(bent)")
    }

    @Test("Pads play as always, whatever the voice mode: no keys, no voice of Mono")
    func padsIgnoreVoiceMode() {
        let engine = makeEngine(["voicemode": Self.mono, "glide": 100])
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
        for pad: Int32 in 0..<3 { setKnobs(engine, ["voicemode": Self.mono, "glide": 100], set: pad + 1) }
        for pad: Int32 in 0..<3 { noteOn(engine, Int32({{APP_UPPER}}_FIRST_PAD_NOTE) + pad) }
        let p = probe(engine)
        #expect(sounding(engine) == 3)
        #expect(p.freshStarts == 3 && p.monoNote == -1 && p.keysHeld == 0 && p.keysUnreleased == 0)
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
        out += render(engine, frames: 128)
        var p = voiceProbe(engine)
        #expect(p.keysSustained == 1 && p.keysUnreleased == 1 && p.releases == 0)
        out += render(engine, seconds: 0.5)
        p = voiceProbe(engine)
        #expect(p.releases == 0 && p.keysSustained == p.keysUnreleased)
        let soundingBefore = sounding(engine)
        pedal(engine, down: false)
        out += render(engine, frames: 128)
        p = voiceProbe(engine)
        #expect(p.keysSustained == 0 && p.keysUnreleased == 0 && Int(p.releases) == soundingBefore)
        out += render(engine, seconds: 1.0)

        // The same note, its key let go when the pedal came up.
        let plain = makeEngine(["voicemode": Self.poly])
        defer { {{APP_C}}_destroy(plain) }
        noteOn(plain, 60)
        var expected = render(plain, seconds: 0.05)
        expected += render(plain, frames: 128)
        expected += render(plain, seconds: 0.5)
        noteOff(plain, 60)
        expected += render(plain, frames: 128)
        expected += render(plain, seconds: 1.0)
        #expect(out == expected)
    }

    @Test("Sustain in Mono: the last note sounds on after its key is let go; the pedal coming up releases it")
    func sustainWithMono() {
        let engine = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(engine) }
        pedal(engine, down: true)
        noteOn(engine, 60)
        var out = render(engine, seconds: 0.05)
        noteOff(engine, 60)
        out += render(engine, frames: 128)
        noteOn(engine, 64)
        out += render(engine, frames: 128)
        noteOff(engine, 64)
        out += render(engine, frames: 128)
        var p = voiceProbe(engine)
        #expect(p.monoNote == 64 && p.keysSustained == 1 && p.keysUnreleased == 1 && p.keysHeld == 0 && p.releases == 0)
        #expect(p.freshStarts == 2 && p.continuingStarts == 0)
        let held = render(engine, seconds: 0.1)
        out += held
        let pitch = note(of: held, expected: 64)
        #expect(abs(pitch - 64) * 100 < 5, "\(pitch)")
        pedal(engine, down: false)
        out += render(engine, frames: 128)
        p = voiceProbe(engine)
        #expect(p.keysSustained == 0 && p.keysUnreleased == 0 && p.releases == 1)
        out += render(engine, seconds: 0.5)

        // The same, with 60 held until 64 comes and 64 let go when the pedal came up.
        let plain = makeEngine(["voicemode": Self.mono])
        defer { {{APP_C}}_destroy(plain) }
        noteOn(plain, 60)
        var expected = render(plain, seconds: 0.05)
        expected += render(plain, frames: 128)
        noteOn(plain, 64)
        expected += render(plain, frames: 128)
        noteOff(plain, 60)
        expected += render(plain, frames: 128)
        expected += render(plain, seconds: 0.1)
        noteOff(plain, 64)
        expected += render(plain, frames: 128)
        expected += render(plain, seconds: 0.5)
        #expect(out == expected)
    }

    @Test("Legato with the pedal down: the return to a key still held is no release; the last key up is held until the pedal comes up")
    func legatoReturnWithPedal() {
        let engine = makeEngine(["voicemode": Self.legato])
        defer { {{APP_C}}_destroy(engine) }
        pedal(engine, down: true)
        noteOn(engine, 60)
        noteOn(engine, 64)
        noteOff(engine, 64)
        var p = probe(engine)
        #expect(p.monoNote == 60 && p.freshStarts == 1 && p.continuingStarts == 2 && p.keysSustained == 0 && p.releases == 0)
        noteOff(engine, 60)
        p = probe(engine)
        #expect(p.monoNote == 60 && p.keysSustained == 1 && p.keysUnreleased == 1 && p.releases == 0)
        pedal(engine, down: false)
        p = probe(engine)
        #expect(p.keysSustained == 0 && p.keysUnreleased == 0 && p.releases == 1)
    }

    @Test("Pads ignore the pedal: a pad's note-off releases it")
    func padsIgnoreSustain() {
        func play(pedalDown: Bool) -> (out: [Float], probe: {{APP}}VoiceProbe) {
            let engine = makeEngine()
            defer { {{APP_C}}_destroy(engine) }
            {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
            if pedalDown { pedal(engine, down: true) }
            let note = Int32({{APP_UPPER}}_FIRST_PAD_NOTE)
            noteOn(engine, note)
            var out = render(engine, seconds: 0.1)
            noteOff(engine, note)
            let p = probe(engine)
            out += render(engine, seconds: 1.0)
            return (out, p)
        }
        let down = play(pedalDown: true), up = play(pedalDown: false)
        #expect(down.out == up.out)
        #expect(down.probe.releases == 1 && down.probe.keysSustained == 0)
    }

    @Test("Reset All Controllers, All Notes Off and All Sound Off put the pedal up and forget the keys held")
    func resetsClearPedalAndKeys() {
        for cc: Int32 in [120, 121, 123] {
            // The pedal: what it held is released (121) or faded out with everything (120, 123), and
            // a key let go after the reset is released at once.
            let engine = makeEngine(["voicemode": Self.poly])
            defer { {{APP_C}}_destroy(engine) }
            pedal(engine, down: true)
            noteOn(engine, 60)
            noteOff(engine, 60)
            #expect(probe(engine).keysSustained == 1, "CC \(cc)")
            controller(engine, cc, 0)
            var p = probe(engine)
            #expect(p.keysSustained == 0 && p.keysUnreleased == 0 && p.releases == (cc == 121 ? 1 : 0), "CC \(cc)")
            noteOn(engine, 62)
            noteOff(engine, 62)
            p = probe(engine)
            #expect(p.keysSustained == 0 && p.keysUnreleased == 0 && p.releases == (cc == 121 ? 2 : 1), "CC \(cc)")

            // The keys: two held in Mono, the reset, then a third let go releases the voice
            // instead of returning to one of the two.
            let mono = makeEngine(["voicemode": Self.mono])
            defer { {{APP_C}}_destroy(mono) }
            noteOn(mono, 60)
            noteOn(mono, 64)
            controller(mono, cc, 0)
            #expect(probe(mono).keysHeld == 0, "CC \(cc)")
            noteOn(mono, 67)
            p = probe(mono)
            #expect(p.monoNote == 67 && p.keysUnreleased == 1 && p.continuingStarts == 0, "CC \(cc)")
            noteOff(mono, 67)
            p = probe(mono)
            #expect(p.keysUnreleased == 0 && p.continuingStarts == 0 && p.releases == 1, "CC \(cc)")
        }
    }

    @Test("The probe tolerates a null engine and a null result")
    func probeOutOfRange() {
        var p = {{APP}}VoiceProbe()
        p.freshStarts = 7
        {{APP_C}}_voice_probe(nil, &p)
        #expect(p.freshStarts == 0 && p.monoNote == -1 && p.keysUnreleased == 0)
        let engine = makeEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_voice_probe(engine, nil)
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
