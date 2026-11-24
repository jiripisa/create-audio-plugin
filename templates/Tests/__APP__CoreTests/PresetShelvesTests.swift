import Foundation
import Testing
@testable import {{APP}}Core

/// What a window keeps of the player's files for all seventeen sets (`PresetShelves`), and the
/// small pieces of the synth's state both models build on.
@Suite("Presets of every set")
struct PresetShelvesTests {

    /// A preset and a kit library side by side in a folder of their own that is not there yet.
    /// Deleting removes for good: the tests have no business in anybody's Trash (or in
    /// ~/Library/Application Support/{{APP}}).
    static func libraries(in root: URL? = nil) -> (presets: PresetLibrary, kits: KitLibrary) {
        let root = root ?? FileManager.default.temporaryDirectory.appending(path: "{{APP_LOWER}}-shelves-\(UUID().uuidString)")
        return (PresetLibrary(folder: root.appending(path: "Presets"), fileExtension: PresetLibrary.fileExtension,
                              deletesForGood: true),
                KitLibrary(folder: root.appending(path: "Kits"), fileExtension: KitLibrary.fileExtension,
                           deletesForGood: true))
    }

    private func remove(_ libraries: (presets: PresetLibrary, kits: KitLibrary)) {
        try? FileManager.default.removeItem(at: libraries.presets.folder.deletingLastPathComponent())
    }

    private func shelves(_ libraries: (presets: PresetLibrary, kits: KitLibrary), inUse names: [String?] = []) -> PresetShelves {
        PresetShelves(presets: libraries.presets, kits: libraries.kits, inUse: names)
    }

    private func tune() throws -> Parameter { try #require(Parameters.named("tune")) }

    /// The last program with Tune at 37 cents.
    private func sound(tune plain: Float = 37) throws -> SetState {
        let synth = Synth(sampleRate: 48_000)
        synth.loadProgram(TestKnobs.otherProgram)
        synth.setValue(plain, of: try tune())
        return synth.state(of: .keyboard)
    }

    @Test("Each of the seventeen sets keeps the preset it came from, the keyboard's first")
    func eachSetKeepsItsPreset() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var shelves = shelves(libraries)
        #expect(shelves.presets.isEmpty)
        #expect(shelves.namesInUse == [String?](repeating: nil, count: 17))

        try shelves.save(try sound(), as: " Mine ", from: .keyboard)
        let loaded = try shelves.load("mine", into: .pad(3))
        #expect(loaded.preset == "Mine" && loaded.values["tune"] == 37)
        #expect(shelves.presets == ["Mine"])
        #expect(shelves.inUse(in: .keyboard) == "Mine")
        #expect(shelves.inUse(in: .pad(3)) == "Mine")
        #expect(shelves.inUse(in: .pad(4)) == nil)
        #expect(shelves.inUse(in: .pad(16)) == nil)                     // no such pad
        #expect(shelves.namesInUse == ["Mine", nil, nil, nil, "Mine"] + [String?](repeating: nil, count: 12))

        shelves.leave(.keyboard)                                         // a program was loaded
        #expect(shelves.inUse(in: .keyboard) == nil)
        #expect(shelves.inUse(in: .pad(3)) == "Mine")

        var attempt = shelves
        let set = try sound()
        #expect(throws: PresetError.missing("Nope")) { _ = try attempt.load("Nope", into: .pad(1)) }
        #expect(throws: PresetError.noName) { try attempt.save(set, as: "  ", from: .pad(1)) }
        #expect(shelves.inUse(in: .pad(1)) == nil)
    }

    @Test("A double click goes to the preset's value while one is in use, then to the program's, then to the default")
    func resetValue() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var shelves = shelves(libraries)
        let tune = try tune()
        let programmed = TestKnobs.programKnob
        var older = try sound()
        older.values[TestKnobs.programKnob.identifier] = nil                                       // a file from before that knob
        try libraries.presets.save(older, as: "Older")

