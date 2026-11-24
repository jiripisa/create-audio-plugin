import AppKit
import AudioToolbox
import Foundation
import SwiftUI
import Testing
import {{APP}}AU
import {{APP}}DSP
import {{APP}}UI
@testable import {{APP}}AUView
@testable import {{APP}}Core

/// What a host's listener heard, in order. The listener runs on its own queue.
private final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func add(_ event: String) { lock.withLock { events.append(event) } }
    var all: [String] { lock.withLock { events } }
}

/// The model behind the plug-in's window (`AudioUnitModel`), driving the real Audio Unit (`PlugIn`,
/// `Instrument`: AudioUnitTests.swift) the way the window's knobs, keys and pads and a host do.
@Suite("The plug-in's window")
@MainActor
struct AudioUnitWindowTests {

    /// The window's model, with the player's files in a folder of the test's own: by default one
    /// nobody made, which holds nothing (the tests stay out of ~/Library/Application Support/{{APP}}).
    private func model(of instrument: Instrument,
                       files: (presets: PresetLibrary, kits: KitLibrary) = PresetShelvesTests.libraries()) throws -> AudioUnitModel {
        try #require(AudioUnitModel(unit: instrument.unit, presets: files.presets, kits: files.kits))
    }

    private func presentPreset(of unit: AudioUnit) throws -> Int {
        var preset = AUPreset()
        var size = UInt32(MemoryLayout<AUPreset>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &preset, &size) == noErr)
        preset.presetName?.release()
        return Int(preset.presetNumber)
    }

    /// Counts the unit's notices that its saved state changed, as a host listens for them to
    /// mark the project edited.
    private func countStateChanges(of unit: AudioUnit, _ body: (Calls) throws -> Void) throws {
        let calls = Calls()
        let listener: AudioUnitPropertyListenerProc = { refCon, _, id, scope, _ in
            guard id == kAudioUnitProperty_ClassInfo, scope == kAudioUnitScope_Global else { return }
            Unmanaged<Calls>.fromOpaque(refCon).takeUnretainedValue().count += 1
        }
        let refCon = Unmanaged.passUnretained(calls).toOpaque()
        try #require(AudioUnitAddPropertyListener(unit, kAudioUnitProperty_ClassInfo, listener, refCon) == noErr)
        defer { AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_ClassInfo, listener, refCon) }
        try body(calls)
    }

    @Test("The window asks the unit by the numbers of {{APP}}AU.h")
    func propertyNumbers() {
        #expect(AudioUnitModel.engineProperty == AudioUnitPropertyID(k{{APP}}Property_Engine))
        #expect(AudioUnitModel.stateChangedProperty == AudioUnitPropertyID(k{{APP}}Property_StateChanged))
        #expect(AudioUnitModel.selectedPadProperty == AudioUnitPropertyID(k{{APP}}Property_SelectedPad))
        #expect(AudioUnitModel.presetNamesProperty == AudioUnitPropertyID(k{{APP}}Property_PresetNames))
    }

    // MARK: The keyboard set: the unit's parameters

    @Test("Turning a knob of the keyboard sets the Audio Unit's parameter")
    func knobSetsParameter() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let programmed = TestKnobs.programKnob
        let lfostart = try #require(Parameters.named("lfostart"))

        model.setPosition(1, of: programmed, in: .keyboard)
        let top = programmed.plain(1)                                   // the top, to a few ulps
        #expect(abs(top - programmed.range.upperBound) < 1e-4)
        #expect(try instrument.parameter(programmed.index) == top)
        #expect(abs(model.position(of: programmed, in: .keyboard) - 1) < 1e-6)

        model.setPosition(0.45, of: lfostart, in: .keyboard)        // a choice snaps to its step
        let value = try instrument.parameter(lfostart.index)
        #expect(value == value.rounded())
        #expect(model.value(of: lfostart, in: .keyboard) == value)

        // The engine gets it at the next render, as from a host.
        let engine = try instrument.engine()
        _ = try instrument.render()
        #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(programmed.index)) - top) < 1e-4)
    }

    @Test("A parameter or program the host changes shows in the window at the next refresh")
    func hostChangeShows() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let tune = try #require(Parameters.named("tune"))
        let programmed = TestKnobs.programKnob
        #expect(abs(model.value(of: tune, in: .keyboard) - tune.defaultValue) < 0.01)

        try instrument.setParameter("tune", to: tune.range.upperBound)
        model.refresh()
        #expect(model.position(of: tune, in: .keyboard) == 1)

        try instrument.loadPreset(TestKnobs.otherProgram)                          // the host's preset menu
        model.refresh()
        #expect(model.program(in: .keyboard) == TestKnobs.otherProgram)
        #expect(abs(model.value(of: programmed, in: .keyboard) - Programs.value(program: TestKnobs.otherProgram, parameter: programmed)) < 0.001)
    }

    @Test("Choosing a program loads the factory preset and leaves the octave alone")
    func choosingAProgram() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let octave = try #require(Parameters.named("octave"))
        let programmed = TestKnobs.programKnob
        model.setPosition(1, of: octave, in: .keyboard)        // +2

        model.loadProgram(TestKnobs.otherProgram, into: .keyboard)
        #expect(model.program(in: .keyboard) == TestKnobs.otherProgram)
        #expect(try presentPreset(of: instrument.unit) == TestKnobs.otherProgram)
        #expect(try instrument.parameter(programmed.index) == Programs.value(program: TestKnobs.otherProgram, parameter: programmed))
        #expect(abs(model.value(of: programmed, in: .keyboard) - Programs.value(program: TestKnobs.otherProgram, parameter: programmed)) < 0.001)
        #expect(try instrument.parameter(octave.index) == 2)

        // A double click goes back to the program's value (through the knob's position: to a few ulps).
        model.setPosition(1, of: programmed, in: .keyboard)
        model.resetToDefault(programmed, in: .keyboard)
        #expect(abs(try instrument.parameter(programmed.index) - Programs.value(program: TestKnobs.otherProgram, parameter: programmed)) <= 1e-6 * max(1, Programs.value(program: TestKnobs.otherProgram, parameter: programmed)))
    }

    @Test("After a project is reopened, the window shows the keyboard's program the engine holds")
    func programShownAfterRestore() throws {
        let saved = try Instrument()
        try saved.loadPreset(TestKnobs.otherProgram)
        try saved.setParameter("velsens", to: 55)                // the sound is no longer the preset's
        let state = try saved.classInfo()

        let reopened = try Instrument()
        let window = try model(of: reopened)                  // the window is open while the host restores
        try reopened.restore(state)
        #expect(try presentPreset(of: reopened.unit) == -1)   // the SDK forgets the number …
        window.refresh()
        #expect(window.program(in: .keyboard) == TestKnobs.otherProgram)            // … the engine does not
        #expect(window.padName(0) == PadLabel.name(program: window.program(in: .pad(0))))

        // A window opened afterwards shows it too, and a double click goes back to its value.
        let later = try model(of: reopened)
        #expect(later.program(in: .keyboard) == TestKnobs.otherProgram)
        let sens = try #require(Parameters.named("velsens"))
        #expect(later.value(of: sens, in: .keyboard) == 55)
        later.resetToDefault(sens, in: .keyboard)
        #expect(try reopened.parameter(sens.index) == Programs.value(program: TestKnobs.otherProgram, parameter: sens))
    }

    /// A host's listener for one parameter. It runs on a queue of its own, so it is made outside
    /// the main actor.
    private nonisolated static func listen(to parameter: Parameter, of unit: AudioUnit, heard: Heard) throws -> AUEventListenerRef {
        var listener: AUEventListenerRef?
        try #require(AUEventListenerCreateWithDispatchQueue(&listener, 0, 0, DispatchQueue(label: "host")) { _, event, _, value in
            switch event.pointee.mEventType {
            case .beginParameterChangeGesture: heard.add("begin")
            case .endParameterChangeGesture: heard.add("end")
            case .parameterValueChange: heard.add("value \(Int(value))")
            default: break
            }
        } == noErr)
        let host = try #require(listener)
        let address = AudioUnitParameter(mAudioUnit: unit, mParameterID: parameter.unitID,
                                         mScope: kAudioUnitScope_Global, mElement: 0)
        for type in [AudioUnitEventType.beginParameterChangeGesture, .parameterValueChange, .endParameterChangeGesture] {
            var event = AudioUnitEvent(mEventType: type, mArgument: .init(mParameter: address))
            try #require(AUEventListenerAddEventType(host, nil, &event) == noErr)
        }
        return host
    }

    @Test("A drag tells the host where it begins, what it sets and where it ends")
    func dragIsHeardByTheHost() async throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let sens = try #require(Parameters.named("velsens"))

        // A host listens to the parameter the way it does to record automation.
        let heard = Heard()
        let host = try Self.listen(to: sens, of: instrument.unit, heard: heard)
        defer { AUListenerDispose(host) }

        model.beginEditing(sens, in: .keyboard)
        model.setPosition(0.5, of: sens, in: .keyboard)
        model.endEditing(sens, in: .keyboard)

        for _ in 0..<200 where heard.all.count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(heard.all == ["begin", "value 50", "end"])
    }

    // MARK: The pads: the engine

    @Test("Knobs, programs and resets in pad mode change the pad's set, never the unit's parameters")
    func padEditsStayInPad() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        let programmed = TestKnobs.programKnob
        let sens = try #require(Parameters.named("velsens"))
        let padSet = Int32(1 + 4)

        model.mode = .pads
        model.selectedPad = 4
        #expect(model.shownSet == .pad(4))
        #expect({{APP_C}}_get_mode(engine) == Int32({{APP_UPPER}}_MODE_PADS))

        model.setPosition(1, of: programmed, in: .pad(4))
        model.loadProgram(TestKnobs.otherProgram, into: .pad(4))
        model.setPosition(1, of: sens, in: .pad(4))
        _ = try instrument.render()
        #expect(model.program(in: .pad(4)) == TestKnobs.otherProgram)
        #expect(model.padName(4) == Programs.names[TestKnobs.otherProgram])
        #expect({{APP_C}}_get_program(engine, padSet) == Int32(TestKnobs.otherProgram))
        #expect({{APP_C}}_get_plain(engine, padSet, Int32(sens.index)) == sens.range.upperBound)
        #expect(model.position(of: sens, in: .pad(4)) == 1)

        model.resetToDefault(sens, in: .pad(4))
        #expect(abs({{APP_C}}_get_plain(engine, padSet, Int32(sens.index)) - Programs.value(program: TestKnobs.otherProgram, parameter: sens)) < 0.001)

        // The keyboard set, the unit's parameters and its preset are as they were.
        for parameter in Parameters.all {
            #expect(try instrument.parameter(parameter.index) == parameter.defaultValue, "\(parameter.identifier)")
            #expect(model.position(of: parameter, in: .keyboard) == Double(parameter.normalised(parameter.defaultValue)))
        }
        #expect(model.program(in: .keyboard) == 0)
        #expect(try presentPreset(of: instrument.unit) == 0)

        // And the other way round: the keyboard's knobs leave the pad alone.
        let padRelease = {{APP_C}}_get_plain(engine, padSet, Int32(programmed.index))
        model.setPosition(0, of: programmed, in: .keyboard)
        model.loadProgram(0, into: .keyboard)
        _ = try instrument.render()
        #expect({{APP_C}}_get_plain(engine, padSet, Int32(programmed.index)) == padRelease)
        #expect({{APP_C}}_get_program(engine, padSet) == Int32(TestKnobs.otherProgram))
    }

    @Test("Pad notes, groups and the mode go to the engine and come back from it")
    func padNotesAndGroups() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)

        model.setPadNote(60, pad: 2)
        model.setPadGroup(7, pad: 2)
        model.setPadGroup(nil, pad: 3)
        #expect({{APP_C}}_pad_note(engine, 2) == 60)
        #expect({{APP_C}}_pad_group(engine, 2) == 7)
        #expect({{APP_C}}_pad_group(engine, 3) == 0)
        #expect(model.padNote(2) == 60)
        #expect(model.padGroup(2) == 7)
        #expect(model.padGroup(3) == nil)

        // What the host restores while the window is open shows at the next refresh.
        {{APP_C}}_set_pad_note(engine, 9, 70)
        {{APP_C}}_set_pad_group(engine, 9, 12)
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
        model.refresh()
        #expect(model.padNote(9) == 70)
        #expect(model.padGroup(9) == 12)
        #expect(model.mode == .pads)
    }

    @Test("An edit of the pads or the mode marks the project edited, at most once per half second")
    func padEditsTellTheHost() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let programmed = TestKnobs.programKnob

        try countStateChanges(of: instrument.unit) { calls in
            // A drag edits many times; the host hears of it once, after it rests.
            for step in 0...20 { model.setPosition(Double(step) / 20, of: programmed, in: .pad(1)) }
            model.refresh()
            #expect(calls.count == 0)
            model.tellHostIfEdited()                          // the window closes
            #expect(calls.count == 1)
            model.tellHostIfEdited()
            #expect(calls.count == 1)                         // nothing new

            // The keyboard's knobs are the unit's parameters: the host knows of them already.
            model.setPosition(0.3, of: programmed, in: .keyboard)
            model.tellHostIfEdited()
            #expect(calls.count == 1)

            model.mode = .pads
            model.tellHostIfEdited()
            #expect(calls.count == 2)
        }
    }

    @Test("The host hears of a pad edit half a second after it, from the window's refresh")
    func padEditsTellTheHostLater() async throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)

        try countStateChanges(of: instrument.unit) { calls in
            model.setPadNote(50, pad: 0)
            model.refresh()
            #expect(calls.count == 0)
        }
        try await Task.sleep(for: SaveDebounce.delay + .milliseconds(50))
        try countStateChanges(of: instrument.unit) { calls in
            model.refresh()
            #expect(calls.count == 1)
            model.refresh()
            #expect(calls.count == 1)
        }
    }

    // MARK: Playing on screen

    @Test("Send to pad from the window copies the keyboard's sound as the unit holds it, at the last note")
    func sendToPadFromWindow() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        let programmed = TestKnobs.programKnob

        model.keyDown(55, velocity: 100)                      // the window's keyboard
        _ = try instrument.render()
        model.keyUp(55)
        model.refresh()
        #expect(model.lastNote == 55)

        model.loadProgram(TestKnobs.otherProgram, into: .keyboard)
        model.setPosition(1, of: programmed, in: .keyboard)         // not rendered yet: only the unit holds it
        model.sendToPad(6)

        let padSet = Int32(1 + 6)
        #expect({{APP_C}}_pad_note(engine, 6) == 55)
        #expect({{APP_C}}_get_program(engine, padSet) == Int32(TestKnobs.otherProgram))
        #expect(abs({{APP_C}}_get_plain(engine, padSet, Int32(programmed.index)) - programmed.range.upperBound) < 1e-4)
        #expect(model.padNote(6) == 55)
        #expect(model.program(in: .pad(6)) == TestKnobs.otherProgram)
        #expect(model.position(of: programmed, in: .pad(6)) == 1)
    }

    @Test("A pad hit on screen plays the pad, selects it and counts")
    func padHitPlays() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        model.mode = .pads

        model.hitPad(3, velocity: 90)
        _ = try instrument.render()
        model.releasePad(3)
        model.refresh()
        #expect(model.selectedPad == 3)
        #expect(model.padHits(3) == 1)
        #expect(model.padHits(2) == 0)
    }

    @Test("Closing the window lets go of the keys it holds")
    func closingReleasesHeldKeys() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        // A released key's voice dies away within the default Release; the two keys are two voices.

        model.keyDown(50, velocity: 100)
        model.keyDown(57, velocity: 100)
        _ = try instrument.render()
        #expect({{APP_C}}_sounding_voices(engine) == 2)

        model.releaseHeld()                                   // the window goes away mid-press
        _ = try instrument.render(seconds: 1.2)
        #expect({{APP_C}}_sounding_voices(engine) == 0)
    }

    // MARK: A unit that is gone

    /// A unit not owned by an `Instrument`, so that the test can dispose of it while the window's
    /// model lives on, as a host may.
    private func disposableUnit() throws -> AudioUnit {
        var made: AudioUnit?
        try #require(AudioComponentInstanceNew(PlugIn.component, &made) == noErr)
        let unit = try #require(made)
        try #require(AudioUnitInitialize(unit) == noErr)
        return unit
    }

    @Test("A window whose unit the host disposed of leaves the unit and its engine alone")
    func unitGoneDetaches() throws {
        let unit = try disposableUnit()
        let model = try #require(AudioUnitModel(unit: unit))
        let programmed = TestKnobs.programKnob
        model.setPadNote(60, pad: 1)                          // a notice for the host is waiting
        let padRelease = model.position(of: programmed, in: .pad(2))
        let keyboardRelease = model.position(of: programmed, in: .keyboard)
        let group = model.padGroup(1)
        #expect(!model.isDetached)

        AudioComponentInstanceDispose(unit)
        model.refresh()
        #expect(model.isDetached)

        // Everything the window can still do is dropped: nothing reaches the freed engine.
        model.mode = .pads
        model.setPosition(1, of: programmed, in: .pad(2))
        model.beginEditing(programmed, in: .keyboard)
        model.setPosition(0, of: programmed, in: .keyboard)
        model.endEditing(programmed, in: .keyboard)
        model.resetToDefault(programmed, in: .pad(2))
        model.loadProgram(TestKnobs.otherProgram, into: .keyboard)
        model.loadProgram(TestKnobs.otherProgram, into: .pad(2))
        model.setPadNote(70, pad: 1)
        model.setPadGroup(9, pad: 1)
        model.sendToPad(5)
        model.hitPad(4, velocity: 100)
        model.releasePad(4)
        model.keyDown(50, velocity: 100)
        model.keyUp(50)
        model.selectedPad = 7
        model.releaseHeld()
        model.tellHostIfEdited()
        model.refresh()

        #expect(model.mode == .keyboard)
        #expect(model.position(of: programmed, in: .pad(2)) == padRelease)
        #expect(model.position(of: programmed, in: .keyboard) == keyboardRelease)
        #expect(model.program(in: .keyboard) == 0)
        #expect(model.padNote(1) == 60)
        #expect(model.padGroup(1) == group)
        #expect(model.selectedPad == 7)                       // the window's own, no engine behind it
    }

    @Test("The first touch after the unit is gone detaches too, not only the refresh")
    func unitGoneBeforeAnyRefresh() throws {
        let unit = try disposableUnit()
        let model = try #require(AudioUnitModel(unit: unit))
        AudioComponentInstanceDispose(unit)

        model.keyDown(50, velocity: 100)
        #expect(model.isDetached)
        model.releaseHeld()
    }

    // MARK: Presets

    private func remove(_ files: (presets: PresetLibrary, kits: KitLibrary)) {
        try? FileManager.default.removeItem(at: files.presets.folder.deletingLastPathComponent())
    }

    /// The name of the unit's present preset: what a host shows and saves with its project.
    private func presentPresetName(of unit: AudioUnit) throws -> String? {
        var preset = AUPreset()
        var size = UInt32(MemoryLayout<AUPreset>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &preset, &size) == noErr)
        return preset.presetName?.takeRetainedValue() as String?
    }

    private func knob(_ identifier: String) throws -> Parameter { try #require(Parameters.named(identifier)) }

    /// A keyboard sound no program has: the last program with Tune at 37 cents, the octave up and
    /// LFO 1 on Tune.
    private func makeASound(with model: AudioUnitModel) throws {
        model.loadProgram(TestKnobs.otherProgram, into: .keyboard)
        model.setPosition(Double(try knob("tune").normalised(37)), of: try knob("tune"), in: .keyboard)
        model.setPosition(Double(try knob("octave").normalised(1)), of: try knob("octave"), in: .keyboard)
        model.setPosition(Double(try knob("lfo1tune").normalised(30)), of: try knob("lfo1tune"), in: .keyboard)
    }

    /// The sound of `makeASound` is in the unit's parameters.
    private func expectTheSound(in instrument: Instrument, _ comment: Comment? = nil) throws {
        #expect(abs(try instrument.parameter(try knob("tune").index) - 37) < 0.5, comment)
        #expect(try instrument.parameter(try knob("octave").index) == 1, comment)
        #expect(abs(try instrument.parameter(try knob("lfo1tune").index) - 30) < 0.01, comment)
    }

    @Test("The window saves a set's sound as a preset, and loading it into the keyboard or a pad brings every value back")
    func windowSavesAndLoadsAPreset() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument, files: files)
        let tune = try knob("tune"), programmed = TestKnobs.programKnob
        #expect(model.presets.isEmpty)
        #expect(model.presetInUse(in: .keyboard) == nil)

        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)
        #expect(model.presets == ["Mine"])
        #expect(model.presetInUse(in: .keyboard) == "Mine")
        #expect(try presentPreset(of: instrument.unit) == -1)            // not a factory preset any more
        #expect(try presentPresetName(of: instrument.unit) == "Mine")    // what the host shows and saves
        #expect(try instrument.presetNames()[0] == "Mine")

        model.loadProgram(0, into: .keyboard)
        model.setPosition(Double(try knob("octave").normalised(-1)), of: try knob("octave"), in: .keyboard)
        #expect(model.presetInUse(in: .keyboard) == nil)
        #expect(try instrument.presetNames()[0] == "")
        #expect(abs(try instrument.parameter(tune.index) - 37) > 1)

        // Into the keyboard: the unit's parameters, the program it grew from, and its name.
        try model.loadPreset("Mine", into: .keyboard)
        #expect(model.presetInUse(in: .keyboard) == "Mine")
        try expectTheSound(in: instrument)
        #expect(abs(model.value(of: tune, in: .keyboard) - 37) < 0.5)   // the window's knob too
        #expect(model.program(in: .keyboard) == TestKnobs.otherProgram)
        #expect({{APP_C}}_get_program(engine, Int32({{APP_UPPER}}_KEYBOARD_SET)) == Int32(TestKnobs.otherProgram))
        #expect(try presentPresetName(of: instrument.unit) == "Mine")
        #expect(try instrument.presetNames()[0] == "Mine")
        _ = try instrument.render()
        #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(tune.index)) - 37) < 0.5)

        // Into a pad: the engine; the keyboard and the unit's parameters stay.
        try model.loadPreset("Mine", into: .pad(4))
        let padSet = Int32(1 + 4)
        #expect(abs({{APP_C}}_get_plain(engine, padSet, Int32(tune.index)) - 37) < 0.5)
        #expect({{APP_C}}_get_program(engine, padSet) == Int32(TestKnobs.otherProgram))
        #expect(abs(model.value(of: tune, in: .pad(4)) - 37) < 0.5)
        #expect(model.presetInUse(in: .pad(4)) == "Mine")
        #expect(model.padName(4) == "Mine")
        #expect(model.padName(5) == PadLabel.name(program: model.program(in: .pad(5))))
        #expect(try instrument.presetNames()[5] == "Mine")

        // Saved from a pad: the pad's own sound.
        model.setPosition(1, of: programmed, in: .pad(4))
        try model.savePreset(as: "Pad sound", from: .pad(4))
        #expect(model.presets == ["Mine", "Pad sound"])
        #expect(model.presetInUse(in: .pad(4)) == "Pad sound")
        #expect(abs(try files.presets.load("Pad sound").values[TestKnobs.programKnob.identifier]! - programmed.range.upperBound) < 1e-3)
        #expect(model.presetInUse(in: .keyboard) == "Mine")
        try expectTheSound(in: instrument)
    }

    @Test("The host hears of a preset loaded into the keyboard value by value, and of the names in use")
    func presetLoadIsHeard() async throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let model = try model(of: instrument, files: files)
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)
        model.loadProgram(0, into: .keyboard)
        model.tellHostIfEdited()

        let tune = try knob("tune")
        let heard = Heard()
        let host = try Self.listen(to: tune, of: instrument.unit, heard: heard)
        defer { AUListenerDispose(host) }
        try countStateChanges(of: instrument.unit) { calls in
            try model.loadPreset("Mine", into: .keyboard)
            model.tellHostIfEdited()                          // the names in use are saved state
            #expect(calls.count == 1)
        }
        for _ in 0..<200 where !heard.all.contains("value 37") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(heard.all.contains("value 37"))
    }

    @Test("A double click on a knob returns the value of the set's preset in use, and a program's after that")
    func resetReturnsThePresetsValue() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument, files: files)
        let tune = try knob("tune")
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)

        model.setPosition(Double(tune.normalised(2000)), of: tune, in: .keyboard)
        model.resetToDefault(tune, in: .keyboard)
        #expect(abs(try instrument.parameter(tune.index) - 37) < 0.5)

        try model.loadPreset("Mine", into: .pad(2))
        model.setPosition(Double(tune.normalised(2000)), of: tune, in: .pad(2))
        model.resetToDefault(tune, in: .pad(2))
        #expect(abs({{APP_C}}_get_plain(engine, 3, Int32(tune.index)) - 37) < 0.5)

        model.loadProgram(0, into: .keyboard)
        model.setPosition(Double(tune.normalised(2000)), of: tune, in: .keyboard)
        model.resetToDefault(tune, in: .keyboard)
        #expect(abs(try instrument.parameter(tune.index) - Programs.value(program: 0, parameter: tune)) < 0.5)
        model.loadProgram(TestKnobs.otherProgram, into: .pad(2))
        model.resetToDefault(tune, in: .pad(2))
        #expect(abs({{APP_C}}_get_plain(engine, 3, Int32(tune.index)) - Programs.value(program: TestKnobs.otherProgram, parameter: tune)) < 0.5)
    }

    @Test("A host's project brings the presets in use back, and the window shows them while the folder has them")
    func projectBringsThePresetBack() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let saved = try Instrument()
        let model = try model(of: saved, files: files)
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)
        try model.loadPreset("Mine", into: .pad(6))
        let state = try saved.classInfo()

        let reopened = try Instrument()
        let open = try self.model(of: reopened, files: files)       // the window is open while the host restores
        try reopened.restore(state)
        open.refresh()
        #expect(open.presetInUse(in: .keyboard) == "Mine")
        #expect(open.presetInUse(in: .pad(6)) == "Mine")
        #expect(open.padName(6) == "Mine")
        try expectTheSound(in: reopened)

        let later = try self.model(of: reopened, files: files)      // a window opened afterwards
        #expect(later.presetInUse(in: .keyboard) == "Mine")
        #expect(later.presetInUse(in: .pad(6)) == "Mine")

        // On a Mac whose folder does not have the preset, the sound is there and no preset is in
        // use, but the project keeps the names for a Mac that has it.
        let elsewhere = try self.model(of: reopened)
        #expect(elsewhere.presetInUse(in: .keyboard) == nil)
        #expect(elsewhere.padName(6) == PadLabel.name(program: TestKnobs.otherProgram))
        elsewhere.refresh()
        #expect(try reopened.presetNames()[0] == "Mine")
        #expect(try reopened.presetNames()[7] == "Mine")

        try files.presets.delete("Mine")                                 // the Finder took it away
        later.lookAtPresets()
        #expect(later.presets.isEmpty)
        #expect(later.presetInUse(in: .keyboard) == nil)
        #expect(later.presetInUse(in: .pad(6)) == nil)
    }

    @Test("A host's own choice of a program leaves the keyboard with no preset in use")
    func hostProgramLeavesThePreset() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let model = try model(of: instrument, files: files)
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)

        try instrument.loadPreset(TestKnobs.otherProgram)                          // the host's preset menu
        model.refresh()
        #expect(model.presetInUse(in: .keyboard) == nil)
        #expect(try instrument.presetNames()[0] == "")

        // Chosen while no window was open: the next window sees it.
        try model.loadPreset("Mine", into: .keyboard)
        try instrument.loadPreset(1)
        let next = try self.model(of: instrument, files: files)
        #expect(next.presetInUse(in: .keyboard) == nil)
        #expect(try instrument.presetNames()[0] == "")
    }

    @Test("A program the host chooses with the window closed is saved with no keyboard preset in use; the pads keep theirs")
    func hostProgramWithTheWindowClosed() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let model = try model(of: instrument, files: files)
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)
        try model.loadPreset("Mine", into: .pad(3))
        model.windowClosed()

        try instrument.loadPreset(TestKnobs.otherProgram)                          // the host's preset menu, no window to see it
        let state = try instrument.classInfo()
        let pads = try #require((state as? [String: Any])?["{{APP_LOWER}}-pads"] as? [String: Any])
        #expect(pads["keyboardPreset"] as? String == "")

        let reopened = try Instrument()
        try reopened.restore(state)
        #expect(try reopened.presetNames()[0] == "")
        #expect(try reopened.presetNames()[4] == "Mine")
        let window = try self.model(of: reopened, files: files)
        #expect(window.presetInUse(in: .keyboard) == nil)
        #expect(window.presetInUse(in: .pad(3)) == "Mine")
    }

    @Test("A preset or a kit saved in another window shows up after a look at the folders")
    func presetsOfAnotherWindow() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let one = try Instrument(), other = try Instrument()
        let mine = try model(of: one, files: files), theirs = try model(of: other, files: files)
        try makeASound(with: theirs)
        try theirs.savePreset(as: "Shared", from: .keyboard)
        try theirs.saveKit(as: "Their kit")
        #expect(mine.presets.isEmpty && mine.kits.isEmpty)
        mine.lookAtPresets()
        #expect(mine.presets == ["Shared"])
        #expect(mine.kits == ["Their kit"])
        try mine.loadPreset("Shared", into: .keyboard)
        try expectTheSound(in: one)
        #expect(mine.presetInUse(in: .keyboard) == "Shared")
    }

    @Test("Deleting the preset in use leaves the sound and no preset in use; a preset that is gone is not loaded")
    func deletingAPreset() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let model = try model(of: instrument, files: files)
        let tune = try knob("tune")
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)
        try model.loadPreset("Mine", into: .pad(1))
        model.tellHostIfEdited()

        try countStateChanges(of: instrument.unit) { calls in
            try model.deletePreset("Mine")
            model.tellHostIfEdited()
            #expect(calls.count == 1)
        }
        #expect(model.presets.isEmpty)
        #expect(model.presetInUse(in: .keyboard) == nil)
        #expect(model.presetInUse(in: .pad(1)) == nil)
        #expect(try instrument.presetNames() == [String](repeating: "", count: 17))
        try expectTheSound(in: instrument)
        model.refresh()
        #expect(model.presetInUse(in: .keyboard) == nil)

        // A double click goes to the program's value now.
        model.resetToDefault(tune, in: .keyboard)
        #expect(abs(try instrument.parameter(tune.index) - Programs.value(program: TestKnobs.otherProgram, parameter: tune)) < 0.5)

        // Failures are thrown and shown, and change nothing.
        #expect(model.lastError == nil)
        #expect(throws: PresetError.missing("Mine")) { try model.loadPreset("Mine", into: .keyboard) }
        #expect(model.lastError == PresetError.missing("Mine").errorDescription)
        let first = try #require(model.lastErrorTime)
        #expect(throws: PresetError.noName) { try model.savePreset(as: " ", from: .keyboard) }
        #expect(model.lastError == PresetError.noName.errorDescription)
        #expect(try #require(model.lastErrorTime) >= first)
        #expect(model.presets.isEmpty)
    }

    // MARK: Kits

    @Test("A kit saved from the window brings back every pad with its preset in use; the default kit has none")
    func kitRoundTrip() throws {
        let files = PresetShelvesTests.libraries()
        defer { remove(files) }
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument, files: files)
        let tune = try knob("tune"), programmed = TestKnobs.programKnob
        try makeASound(with: model)
        try model.savePreset(as: "Mine", from: .keyboard)
        try model.loadPreset("Mine", into: .pad(1))
        model.setPadNote(60, pad: 3)
        model.setPadGroup(5, pad: 3)
        model.loadProgram(TestKnobs.otherProgram, into: .pad(7))
        model.setPosition(1, of: programmed, in: .pad(7))

        try model.saveKit(as: "Kit A")
        #expect(model.kits == ["Kit A"])
        #expect(try files.kits.load("Kit A").pads[1].set.preset == "Mine")

        model.loadDefaultKit()
        #expect(model.presetInUse(in: .pad(1)) == nil)
        let standard = Synth(sampleRate: 48_000)                         // the engine's own kit
        #expect(model.padNote(3) == standard.padNote(3))
        #expect(model.padGroup(3) == standard.padGroup(3))
        #expect(try instrument.presetNames().dropFirst().allSatisfy(\.isEmpty))
        #expect(try instrument.presetNames()[0] == "Mine")              // the keyboard keeps its own

        model.mode = .pads
        try model.loadKit("kit a")
        #expect(model.mode == .pads)
        #expect(model.presetInUse(in: .pad(1)) == "Mine")
        #expect(model.padName(1) == "Mine")
        #expect(abs({{APP_C}}_get_plain(engine, 2, Int32(tune.index)) - 37) < 0.5)
        #expect(model.padNote(3) == 60 && {{APP_C}}_pad_note(engine, 3) == 60)
        #expect(model.padGroup(3) == 5)
        #expect(model.program(in: .pad(7)) == TestKnobs.otherProgram)
        #expect(model.position(of: programmed, in: .pad(7)) == 1)
        #expect(try instrument.presetNames()[2] == "Mine")
        try expectTheSound(in: instrument)                               // the keyboard is untouched

        try model.deleteKit("Kit A")
        #expect(model.kits.isEmpty)
        #expect(throws: PresetError.missing("Kit A")) { try model.loadKit("Kit A") }
        #expect(model.lastError != nil)
    }

    // MARK: MIDI controllers

    /// A control change on channel 1, played in the next block.
    private func send(controller: UInt32, value: UInt32, to instrument: Instrument) throws {
        try instrument.midi(0xB0, controller, value)
        _ = try instrument.render()
    }

    @Test("The window learns a controller, gives and takes them, and the project keeps them")
    func windowLearns() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let programmed = TestKnobs.programKnob, tune = try knob("tune")
        #expect(model.learning == nil)
        #expect(model.controller(of: programmed) == Controllers.standard(for: programmed))
        #expect(model.controller(of: try knob("lfo1tune")) == nil)

        try countStateChanges(of: instrument.unit) { calls in
            model.learn(programmed)
            #expect(model.learning == programmed)
            try send(controller: UInt32(TestKnobs.freeControllers[0]), value: 127, to: instrument)
            model.refresh()
            #expect(model.learning == nil)
            #expect(model.controller(of: programmed) == TestKnobs.freeControllers[0])
            #expect(abs(try instrument.parameter(programmed.index) - programmed.range.upperBound) < 1e-3)
            model.tellHostIfEdited()
            #expect(calls.count == 1)                         // the learnt controller is saved state

            model.setController(102, of: programmed)                // Tune's: it moves over
            #expect(model.controller(of: programmed) == 102)
            #expect(model.controller(of: tune) == nil)
            model.setController(nil, of: programmed)
            #expect(model.controller(of: programmed) == nil)
            model.tellHostIfEdited()
            #expect(calls.count == 2)
        }

        let state = try instrument.classInfo()
        model.resetControllers()
        #expect(model.controller(of: programmed) == Controllers.standard(for: programmed))
        #expect(model.controller(of: tune) == 102)

        let reopened = try Instrument()
        try reopened.restore(state)
        let later = try self.model(of: reopened)
        #expect(later.controller(of: programmed) == nil)
        #expect(later.controller(of: tune) == nil)
    }

    @Test("Closing the window or switching to the pads calls a learn off: no knob is left listening")
    func learnCancelledOnClose() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        let tune = try knob("tune")

        model.learn(tune)
        #expect({{APP_C}}_learning(engine) == Int32(tune.index))
        model.windowClosed()
        #expect(model.learning == nil)
        #expect({{APP_C}}_learning(engine) == -1)
        try send(controller: UInt32(TestKnobs.freeControllers[0]), value: 100, to: instrument)
        model.refresh()
        #expect(model.controller(of: tune) == 102)
        #expect(!Parameters.all.contains { model.controller(of: $0) == TestKnobs.freeControllers[0] })

        model.learn(tune)
        model.mode = .pads
        #expect(model.learning == nil)
        #expect({{APP_C}}_learning(engine) == -1)

        // A mode the host restores calls it off too.
        model.mode = .keyboard
        model.learn(tune)
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_PADS))
        model.refresh()
        #expect(model.learning == nil)
        #expect({{APP_C}}_learning(engine) == -1)
    }

    // MARK: The selected pad

    @Test("The window reopens on the pad it showed, which the project keeps, though choosing a pad is no edit of it")
    func windowReopensOnSelectedPad() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        #expect(model.selectedPad == 0)

        try countStateChanges(of: instrument.unit) { calls in
            model.hitPad(2, velocity: 90)                     // auditioning pads selects them
            model.releasePad(2)
            #expect(model.selectedPad == 2)
            model.selectedPad = 9
            model.tellHostIfEdited()
            #expect(calls.count == 0)                         // the host does not ask to save
        }
        #expect(try instrument.selectedPad() == 9)
        #expect(try self.model(of: instrument).selectedPad == 9)

        let reopened = try Instrument()
        let open = try self.model(of: reopened)
        try reopened.restore(try instrument.classInfo())
        #expect(try self.model(of: reopened).selectedPad == 9)
        open.refresh()                                        // a window open while the host restores
        #expect(open.selectedPad == 9)

        model.selectedPad = 42                                // no such pad: the unit keeps its own
        #expect(try instrument.selectedPad() == 9)
    }

    // MARK: The window

    @Test("The window opens without the component's artwork, at the panel's width")
    func windowWithoutArt() throws {
        let before = Artwork.bundle
        defer { Artwork.bundle = before }                     // the factory points it at its own bundle
        let instrument = try Instrument()
        let view = try #require({{APP}}AUViewFactory().uiView(forAudioUnit: instrument.unit, with: .zero))
        // In the tests the factory's class lives in the test bundle, which holds no artwork.
        #expect(Artwork.bundle == Bundle(for: {{APP}}AUViewFactory.self))
        #expect(Artwork.bundle.url(forResource: "background", withExtension: "png", subdirectory: "Art") == nil)
        #expect(view.frame.width == InstrumentPanel<EmptyView, EmptyView>.width)
        #expect(view.frame.height > 400)
    }
}
