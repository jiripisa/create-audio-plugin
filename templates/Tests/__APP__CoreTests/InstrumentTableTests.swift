import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// The instrument's part of the table, as its spec gives it: its knobs and their order, ranges,
/// defaults and controllers, what the LFOs, the velocity and the wheels move, its sections,
/// programs and default kit.
@Suite("Instrument table")
struct InstrumentTableTests: EngineHarness {

    @Test("Tone's knobs follow the platform block")
    func knobs() {
        #expect(TestKnobs.instrument.map(\.identifier) == ["attack", "decay", "release", "brightness"])
        #expect(TestKnobs.instrument.map(\.name) == ["Attack", "Decay", "Release", "Brightness"])
        #expect(Parameters.all.count == 14 + 4 + 2 * 4 + 9)
    }

    @Test("Ranges, defaults and units")
    func ranges() {
        func knob(_ id: String) -> Parameter { TestKnobs.named(id) }
        #expect(knob("attack").range == 1...2000 && knob("attack").defaultValue == 5 && knob("attack").unit == "ms")
        #expect(knob("decay").range == 0.05...20 && knob("decay").defaultValue == 2 && knob("decay").unit == "s")
        #expect(knob("release").range == 0.01...5 && knob("release").defaultValue == 0.3 && knob("release").unit == "s")
        #expect(knob("brightness").range == 0...100 && knob("brightness").defaultValue == 30 && knob("brightness").unit == "%")
        for id in ["attack", "decay", "release"] {
            var info = {{APP}}ParamInfo()
            {{APP_C}}_param_info(Int32(knob(id).index), &info)
            #expect(info.logarithmic == 1, "\(id)")
        }
        #expect(knob("attack").label(5) == "5 ms" && knob("release").label(0.3) == "0.30 s" && knob("brightness").label(30) == "30 %")
    }

    @Test("Where MIDI names a controller for the thing, the knob has it")
    func controllers() {
        let expected = ["attack": 73, "decay": 75, "release": 72, "brightness": 74]
        for (id, controller) in expected {
            #expect(Controllers.standard(for: TestKnobs.named(id)) == controller, "\(id)")
        }
    }