        _ = try shelves.load("Older", into: .pad(0))
        #expect(shelves.resetValue(of: tune, in: .pad(0), program: TestKnobs.otherProgram) == 37)
        #expect(shelves.resetValue(of: programmed, in: .pad(0), program: TestKnobs.otherProgram) == Programs.value(program: TestKnobs.otherProgram, parameter: programmed))
        #expect(shelves.resetValue(of: tune, in: .keyboard, program: TestKnobs.otherProgram) == Programs.value(program: TestKnobs.otherProgram, parameter: tune))
        #expect(shelves.resetValue(of: tune, in: .keyboard, program: -1) == tune.defaultValue)
        shelves.leave(.pad(0))
        #expect(shelves.resetValue(of: tune, in: .pad(0), program: TestKnobs.otherProgram) == Programs.value(program: TestKnobs.otherProgram, parameter: tune))
    }

    @Test("Deleting a preset leaves every set that used it with none; a set using another keeps it")
    func deleting() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var shelves = shelves(libraries)
        try shelves.save(try sound(), as: "Mine", from: .keyboard)
        try shelves.save(try sound(tune: -30), as: "Other", from: .pad(5))
        _ = try shelves.load("Mine", into: .pad(2))

        try shelves.delete("mine")
        #expect(shelves.presets == ["Other"])
        #expect(shelves.inUse(in: .keyboard) == nil && shelves.inUse(in: .pad(2)) == nil)
        #expect(shelves.inUse(in: .pad(5)) == "Other")
        var attempt = shelves
        #expect(throws: PresetError.missing("Mine")) { try attempt.delete("Mine") }
    }

    @Test("What another window saves or deletes shows after a look at the folder, which tells whether anything changed")
    func anotherWindow() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var mine = shelves(libraries), theirs = shelves(libraries)
        try theirs.save(try sound(), as: "Shared", from: .keyboard)
        try theirs.saveKit(Kit(name: "", pads: []), as: "Their kit")
        #expect(mine.presets.isEmpty && mine.kits.isEmpty)
        let sawThem = mine.look()
        #expect(sawThem)
        #expect(mine.presets == ["Shared"] && mine.kits == ["Their kit"])
        let sawNothing = mine.look()
        #expect(!sawNothing)

        _ = try mine.load("Shared", into: .pad(7))
        try theirs.delete("Shared")
        let sawDelete = mine.look()
        #expect(sawDelete)
        #expect(mine.inUse(in: .pad(7)) == nil)
    }

    @Test("Saving over a preset another set uses gives that set the new values to go back to")
    func savingOverAPresetInUse() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var shelves = shelves(libraries)
        let tune = try tune()
        try shelves.save(try sound(), as: "Mine", from: .keyboard)
        _ = try shelves.load("Mine", into: .pad(1))
        try shelves.save(try sound(tune: 75), as: "MINE", from: .pad(9))
        #expect(shelves.presets == ["MINE"])
        #expect(shelves.inUse(in: .pad(1)) == "MINE")
        #expect(shelves.resetValue(of: tune, in: .pad(1), program: TestKnobs.otherProgram) == 75)
        #expect(shelves.resetValue(of: tune, in: .keyboard, program: TestKnobs.otherProgram) == 75)
    }

    @Test("A set told its preset (by a saved state or a host) has it while the folder does")
    func following() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        try libraries.presets.save(try sound(), as: "Mine")
        var shelves = shelves(libraries, inUse: ["Mine", nil, "Gone", "mine"])
        #expect(shelves.namesInUse.prefix(4) == ["Mine", nil, nil, "Mine"])
        shelves.follow("Gone", in: .pad(0))
        #expect(shelves.inUse(in: .pad(0)) == nil)
        shelves.follow("Mine", in: .pad(0))
        #expect(shelves.inUse(in: .pad(0)) == "Mine")
        shelves.follow(nil, in: .keyboard)
        #expect(shelves.inUse(in: .keyboard) == nil)
    }

    @Test("A kit saves the pads with their presets in use and gives them back; the default kit leaves the pads with none")
    func kits() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var shelves = shelves(libraries)
        let synth = Synth(sampleRate: 48_000)
        try shelves.save(try sound(), as: "Mine", from: .keyboard)
        _ = try shelves.load("Mine", into: .pad(1))

        try shelves.saveKit(synth.kit, as: " Kit A ")
        #expect(shelves.kits == ["Kit A"])
        let file = try libraries.kits.load("Kit A")
        #expect(file.name == "Kit A")
        #expect(file.pads[1].set.preset == "Mine")
        #expect(file.pads[0].set.preset == nil)

        var other = self.shelves(libraries, inUse: [nil, nil, nil, "Mine"])
        let kit = try other.loadKit("kit a")
        #expect(kit.pads.count == 16)
        #expect(other.inUse(in: .pad(1)) == "Mine")
        #expect(other.inUse(in: .pad(2)) == nil)                         // the kit's pad 3 has none
        other.leavePads()
        #expect(other.namesInUse == [String?](repeating: nil, count: 17))

        // On a Mac without the preset, the kit loads and its pad has none.
        let elsewhere = Self.libraries()
        defer { remove(elsewhere) }
        try elsewhere.kits.save(file, as: "Kit A")
        var there = self.shelves(elsewhere)
        _ = try there.loadKit("Kit A")
        #expect(there.inUse(in: .pad(1)) == nil)

        try shelves.deleteKit("KIT A")
        #expect(shelves.kits.isEmpty)
        var attempt = shelves
        let kitNow = synth.kit
        #expect(throws: PresetError.missing("Kit A")) { _ = try attempt.loadKit("Kit A") }
        #expect(throws: PresetError.noName) { try attempt.saveKit(kitNow, as: "") }
    }

    @Test("A kit with fewer pads leaves the presets of the others alone")
    func shortKit() throws {
        let libraries = Self.libraries()
        defer { remove(libraries) }
        var shelves = shelves(libraries)
        try shelves.save(try sound(), as: "Mine", from: .pad(10))
        try libraries.kits.save(Kit(name: "Two", pads: Array(Synth(sampleRate: 48_000).kit.pads.prefix(2))), as: "Two")
        _ = try shelves.load("Mine", into: .pad(0))
        _ = try shelves.loadKit("Two")
        #expect(shelves.inUse(in: .pad(0)) == nil)
        #expect(shelves.inUse(in: .pad(10)) == "Mine")
    }

    // MARK: The synth's state

    @Test("A saved state carries the preset of every set, the keyboard's first")
    func stateNames() throws {
        let synth = Synth(sampleRate: 48_000)
        var state = synth.state
        #expect(state.presetNames == [String?](repeating: nil, count: 17))
        state.presetNames = ["K", nil, "P1"]
        #expect(state.keyboard.preset == "K")
        #expect(state.pads[1].set.preset == "P1")
        #expect(state.presetNames == ["K", nil, "P1"] + [String?](repeating: nil, count: 14))

        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SynthState.self, from: data).presetNames == state.presetNames)

        var short = SynthState(mode: .keyboard, keyboard: SetState(program: 0, values: [:]), pads: [])
        short.presetNames = ["K", "ignored"]
        #expect(short.presetNames == ["K"])
    }

    @Test("A set's state is what the whole state holds for it")
    func setState() {
        let synth = Synth(sampleRate: 48_000)
        synth.loadProgram(TestKnobs.otherProgram, into: .pad(6))
        #expect(synth.state(of: .pad(6)) == synth.state.pads[6].set)
        #expect(synth.state(of: .keyboard) == synth.state.keyboard)
    }

    @Test("A set records the program it came from without a knob moving")
    func recordProgram() throws {
        let synth = Synth(sampleRate: 48_000)
        let programmed = TestKnobs.programKnob
        synth.setValue(programmed.plain(0.7), of: programmed, in: .pad(2))
        synth.recordProgram(TestKnobs.otherProgram, in: .pad(2))
        #expect(synth.program(in: .pad(2)) == TestKnobs.otherProgram)
        #expect(abs(synth.value(of: programmed, in: .pad(2)) - programmed.plain(0.7)) <= 1e-4 * programmed.plain(0.7))
        synth.recordProgram(999, in: .pad(2))
        synth.recordProgram(-1, in: .pad(2))
        #expect(synth.program(in: .pad(2)) == TestKnobs.otherProgram)
    }

    @Test("A saved set's values in full: its own, the program's for the knobs it lacks, kept within each knob")
    func resolvedValues() throws {
        let tune = try tune()
        let octave = try #require(Parameters.named("octave"))
        let lfoStart = try #require(Parameters.named("lfostart"))
        let programmed = TestKnobs.programKnob
        var saved = try sound()
        saved.values[TestKnobs.programKnob.identifier] = nil
        saved.values["lfostart"] = 1.4
        saved.values["octave"] = 7
        saved.values["unknown"] = 3

        let resolved = saved.resolved(currentProgram: 0)
        #expect(resolved.program == TestKnobs.otherProgram)
        #expect(resolved.values.count == Parameters.all.count)
        #expect(resolved.values[tune.index] == 37)
        #expect(resolved.values[programmed.index] == Programs.value(program: TestKnobs.otherProgram, parameter: programmed))
        #expect(resolved.values[lfoStart.index] == 1)
        #expect(resolved.values[octave.index] == 2)

        // What the synth does with the same set.
        let synth = Synth(sampleRate: 48_000)
        synth.apply(saved, to: .keyboard)
        for parameter in Parameters.all {
            #expect(abs(synth.value(of: parameter) - resolved.values[parameter.index]) < 1e-3, "\(parameter.identifier)")
        }

        // A program number that is no program leaves the set's own.
        saved.program = 3_000
        #expect(saved.resolved(currentProgram: TestKnobs.otherProgram).program == TestKnobs.otherProgram)
        #expect(saved.resolved(currentProgram: TestKnobs.otherProgram).values[programmed.index] == Programs.value(program: TestKnobs.otherProgram, parameter: programmed))
    }
}
