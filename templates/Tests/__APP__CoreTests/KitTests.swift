import Foundation
import Testing
@testable import {{APP}}Core

/// A kit: all sixteen pads under one name, in a file.
@Suite("Kits")
struct KitTests {

    private func library() -> KitLibrary {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "{{APP_LOWER}}-kits-\(UUID().uuidString)").appending(path: "Kits")
        return KitLibrary(folder: folder, fileExtension: KitLibrary.fileExtension, deletesForGood: true)
    }

    private func remove(_ library: KitLibrary) {
        try? FileManager.default.removeItem(at: library.folder.deletingLastPathComponent())
    }

    private func tune() throws -> Parameter { try #require(Parameters.named("tune")) }

    @Test("A kit goes through its file into another synth, pad for pad")
    func roundTrip() throws {
        let library = library()
        defer { remove(library) }
        let source = Synth(sampleRate: 48_000)
        for pad in 0..<16 {
            source.setValue(Float(-60 + pad * 8), of: try tune(), in: .pad(pad))
            source.setPadNote(40 + pad, pad: pad)
            source.setPadGroup(pad % 3 == 0 ? nil : pad, pad: pad)
        }
        source.loadProgram(TestKnobs.otherProgram, into: .pad(5))
        var kit = source.kit
        kit.name = "Mine"
        #expect(kit.pads.count == 16)
        try library.save(kit, as: "Mine")
        #expect(library.names() == ["Mine"])
        #expect(FileManager.default.fileExists(atPath: library.folder.appending(path: "Mine.{{APP_LOWER}}kit").path(percentEncoded: false)))

        let loaded = try library.load("Mine")
        #expect(loaded == kit)
        let target = Synth(sampleRate: 48_000)
        target.apply(loaded)
        #expect(target.state.pads == source.state.pads)
    }

    @Test("Applying a kit leaves the mode and the keyboard set alone")
    func keyboardUntouched() throws {
        let source = Synth(sampleRate: 48_000)
        source.setValue(55, of: try tune(), in: .pad(0))
        source.setPadNote(70, pad: 0)
        let kit = source.kit

        let target = Synth(sampleRate: 48_000)
        target.mode = .keyboard
        target.loadProgram(TestKnobs.otherProgram)
        target.setValue(45, of: try tune())
        let keyboard = target.state.keyboard
        target.apply(kit)
        #expect(target.mode == .keyboard)
        #expect(target.state.keyboard == keyboard)
        let tune = try tune()
        #expect(target.padNote(0) == 70 && abs(target.value(of: tune, in: .pad(0)) - 55) < 0.01)

        target.mode = .pads
        target.apply(kit)
        #expect(target.mode == .pads)
    }

    @Test("A kit of fewer than sixteen pads leaves the other pads alone")
    func fewerPads() throws {
        let synth = Synth(sampleRate: 48_000)
        synth.setPadNote(70, pad: 9)
        var kit = synth.kit
        kit.pads = Array(kit.pads.prefix(2))
        kit.pads[1].note = 99
        synth.apply(kit)
        #expect(synth.padNote(1) == 99 && synth.padNote(9) == 70)
    }

    @Test("A kit file with fields missing takes the defaults; unknown fields are ignored; damage is an error")
    func tolerantAndDamaged() throws {
        let library = library()
        defer { remove(library) }
        try library.makeFolder()
        func write(_ text: String, _ name: String) throws {
            try Data(text.utf8).write(to: library.folder.appending(path: "\(name).{{APP_LOWER}}kit"))
        }
        try write("{}", "Empty")
        try write(#"{"name":"Hi","pads":[{"set":{}},{"note":50,"group":2,"extra":1}],"future":true}"#, "Part")
        try write("nope", "Broken")
        try write(#"{"pads":"many"}"#, "Wrong")

        #expect(try library.load("Empty") == Kit(name: "", pads: []))
        let part = try library.load("Part")
        #expect(part.name == "Hi" && part.pads.count == 2)
        #expect(part.pads[0].note == 36 && part.pads[1].note == 50 && part.pads[1].group == 2)
        #expect(throws: PresetError.unreadable("Broken")) { try library.load("Broken") }
        #expect(throws: PresetError.unreadable("Wrong")) { try library.load("Wrong") }
    }

    // A later version may add a knob or an amount: a kit keeps its values by identifier, so that
    // each lands on its own parameter whatever its place in the table; a value this version does
    // not know is ignored, and a parameter the kit lacks takes its program's value.
    @Test("A kit from a version with another table puts every value it has on the parameter it names")
    func kitFromAnotherTable() throws {
        let source = Synth(sampleRate: 48_000)
        for parameter in Parameters.all {
            source.setValue(parameter.plain(Float((parameter.index * 37) % 100) / 100), of: parameter, in: .pad(2))
        }
        var object = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(source.kit)) as? [String: Any])
        var pads = try #require(object["pads"] as? [[String: Any]])
        var set = try #require(pads[2]["set"] as? [String: Any])
        var values = try #require(set["values"] as? [String: Any])
        values["lfo1tune"] = nil
        values["futureknob"] = 0.5
        values["velfutureknob"] = 20
        set["values"] = values
        pads[2]["set"] = set
        object["pads"] = pads
        let kit = try JSONDecoder().decode(Kit.self, from: try JSONSerialization.data(withJSONObject: object))

        let target = Synth(sampleRate: 48_000)
        target.apply(kit)
        let amount = try #require(Parameters.named("lfo1tune"))
        for parameter in Parameters.all where parameter != amount {
            let value = source.value(of: parameter, in: .pad(2))
            #expect(abs(target.value(of: parameter, in: .pad(2)) - value) <= 1e-4 * max(1, abs(value)), "\(parameter.identifier)")
        }
        let program = target.program(in: .pad(2))
        #expect(target.value(of: amount, in: .pad(2)) == Programs.value(program: program, parameter: amount))
    }

    @Test("A pad is named by its preset, else its program, else Custom")
    func padNames() {
        #expect(PadLabel.name(program: 0, preset: "Mine") == "Mine")
        #expect(PadLabel.name(program: 0, preset: nil) == Programs.names[0])
        #expect(PadLabel.name(program: 0, preset: "") == Programs.names[0])
        #expect(PadLabel.name(program: -1, preset: nil) == "Custom")
        #expect(PadLabel.name(program: 999, preset: nil) == "Custom")
        #expect(PadLabel.name(program: -1, preset: "Mine") == "Mine")
    }
}