    @Test("What the LFOs and the velocity move")
    func targets() {
        let lfo = TestKnobs.all.filter { LFOs.amount(of: $0, lfo: 0) != nil }.map(\.identifier)
        let vel = Parameters.all.filter { $0.identifier.hasPrefix("vel") && $0.index >= TestKnobs.all.count }.map(\.identifier)
        #expect(Set(lfo) == ["volume", "pan", "tune", "brightness"])
        #expect(vel == ["velattack", "veldecay", "velrelease", "velbrightness", "velvolume", "velpan", "veltune",
                        "vellfo1rate", "vellfo2rate"])
    }

    // The mod wheel at the top moves Brightness half its travel up, full aftertouch a quarter.
    @Test("The mod wheel and the aftertouch move Brightness")
    func wheels() {
        func play(_ knobs: [String: Float], wheel: Int32? = nil, pressure: Int32? = nil) -> [Float] {
            let engine = makeDefaultEngine(knobs)
            defer { {{APP_C}}_destroy(engine) }
            if let wheel { {{APP_C}}_midi(engine, 0xB0, 1, wheel, 0) }
            if let pressure { {{APP_C}}_midi(engine, 0xD0, pressure, 0, 0) }
            {{APP_C}}_midi(engine, 0x90, 60, 110, 0)
            return render(engine, seconds: 0.5)
        }
        let wheel = play(["brightness": 10], wheel: 127)
        #expect(residualDb(wheel, play(["brightness": 60])) < -100)
        let pressed = play(["brightness": 10], pressure: 127)
        #expect(residualDb(pressed, play(["brightness": 35])) < -100)
        #expect(pressed != play(["brightness": 10]))
    }

    @Test("Sections: Tone, then Master")
    func sections() {
        #expect(ParameterSection.all.map(\.title) == ["Tone", "Master"])
        #expect(ParameterSection.all[0].parameters.map(\.identifier) == ["attack", "decay", "release", "brightness"])
    }

    @Test("Programs: Tone is the defaults, Soft Tone slower and darker")
    func programs() {
        #expect(Programs.names == ["Tone", "Soft Tone"])
        for program in Programs.names.indices {
            let values = PrototypeScores.programs[program]!
            for parameter in Parameters.all {
                #expect(Programs.value(program: program, parameter: parameter) == values[parameter.identifier] ?? parameter.defaultValue,
                        "\(Programs.names[program]): \(parameter.identifier)")
            }
        }
    }

    @Test("The default kit: Tone on every pad, at notes 36 ... 51, groups off")
    func defaultKit() {
        let engine = {{APP_C}}_create()!
        defer { {{APP_C}}_destroy(engine) }
        for pad: Int32 in 0..<16 {
            #expect({{APP_C}}_pad_note(engine, pad) == 36 + pad && {{APP_C}}_pad_group(engine, pad) == 0, "pad \(pad + 1)")
            #expect({{APP_C}}_get_program(engine, pad + 1) == 0, "pad \(pad + 1)")
        }
    }

    // The longest release: Release at its top, the note let go at full level. The voice is over
    // within the tail, and not much sooner: the tail is no guess.
    @Test("A note let go sounds no longer than the tail, and nearly as long")
    func tail() throws {
        let release = TestKnobs.named("release")
        #expect(abs({{APP_C}}_tail_time() - Double(release.range.upperBound) * 100 / 60) < 1e-6)
        let rate = 48_000.0
        let engine = makeDefaultEngine(["release": release.range.upperBound, "decay": TestKnobs.named("decay").range.upperBound,
                                        "velsens": 0], rate: rate)
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 60, 127, 0)
        _ = render(engine, seconds: 0.1, at: rate)
        {{APP_C}}_midi(engine, 0x80, 60, 0, 0)
        var frames = 0
        while {{APP_C}}_sounding_voices(engine) > 0 || frames == 0 {
            _ = render(engine, frames: 128)
            frames += 128
            try #require(Double(frames) / rate < 2 * {{APP_C}}_tail_time(), "the voice does not end")
        }
        let lasted = Double(frames) / rate
        #expect(lasted <= {{APP_C}}_tail_time() && lasted > 0.95 * {{APP_C}}_tail_time(), "\(lasted) s, tail \({{APP_C}}_tail_time()) s")
    }

    @Test("Tone's parameter IDs")
    func parameterIDs() {
        let ids: [String: UInt32] = ["attack": 14, "decay": 15, "release": 16, "brightness": 17, "lfo1brightness": 1_017,
                                     "lfo2brightness": 2_017, "velattack": 3_014, "velbrightness": 3_017]
        for (id, unitID) in ids { #expect(TestKnobs.named(id).unitID == unitID, "\(id)") }
    }

    // The calibration (`kOutputLevel`): the fullest gesture of the playing style at full velocity,
    // with Volume at its default, peaks under the knee of the output stage (0.6: the limiter bends
    // what is above it), and not far under, so that no level is given away. Tone is played in
    // chords: four keys at once.
    @Test("The fullest gesture, a four-note chord at full velocity, peaks just under the limiter's knee")
    func fullestGesture() {
        var loudest: Float = 0
        for chord: [Int32] in [[48, 55, 60, 64], [60, 64, 67, 72], [57, 60, 64, 69], [72, 76, 79, 84]] {
            let engine = makeDefaultEngine()
            defer { {{APP_C}}_destroy(engine) }
            for note in chord { {{APP_C}}_midi(engine, 0x90, note, 127, 0) }
            let peak = render(engine, seconds: 2).map(abs).max() ?? 0
            #expect(peak < 0.6, "chord \(chord): peak \(peak)")
            loudest = max(loudest, peak)
        }
        #expect(loudest > 0.4, "the loudest chord peaks at \(loudest): the level is lower than it needs to be")
    }

    @Test("One default note at full velocity peaks around -17 dBFS")
    func level() {
        let engine = makeDefaultEngine()
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_midi(engine, 0x90, 60, 127, 0)
        let peak = render(engine, seconds: 1).map(abs).max() ?? 0
        #expect(peak > 0.13 && peak < 0.155, "peak \(peak)")
    }
}
