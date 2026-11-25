import Testing
import {{APP}}DSP
@testable import {{APP}}Core

/// The table's invariants for every instrument: the platform block first and as it is, then the
/// instrument's knobs, then the amounts, each named after its knob. The instrument's own knobs,
/// programs and kit are checked in `InstrumentTableTests`.
@Suite("Parameter table")
struct ParameterTableTests {

    private static let knobs = TestKnobs.all
    private static var lfoTargets: [Parameter] { knobs.filter { LFOs.amount(of: $0, lfo: 0) != nil } }
    private static var velTargets: [Parameter] { knobs.filter { Velocity.amount(of: $0) != nil } }

    @Test("The platform's knobs come first, in the permanent order, then the instrument's, then the amounts")
    func order() {
        #expect(Parameters.all.prefix(TestKnobs.platform.count).map(\.identifier) == TestKnobs.platform)
        #expect(!TestKnobs.instrument.isEmpty)
        #expect(Parameters.all.prefix(Self.knobs.count).map(\.index) == Self.knobs.map(\.index))   // the knobs, then nothing but amounts
        let lfo = Self.lfoTargets, vel = Self.velTargets
        #expect(Parameters.all.count == Self.knobs.count + 2 * lfo.count + vel.count)
        let amounts = Parameters.all.dropFirst(Self.knobs.count).map(\.identifier)
        // LFO 1's amounts, LFO 2's on the same knobs in the same order, then the velocity's.
        let lfo1 = Array(amounts.prefix(lfo.count)), lfo2 = Array(amounts.dropFirst(lfo.count).prefix(lfo.count))
        #expect(Set(lfo1) == Set(lfo.map { "lfo1\($0.identifier)" }))
        #expect(lfo2 == lfo1.map { "lfo2" + $0.dropFirst(4) })
        #expect(Set(amounts.suffix(vel.count)) == Set(vel.map { "vel\($0.identifier)" }))
    }

