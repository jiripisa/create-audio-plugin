import Foundation
import Testing
@testable import {{APP}}Core

/// MIDI controllers on the keyboard set's knobs: each knob comes with one, a control change moves
/// the knob, and a knob can be taught another.
@Suite("Controllers")
struct ControllerTests {

    private func knob(_ identifier: String) throws -> Parameter { try #require(Parameters.named(identifier)) }

    /// The knobs, in table order.
    private static let knobs = ParameterSection.all.flatMap(\.parameters).sorted { $0.index < $1.index }

    /// The first instrument knob and its controller; controllers no knob comes with.
    private static let first = TestKnobs.first
    private static let firstCC = Controllers.standard(for: TestKnobs.first)!
    private static let free = TestKnobs.freeControllers

    /// Lets the engine take in what was posted: MIDI is read at the start of a block.
    private func run(_ synth: Synth) {
        var block = [Float](repeating: 0, count: 64)
        block.withUnsafeMutableBufferPointer { synth.render(left: $0.baseAddress!, right: nil, frames: 64) }
    }

    private func send(_ synth: Synth, controller: Int, value: Int, channel: UInt8 = 0) {
        synth.postMIDI(status: 0xB0 | channel, data1: UInt8(controller), data2: UInt8(value))
        run(synth)
    }

    // MARK: What the knobs come with

    @Test("Every knob comes with a controller of its own, and none that MIDI reserves")
    func standardControllers() {
        #expect(Self.knobs.map(\.index) == TestKnobs.all.map(\.index))
        let controllers = Self.knobs.compactMap { Controllers.standard(for: $0) }
        #expect(controllers.count == Self.knobs.count)
        #expect(Set(controllers).count == controllers.count)
        #expect(controllers.allSatisfy { (0...127).contains($0) && !Controllers.isReserved($0) })
    }

    @Test("The platform block comes with its controllers: Volume 7, Pan 10, Glide 5 (Portamento Time), the others 102-112")
    func platformControllers() throws {
        let expected = ["volume": 7, "pan": 10, "tune": 102, "octave": 103, "bendup": 104, "benddown": 105, "voicemode": 106,
                        "glide": 5, "lfostart": 107, "lfo1rate": 108, "lfo1shape": 109, "lfo2rate": 110, "lfo2shape": 111,
                        "velsens": 112]
        #expect(expected.count == TestKnobs.platform.count)
        for (identifier, controller) in expected {
            #expect(Controllers.standard(for: try knob(identifier)) == controller, "\(identifier)")
            #expect(Synth().controller(of: try knob(identifier)) == controller, "\(identifier) on a new synth")
        }
    }

    @Test("MIDI's own controllers and the mod wheel are reserved; an amount has no controller")
    func reserved() {
        let reserved = [0, 1, 6, 32, 38, 64] + Array(96...101) + Array(120...127)
        for controller in 0...127 {
            #expect(Controllers.isReserved(controller) == reserved.contains(controller), "CC \(controller)")
        }
        #expect(Controllers.isReserved(-1) && Controllers.isReserved(128))
        let synth = Synth()
        for amount in Parameters.all where amount.index >= Self.knobs.count {
            #expect(Controllers.standard(for: amount) == nil, "\(amount.identifier)")
            #expect(synth.controller(of: amount) == nil, "\(amount.identifier) on a new synth")
        }
    }

    // MARK: Moving a knob

    @Test("A controller puts its knob where its value says, on any channel")
    func controllerMovesItsKnob() throws {
        let synth = Synth()
        let first = Self.first, volume = try knob("volume")
        let volumeBefore = synth.value(of: volume)
        send(synth, controller: Self.firstCC, value: 127)
        #expect(synth.normalisedValue(of: first) == 1)
        send(synth, controller: Self.firstCC, value: 0, channel: 9)
        #expect(synth.normalisedValue(of: first) == 0)
        send(synth, controller: Self.firstCC, value: 100, channel: 15)
        #expect(abs(synth.normalisedValue(of: first) - 100.0 / 127) < 1e-6)
        #expect(synth.value(of: volume) == volumeBefore)                             // nobody else moved
    }

    @Test("A choice takes the step nearest to the controller's value")
    func controllerOnAChoice() throws {
        let synth = Synth()
        let shape = try knob("lfo1shape")                     // Sine ... Wander, seven steps
        let cc = try #require(synth.controller(of: shape))
        send(synth, controller: cc, value: 0)
        #expect(shape.text(synth.value(of: shape)) == "Sine")
        send(synth, controller: cc, value: 64)
        #expect(shape.text(synth.value(of: shape)) == "Ramp Down")
        send(synth, controller: cc, value: 127)
        #expect(shape.text(synth.value(of: shape)) == "Wander")
    }

    @Test("A knob with a middle stands on it at 64")
    func middle() throws {
        let synth = Synth()
        for identifier in ["pan", "tune", "octave"] {
            let bipolar = try knob(identifier)
            #expect(bipolar.isBipolar, "\(identifier)")
            let cc = try #require(synth.controller(of: bipolar))
            send(synth, controller: cc, value: 64)
            #expect(synth.normalisedValue(of: bipolar) == 0.5, "\(identifier)")
            #expect(abs(synth.value(of: bipolar)) < 1e-4, "\(identifier)")
            send(synth, controller: cc, value: 63)
            #expect(synth.normalisedValue(of: bipolar) < 0.5, "\(identifier)")
        }
        let volume = try knob("volume")                       // -40 ... 6 dB has no middle
        send(synth, controller: 7, value: 64)
        #expect(abs(synth.normalisedValue(of: volume) - 64.0 / 127) < 1e-6)
    }

    @Test("In pad mode a controller still moves the keyboard set, and no pad")
    func padModeMovesTheKeyboard() throws {
        let synth = Synth()
        synth.mode = .pads
        let first = Self.first
        let pads = (0..<16).map { synth.normalisedValue(of: first, in: .pad($0)) }
        send(synth, controller: Self.firstCC, value: 127)
        #expect(synth.normalisedValue(of: first) == 1)
        #expect((0..<16).map { synth.normalisedValue(of: first, in: .pad($0)) } == pads)
    }

    @Test("The engine counts what MIDI changed, so that a window knows when to look")
    func changesAreCounted() {
        let synth = Synth()
        let before = synth.changes
        synth.noteOn(48)
        run(synth)
        #expect(synth.changes == before)                      // a note changes no knob
        send(synth, controller: Self.firstCC, value: 100)
        #expect(synth.changes != before)
        let moved = synth.changes
        send(synth, controller: Self.free[0], value: 100)     // nobody listens to it
        send(synth, controller: 1, value: 100)                // the mod wheel moves no knob
        #expect(synth.changes == moved)
    }

    @Test("The mod wheel, Reset All Controllers and All Notes Off move no knob")
    func midisOwnControllers() {
        let synth = Synth()
        let values = Parameters.all.map { synth.normalisedValue(of: $0) }
        for controller in [1, 121, 123, 120, 64, 0] { send(synth, controller: controller, value: 127) }
        #expect(Parameters.all.map { synth.normalisedValue(of: $0) } == values)
    }

    // MARK: Learn

    @Test("A knob that is learning takes the next controller that moves, and that controller's value")
    func learn() throws {
        let synth = Synth()
        let rate = try knob("lfo1rate")
        let standard = try #require(Controllers.standard(for: rate))
        #expect(synth.learning == nil)
        synth.learn(rate)
        #expect(synth.learning == rate)
        let before = synth.changes
        send(synth, controller: Self.free[0], value: 127)
        #expect(synth.learning == nil)
        #expect(synth.changes != before)
        #expect(synth.controller(of: rate) == Self.free[0])
        #expect(synth.normalisedValue(of: rate) == 1)
        send(synth, controller: standard, value: 0)           // the controller it came with
        #expect(synth.normalisedValue(of: rate) == 1)         // no longer moves it
    }

    @Test("Learning can be called off, and a reserved controller does not end it")
    func learnIgnoresReserved() throws {
        let synth = Synth()
        let rate = try knob("lfo1rate")
        let standard = Controllers.standard(for: rate)
        synth.learn(rate)
        send(synth, controller: 1, value: 90)                 // the mod wheel
        send(synth, controller: 64, value: 127)
        #expect(synth.learning == rate)
        #expect(synth.controller(of: rate) == standard)
        synth.learn(nil)
        #expect(synth.learning == nil)
        send(synth, controller: Self.free[0], value: 127)
        #expect(synth.controller(of: rate) == standard)
    }

    @Test("An amount cannot learn")
    func amountsDoNotLearn() throws {
        let synth = Synth()
        synth.learn(try knob("lfo1tune"))
        #expect(synth.learning == nil)
        synth.setController(Self.free[0], of: try knob("lfo1tune"))
        #expect(synth.controller(of: try knob("lfo1tune")) == nil)
    }

    @Test("A controller serves one knob: given to another, the first knob has none")
    func oneKnobPerController() throws {
        let synth = Synth()
        let rate = try knob("lfo1rate"), firstKnob = Self.first
        synth.learn(rate)
        send(synth, controller: Self.firstCC, value: 10)      // the first knob's controller
        #expect(synth.controller(of: rate) == Self.firstCC)
        #expect(synth.controller(of: firstKnob) == nil)
        let firstBefore = synth.value(of: firstKnob)
        send(synth, controller: Self.firstCC, value: 120)
        #expect(synth.value(of: firstKnob) == firstBefore)
    }

    @Test("A knob's controller can be taken away, given by hand, and all put back")
    func setAndReset() throws {
        let synth = Synth()
        let rate = try knob("lfo1rate"), firstKnob = Self.first
        synth.setController(nil, of: firstKnob)
        #expect(synth.controller(of: firstKnob) == nil)
        synth.setController(Self.firstCC, of: rate)
        #expect(synth.controller(of: rate) == Self.firstCC)
        synth.setController(64, of: firstKnob)                    // reserved: not taken
        #expect(synth.controller(of: firstKnob) == nil)
        synth.setController(128, of: firstKnob)                   // not a controller
        #expect(synth.controller(of: firstKnob) == nil)
        synth.resetControllers()
        #expect(Self.knobs.allSatisfy { synth.controller(of: $0) == Controllers.standard(for: $0) })
    }

    @Test("Programs and sent pads leave the controllers alone")
    func soundsKeepControllers() throws {
        let synth = Synth()
        let rate = try knob("lfo1rate")
        synth.setController(Self.free[0], of: rate)
        synth.loadProgram(TestKnobs.otherProgram)
        synth.sendToPad(2)
        synth.loadDefaultKit()
        #expect(synth.controller(of: rate) == Self.free[0])
    }

    // MARK: Storing

    @Test("The controllers round-trip through the form they are stored in, a knob without one included")
    func mapSurvivesStorage() throws {
        let synth = Synth()
        synth.setController(Self.free[0], of: try knob("lfo1rate"))
        synth.setController(nil, of: Self.first)
        let map = ControllerMap(capturing: synth)
        #expect(Set(map.controllers.keys) == Set(Self.knobs.map(\.identifier)))
        let stored = try JSONEncoder().encode(map)

        let other = Synth()
        try JSONDecoder().decode(ControllerMap.self, from: stored).apply(to: other)
        #expect(other.controller(of: try knob("lfo1rate")) == Self.free[0])
        #expect(other.controller(of: Self.first) == nil)
        #expect(other.controller(of: try knob("volume")) == 7)
        #expect(ControllerMap(capturing: other) == map)
    }

    @Test("A stored map from another version: a knob it lacks keeps its standard, a name it has that this version lacks is ignored")
    func tolerantMap() throws {
        let json = Data(#"{"controllers": {"lfo1rate": \#(Self.free[0]), "from-the-future": 50, "\#(Self.first.identifier)": -1}, "unknown": true}"#.utf8)
        let map = try JSONDecoder().decode(ControllerMap.self, from: json)
        let synth = Synth()
        synth.setController(nil, of: try knob("pan"))
        map.apply(to: synth)
        #expect(synth.controller(of: try knob("lfo1rate")) == Self.free[0])
        #expect(synth.controller(of: Self.first) == nil)
        #expect(synth.controller(of: try knob("pan")) == 10)
        #expect(synth.controller(of: try knob("volume")) == 7)

        let empty = try JSONDecoder().decode(ControllerMap.self, from: Data("{}".utf8))
        #expect(empty.controllers.isEmpty)
    }

    @Test("A stored map that gives one controller to two knobs leaves it with one")
    func mapWithAClash() throws {
        let synth = Synth()
        ControllerMap(controllers: ["lfo1rate": Self.free[0], "lfo2rate": Self.free[0]]).apply(to: synth)
        let holders = Self.knobs.filter { synth.controller(of: $0) == Self.free[0] }
        #expect(holders.count == 1)
    }

    // MARK: What the panel shows

    @Test("A controller reads as CC and its number; none as a dash")
    func labels() {
        #expect(Controllers.label(74) == "CC 74")
        #expect(Controllers.label(nil) == "—")
    }

    @Test("Every control on the panel can learn in the keyboard set; a pad's controls and the amounts cannot")
    func whoLearns() throws {
        #expect(Self.knobs.allSatisfy { Controllers.canLearn($0, in: .keyboard) })
        #expect(!Self.knobs.contains { Controllers.canLearn($0, in: .pad(3)) })
        #expect(!Controllers.canLearn(try knob("lfo1tune"), in: .keyboard))
        #expect(!Controllers.canLearn(try knob("velvolume"), in: .keyboard))
    }

    @Test("In MIDI mode a control shows its controller, a dash without one, and asks for a control while it listens")
    func captions() throws {
        let firstKnob = Self.first, volumeKnob = try knob("volume")
        #expect(Controllers.caption(of: firstKnob, in: .keyboard, controller: 74, learning: nil) == "CC 74")
        #expect(Controllers.caption(of: firstKnob, in: .keyboard, controller: nil, learning: nil) == "—")
        #expect(Controllers.caption(of: firstKnob, in: .keyboard, controller: 74, learning: firstKnob) == "move a control")
        #expect(Controllers.caption(of: firstKnob, in: .keyboard, controller: 74, learning: volumeKnob) == "CC 74")
        // A pad's set and an amount have no controllers, whatever the keyboard's knob has.
        #expect(Controllers.caption(of: firstKnob, in: .pad(0), controller: 74, learning: firstKnob) == "—")
        #expect(Controllers.caption(of: try knob("lfo1tune"), in: .keyboard, controller: nil, learning: nil) == "—")
    }
}