    @Test("Identifiers are lowercase ASCII and unique, the knobs' and the amounts' together")
    func identifiers() {
        let ids = Parameters.all.map(\.identifier)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(!id.isEmpty && id.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }, "\(id)")
        }
    }

    @Test("The platform block's ranges, defaults and choices")
    func platformBlock() {
        func knob(_ id: String) -> Parameter { TestKnobs.named(id) }
        // The platform's own default, or the instrument's where it sets one (`kPlatformDefaults`).
        func hasDefault(_ id: String, _ platform: Float) -> Bool {
            TestKnobs.platformOwn[id] == platform && knob(id).defaultValue == TestKnobs.platformDefault(id)
        }
        #expect(Set(TestKnobs.platformOwn.keys) == Set(TestKnobs.platform))
        #expect(knob("volume").range == -40...6 && hasDefault("volume", 0) && knob("volume").unit == "dB")
        #expect(knob("pan").range == -100...100 && hasDefault("pan", 0) && knob("pan").unit == "%")
        #expect(knob("tune").range == -100...100 && hasDefault("tune", 0) && knob("tune").unit == "ct")
        #expect(knob("octave").range == -2...2 && knob("octave").kind == .integer && hasDefault("octave", 0))
        #expect(knob("bendup").range == 0...24 && knob("benddown").range == 0...24 && knob("bendup").kind == .integer)
        #expect(hasDefault("bendup", 2) && hasDefault("benddown", 2))
        #expect(knob("voicemode").kind == .choice(["Poly", "Mono", "Legato"]) && hasDefault("voicemode", 0))
        #expect(knob("glide").range == 0...2000 && hasDefault("glide", 0) && knob("glide").unit == "ms")
        #expect(knob("lfostart").kind == .choice(["Hit", "Free"]) && hasDefault("lfostart", 0))
        #expect(knob("lfo1rate").range == 0.02...20 && hasDefault("lfo1rate", 6))
        #expect(knob("lfo1shape").kind == knob("lfo2shape").kind && hasDefault("lfo1shape", 0))
        #expect(knob("lfo2rate").range == 0.02...20 && hasDefault("lfo2rate", 2))
        #expect(knob("lfo2shape").kind == .choice(["Sine", "Triangle", "Ramp Up", "Ramp Down", "Square", "Steps", "Wander"]))
        #expect(hasDefault("lfo2shape", 0))
        #expect(knob("velsens").range == 0...100 && hasDefault("velsens", 70))
        for id in ["glide", "lfo1rate", "lfo2rate"] {
            var info = {{APP}}ParamInfo()
            {{APP_C}}_param_info(Int32(knob(id).index), &info)
            #expect(info.logarithmic == 1, "\(id)")
        }
        // A logarithmic knob's middle is the geometric mean; Glide, whose bottom is none, travels
        // as log(1 + x / 2 ms) and is 0 at its bottom.
        let rate = knob("lfo1rate")
        #expect(abs(rate.plain(0.5) - (0.02 * 20 as Float).squareRoot()) < 1e-5)
        let glide = knob("glide")
        #expect(glide.plain(0) == 0 && abs(glide.plain(1) - 2000) < 0.01)
        #expect(abs(glide.plain(0.5) - 2 * ((1001 as Float).squareRoot() - 1)) < 0.01)
        #expect(abs(glide.plain(glide.normalised(100)) - 100) < 0.01)
    }

    @Test("The instrument's defaults of platform knobs name knobs of the platform block, once each, in range; the table reports them")
    func instrumentPlatformDefaults() {
        let count = Int({{APP_C}}_num_platform_defaults())
        var seen: Set<Int32> = []
        for i in 0..<Int32(count) {
            let index = {{APP_C}}_platform_default_param(i), value = {{APP_C}}_platform_default_value(i)
            #expect(index >= 0 && Int(index) < TestKnobs.platform.count, "entry \(i): knob \(index)")
            #expect(seen.insert(index).inserted, "entry \(i): knob \(index) twice")
            guard index >= 0 && Int(index) < TestKnobs.platform.count else { continue }
            let knob = Parameters.all[Int(index)]
            #expect(knob.range.contains(value), "\(knob.identifier): \(value)")
            if knob.kind != .continuous { #expect(value == value.rounded(), "\(knob.identifier): \(value)") }
            var info = {{APP}}ParamInfo()
            {{APP_C}}_param_info(index, &info)
            #expect(info.defaultValue == value && knob.defaultValue == value, "\(knob.identifier)")
        }
        #expect(TestKnobs.platformDefaults.count == count)
        #expect({{APP_C}}_platform_default_param(Int32(count)) == -1 && {{APP_C}}_platform_default_param(-1) == -1)
        #expect({{APP_C}}_platform_default_value(Int32(count)) == 0)
    }

    @Test("Every amount is -100 ... 100 % and 0 at rest")
    func amountsAtRest() {
        for amount in Parameters.all.dropFirst(Self.knobs.count) {
            #expect(amount.range == -100...100 && amount.defaultValue == 0 && amount.unit == "%", "\(amount.identifier)")
        }
    }

    @Test("Sections hold every knob once: the instrument's sections, then Master with the platform block")
    func sections() {
        let sections = ParameterSection.all
        #expect(sections.last?.title == "Master")
        #expect(sections.last?.parameters.map(\.identifier) == TestKnobs.platform)
        let all = sections.flatMap(\.parameters).map(\.index)
        #expect(all.sorted() == Self.knobs.map(\.index))
        var info = {{APP}}ParamInfo()
        {{APP_C}}_param_info(Int32(Self.knobs.count), &info)
        #expect(info.section == -1)
    }

    @Test("LFO and VEL amounts point at their targets")
    func amounts() {
        // The LFOs move Volume, Pan and Tune; the velocity moves Volume, Pan, Tune and the LFOs'
        // rates, and no switch, Octave, bend range, Glide or Vel Sens.
        let lfo = Set(Self.lfoTargets.map(\.identifier)), vel = Set(Self.velTargets.map(\.identifier))
        #expect(lfo.isSuperset(of: ["volume", "pan", "tune"]))
        #expect(vel.isSuperset(of: ["volume", "pan", "tune", "lfo1rate", "lfo2rate"]))
        #expect(vel.isDisjoint(with: ["octave", "bendup", "benddown", "voicemode", "glide", "lfostart", "lfo1shape", "lfo2shape", "velsens"]))
        for knob in Self.knobs {
            #expect(LFOs.amount(of: knob, lfo: 1)?.identifier == (lfo.contains(knob.identifier) ? "lfo2\(knob.identifier)" : nil))
            #expect(Velocity.amount(of: knob)?.identifier == (vel.contains(knob.identifier) ? "vel\(knob.identifier)" : nil))
            if knob.isChoice { #expect(!lfo.contains(knob.identifier) && !vel.contains(knob.identifier), "\(knob.identifier)") }
        }
        // VEL moves every continuous knob of the instrument.
        for knob in TestKnobs.instrument where knob.kind == .continuous {
            #expect(vel.contains(knob.identifier), "\(knob.identifier)")
        }
        #expect(TestKnobs.named("velvolume").name == "VEL>Volume" && TestKnobs.named("lfo2tune").name == "LFO 2>Tune")
        #expect(LFOs.count == 2)
        #expect(LFOs.label(amount: -30) == "−30 %" && LFOs.snapped(amount: 0.5) == 0)
    }

    @Test("The arcs a knob shows: an LFO sweeps both ways, a softer hit moves one way")
    func arcs() {
        #expect(LFOs.arc(position: 0.5, amount: 25) == 0.25...0.75)
        #expect(LFOs.arc(position: 0.875, amount: -25) == 0.625...1)
        // The knob is where the hardest hit stands; a positive amount means a softer hit is lower.
        #expect(Velocity.arc(position: 0.5, amount: 25) == 0.25...0.5)
        #expect(Velocity.arc(position: 0.5, amount: -25) == 0.5...0.75)
        #expect(Velocity.arc(position: 0.125, amount: 50) == 0...0.125)
        #expect(Velocity.arc(position: 0.875, amount: -50) == 0.875...1)
        #expect(Velocity.arc(position: 0.375, amount: 0) == 0.375...0.375)
    }

    @Test("Programs set every parameter but Octave; there are at least two")
    func programs() {
        #expect(Programs.names.count >= 2)
        #expect(Set(Programs.names).count == Programs.names.count)
        #expect({{APP_C}}_program_sets(Int32(TestKnobs.named("octave").index)) == 0)
        for parameter in Parameters.all where parameter.identifier != "octave" {
            #expect({{APP_C}}_program_sets(Int32(parameter.index)) == 1, "\(parameter.identifier)")
        }
        let octave = TestKnobs.named("octave")
        for program in Programs.names.indices {
            #expect(Programs.value(program: program, parameter: octave) == octave.defaultValue)
        }
    }

    // A fresh keyboard set holds the defaults and names the first program (the Audio Unit shows
    // it as its preset): the first program is the defaults, the instrument's playing style included.
    @Test("The first program is the table's defaults")
    func firstProgramIsTheDefaults() {
        for parameter in Parameters.all {
            #expect(Programs.value(program: 0, parameter: parameter) == parameter.defaultValue, "\(parameter.identifier)")
        }
    }

    @Test("Values round-trip and display")
    func display() {
        func knob(_ id: String) -> Parameter { TestKnobs.named(id) }
        #expect(knob("volume").label(-12) == "-12.0 dB" && knob("volume").label(-0.01) == "0.0 dB")
        #expect(knob("pan").label(50) == "50 %")
        #expect(knob("tune").label(10) == "10 ct")
        #expect(knob("octave").label(1) == "+1" && knob("octave").label(-1) == "-1" && knob("octave").label(0) == "0")
        #expect(knob("bendup").label(12) == "12 st")
        #expect(knob("voicemode").label(2) == "Legato")
        #expect(knob("glide").label(100) == "100 ms")
        #expect(knob("lfostart").label(1) == "Free")
        #expect(knob("lfo1rate").label(6) == "6.00 Hz" && knob("lfo1rate").label(12) == "12 Hz")
        #expect(knob("lfo1shape").label(4) == "Square")
        for knob in Self.knobs where knob.kind == .continuous {
            let plain = knob.plain(0.3)
            #expect(abs(knob.plain(knob.normalised(plain)) - plain) <= 1e-4 * max(1, abs(plain)), "\(knob.identifier)")
        }
    }
}
