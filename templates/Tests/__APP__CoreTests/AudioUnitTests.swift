import AudioToolbox
import Foundation
import Testing
import {{APP}}AU
import {{APP}}DSP
@testable import {{APP}}Core

/// The Audio Unit, registered with this process only (no component bundle) under a subtype of
/// its own, so that an installed copy stays out of it. The plug-in window's tests use it too.
@MainActor
enum PlugIn {

    /// The plug-in's subtype ('{{AU_SUBTYPE}}') with its last character changed to `t` (to `u` when it
    /// already is a `t`): never the subtype of an installed copy.
    static let subtypeUnderTest: OSType = {
        var code = Array("{{AU_SUBTYPE}}".utf8)
        code[3] = code[3] == UInt8(ascii: "t") ? UInt8(ascii: "u") : UInt8(ascii: "t")
        return code.reduce(0) { $0 << 8 | OSType($1) }
    }()

    static let component: AudioComponent = {
        var description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                    componentSubType: subtypeUnderTest,
                                                    componentManufacturer: 0x4A50_6973,     // 'JPis'
                                                    componentFlags: 0, componentFlagsMask: 0)
        let factory = unsafeBitCast({{APP}}AUFactory as @convention(c) (UnsafePointer<AudioComponentDescription>?) -> UnsafeMutableRawPointer?,
                                    to: AudioComponentFactoryFunction.self)
        return AudioComponentRegister(&description, "{{APP}} under test" as CFString, 0, factory)
    }()
}

/// One instance of the unit, played the way a host plays it: initialised at a sample rate with
/// a number of output channels, rendered block after block. The plug-in window's tests use it too.
@MainActor
final class Instrument {

    let unit: AudioUnit
    let rate: Double
    let channels: Int
    /// Rendered blocks so far: a unit renders a point in time only once, so every block has a
    /// time of its own.
    private var blocks = 0
    static let frames = 256

    /// `initialised: false` leaves the unit as a host first gets it, before it sets a format.
    init(rate: Double = 48_000, channels: Int = 2, initialised: Bool = true) throws {
        var made: AudioUnit?
        try #require(AudioComponentInstanceNew(PlugIn.component, &made) == noErr)
        unit = try #require(made)
        self.rate = rate
        self.channels = channels
        if initialised { try initialise(rate: rate, channels: channels) }
    }

    isolated deinit {
        AudioComponentInstanceDispose(unit)
    }

    /// Sets the output format and initialises, as a host does before it plays.
    func initialise(rate: Double, channels: Int) throws {
        var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                                                 mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                 mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        try #require(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr)
        try #require(AudioUnitInitialize(unit) == noErr)
    }

    /// One block of every output channel. MIDI sent before it is played in it.
    func render() throws -> [[Float]] {
        let frames = UInt32(Self.frames)
        var flags = AudioUnitRenderActionFlags()
        var time = AudioTimeStamp()
        time.mFlags = .sampleTimeValid
        time.mSampleTime = Float64(blocks * Self.frames)
        blocks += 1
        let buffers = AudioBufferList.allocate(maximumBuffers: channels)     // the unit fills buffers of its own
        defer { free(buffers.unsafeMutablePointer) }
        for index in 0..<channels { buffers[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: nil) }
        try #require(AudioUnitRender(unit, &flags, &time, 0, frames, buffers.unsafeMutablePointer) == noErr)
        return (0..<channels).map { index in
            let data = buffers[index].mData!.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: data, count: Self.frames))
        }
    }

    /// Every channel of `seconds` of output, block after block.
    func render(seconds: Double) throws -> [[Float]] {
        var out = [[Float]](repeating: [], count: channels)
        for _ in 0..<Int((seconds * rate / Double(Self.frames)).rounded(.up)) {
            for (index, channel) in try render().enumerated() { out[index] += channel }
        }
        return out
    }

    func midi(_ status: UInt32, _ data1: UInt32, _ data2: UInt32) throws {
        try #require(MusicDeviceMIDIEvent(unit, status, data1, data2, 0) == noErr)
    }

    func setParameter(_ identifier: String, to value: Float) throws {
        let parameter = try #require(Parameters.named(identifier))
        try #require(AudioUnitSetParameter(unit, AudioUnitParameterID(parameter.index), kAudioUnitScope_Global, 0, value, 0) == noErr)
    }

    /// The unit's own value of a parameter, as a host reads it.
    func parameter(_ index: Int) throws -> Float {
        var value: AudioUnitParameterValue = 0
        try #require(AudioUnitGetParameter(unit, AudioUnitParameterID(index), kAudioUnitScope_Global, 0, &value) == noErr)
        return value
    }

    /// The engine behind the unit, as the plug-in's window gets it.
    func engine() throws -> OpaquePointer {
        var pointer: UnsafeMutableRawPointer?
        var size = UInt32(MemoryLayout<UnsafeMutableRawPointer?>.size)
        try #require(AudioUnitGetProperty(unit, AudioUnitPropertyID(k{{APP}}Property_Engine), kAudioUnitScope_Global, 0, &pointer, &size) == noErr)
        return OpaquePointer(try #require(pointer))
    }

    /// The unit's saved state, as a host saves it with a project.
    func classInfo() throws -> CFPropertyList {
        var state: Unmanaged<CFPropertyList>?
        var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &state, &size) == noErr)
        return try #require(state).takeRetainedValue()        // the unit hands its state over retained
    }

    func restore(_ state: CFPropertyList) throws {
        var saved = Unmanaged.passUnretained(state)
        try withExtendedLifetime(state) {
            try #require(AudioUnitSetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &saved,
                                              UInt32(MemoryLayout<Unmanaged<CFPropertyList>>.size)) == noErr)
        }
    }

    /// Chooses a factory preset (a program), as a host's preset menu does.
    func loadPreset(_ number: Int) throws {
        let name = Programs.names[number] as CFString
        var preset = AUPreset(presetNumber: Int32(number), presetName: Unmanaged.passUnretained(name))
        try withExtendedLifetime(name) {
            try #require(AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0,
                                              &preset, UInt32(MemoryLayout<AUPreset>.size)) == noErr)
        }
    }

    func float64Property(_ id: AudioUnitPropertyID) throws -> Float64 {
        var value: Float64 = -1
        var size = UInt32(MemoryLayout<Float64>.size)
        try #require(AudioUnitGetProperty(unit, id, kAudioUnitScope_Global, 0, &value, &size) == noErr)
        return value
    }

    /// The pad the window shows (0...15), as the unit keeps it for the window.
    func selectedPad() throws -> Int {
        var pad: UInt32 = 99
        var size = UInt32(MemoryLayout<UInt32>.size)
        try #require(AudioUnitGetProperty(unit, AudioUnitPropertyID(k{{APP}}Property_SelectedPad), kAudioUnitScope_Global, 0,
                                          &pad, &size) == noErr)
        return Int(pad)
    }

    @discardableResult
    func setSelectedPad(_ pad: UInt32) -> OSStatus {
        var value = pad
        return AudioUnitSetProperty(unit, AudioUnitPropertyID(k{{APP}}Property_SelectedPad), kAudioUnitScope_Global, 0,
                                    &value, UInt32(MemoryLayout<UInt32>.size))
    }

    /// The presets in use, as the unit keeps them for the window: the keyboard's, then pad 1...16's;
    /// "" for none.
    func presetNames() throws -> [String] {
        var names: Unmanaged<CFArray>?
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        try #require(AudioUnitGetProperty(unit, AudioUnitPropertyID(k{{APP}}Property_PresetNames), kAudioUnitScope_Global, 0,
                                          &names, &size) == noErr)
        let array = try #require(names).takeRetainedValue()                          // handed over retained
        return try #require(array as? [String])
    }

    @discardableResult
    func setPresetNames(_ names: CFArray) -> OSStatus {
        var value = Unmanaged.passUnretained(names)
        return withExtendedLifetime(names) {
            AudioUnitSetProperty(unit, AudioUnitPropertyID(k{{APP}}Property_PresetNames), kAudioUnitScope_Global, 0,
                                 &value, UInt32(MemoryLayout<Unmanaged<CFArray>>.size))
        }
    }
}

private func peak(_ samples: [Float]) -> Float {
    samples.reduce(0) { max($0, abs($1)) }
}

/// How many times a host's property listener was called. The unit calls it synchronously.
final class Calls {
    var count = 0
}

/// The values a host's parameter listener was told of, in order. The listener runs on its own queue.
private final class Told: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Float] = []

    func add(_ value: Float) { lock.withLock { values.append(value) } }
    var all: [Float] { lock.withLock { values } }
}

@Suite("The Audio Unit")
@MainActor
struct AudioUnitTests {

    // MARK: Parameters and programs

    @Test("The parameters are the keyboard set, grouped as the engine's sections")
    func parametersAreTheKeyboardSet() throws {
        let instrument = try Instrument()
        let unit = instrument.unit

        var size: UInt32 = 0
        try #require(AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &size, nil) == noErr)
        var ids = [AudioUnitParameterID](repeating: 0, count: Int(size) / MemoryLayout<AudioUnitParameterID>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &ids, &size) == noErr)
        #expect(Parameters.all.count == Int({{APP_C}}_num_params()))
        #expect(ids == (0..<Parameters.all.count).map { AudioUnitParameterID($0) })

        var sectionOf: [Int: Int] = [:]
        for (section, group) in ParameterSection.all.enumerated() {
            for parameter in group.parameters { sectionOf[parameter.index] = section }
        }
        for parameter in Parameters.all {
            var info = AudioUnitParameterInfo()
            var infoSize = UInt32(MemoryLayout<AudioUnitParameterInfo>.size)
            try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterInfo, kAudioUnitScope_Global,
                                              AudioUnitElement(parameter.index), &info, &infoSize) == noErr)
            let name = info.flags.contains(.flag_CFNameRelease) ? info.cfNameString?.takeRetainedValue() : info.cfNameString?.takeUnretainedValue()
            #expect(name as String? == parameter.name)
            #expect(info.minValue == parameter.range.lowerBound && info.maxValue == parameter.range.upperBound, "\(parameter.identifier)")
            #expect(info.defaultValue == parameter.defaultValue, "\(parameter.identifier)")
            #expect(info.flags.contains(.flag_IsReadable) && info.flags.contains(.flag_IsWritable))
            if let section = sectionOf[parameter.index] {
                #expect(info.flags.contains(.flag_HasClump) && info.clumpID == UInt32(section + 1), "\(parameter.identifier)")
            } else {
                #expect(!info.flags.contains(.flag_HasClump), "\(parameter.identifier) is in no section")
            }
            if case .choice(let choices) = parameter.kind {
                #expect(info.unit == .indexed)
                var strings: Unmanaged<CFArray>?
                var stringsSize = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
                try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterValueStrings, kAudioUnitScope_Global,
                                                  AudioUnitElement(parameter.index), &strings, &stringsSize) == noErr)
                #expect(try #require(strings).takeRetainedValue() as? [String] == choices)
            }
        }
        #expect(sectionOf.count == TestKnobs.all.count)

        for (section, group) in ParameterSection.all.enumerated() {
            var clump = AudioUnitParameterNameInfo(inID: AudioUnitParameterID(section + 1), inDesiredLength: Int32(kAudioUnitParameterName_Full), outName: nil)
            var clumpSize = UInt32(MemoryLayout<AudioUnitParameterNameInfo>.size)
            try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterClumpName, kAudioUnitScope_Global, 0, &clump, &clumpSize) == noErr)
            #expect(try #require(clump.outName).takeRetainedValue() as String == group.title)
        }
    }

    @Test("A note sent by the host sounds in both channels within 100 ms at 48 kHz")
    func noteRenders() throws {
        let instrument = try Instrument(rate: 48_000)
        try instrument.midi(0x90, 60, 100)
        let out = try instrument.render(seconds: 0.1)
        #expect(out.count == 2)
        #expect(peak(out[0]) > 0.01 && peak(out[1]) > 0.01)
    }

    @Test("A parameter the host sets reaches the engine's keyboard set by the next render")
    func hostParameterReachesEngine() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let volume = try #require(Parameters.named("volume"))
        try instrument.setParameter("volume", to: -20)
        _ = try instrument.render()
        #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(volume.index)) + 20) < 0.001)
        #expect({{APP_C}}_get_plain(engine, 1, Int32(volume.index)) != -20)       // a pad's set is not the unit's
    }

    @Test("A factory preset loads its program into the keyboard set and leaves the octave alone")
    func factoryPresetLoadsProgram() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let octave = try #require(Parameters.named("octave"))
        try instrument.setParameter("octave", to: 1)
        _ = try instrument.render()

        let other = TestKnobs.otherProgram
        try instrument.loadPreset(other)
        _ = try instrument.render()

        var present = AUPreset()
        var size = UInt32(MemoryLayout<AUPreset>.size)
        try #require(AudioUnitGetProperty(instrument.unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &present, &size) == noErr)
        present.presetName?.release()
        #expect(present.presetNumber == Int32(other))
        #expect({{APP_C}}_get_program(engine, Int32({{APP_UPPER}}_KEYBOARD_SET)) == Int32(other))
        for parameter in Parameters.all where parameter != octave {
            let value = Programs.value(program: other, parameter: parameter)
            #expect(try instrument.parameter(parameter.index) == value, "\(parameter.identifier)")
            #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(parameter.index)) - value) <= 0.001 * max(1, abs(value)),
                    "\(parameter.identifier)")
        }
        #expect(try instrument.parameter(octave.index) == 1)
        #expect({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(octave.index)) == 1)
    }

    @Test("A knob set back before the next render after a factory preset is what the engine plays")
    func factoryPresetThenRevert() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let knob = TestKnobs.programKnob, other = TestKnobs.otherProgram
        _ = try instrument.render()
        let before = try instrument.parameter(knob.index)
        try #require(Programs.value(program: other, parameter: knob) != before)

        try instrument.loadPreset(other)
        try instrument.setParameter(knob.identifier, to: before)   // automation, a reset or a click, within one buffer
        _ = try instrument.render()

        #expect(try instrument.parameter(knob.index) == before)
        #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(knob.index)) - before) <= 0.001 * max(1, abs(before)))
        #expect({{APP_C}}_get_program(engine, Int32({{APP_UPPER}}_KEYBOARD_SET)) == Int32(other))
    }

    // MARK: MIDI controllers

    /// A host's listener for one parameter's value. It runs on a queue of its own, so it is made
    /// outside the main actor.
    private nonisolated static func listen(to parameter: Parameter, of unit: AudioUnit, told: Told) throws -> AUParameterListenerRef {
        var listener: AUParameterListenerRef?
        try #require(AUListenerCreateWithDispatchQueue(&listener, 0, DispatchQueue(label: "host")) { _, _, value in
            told.add(value)
        } == noErr)
        let host = try #require(listener)
        var address = AudioUnitParameter(mAudioUnit: unit, mParameterID: AudioUnitParameterID(parameter.index),
                                         mScope: kAudioUnitScope_Global, mElement: 0)
        try #require(AUListenerAddParameter(host, nil, &address) == noErr)
        return host
    }

    @Test("A controller moves the engine's knob, and after the block the unit's parameter follows and the host is told")
    func controllerMirrorsToHost() async throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let tune = try #require(Parameters.named("tune"))
        #expect(Synth(borrowing: engine).controller(of: tune) == 102)
        let told = Told()
        let host = try Self.listen(to: tune, of: instrument.unit, told: told)
        defer { AUListenerDispose(host) }

        try instrument.midi(0xB0, 102, 127)
        _ = try instrument.render()
        let top = {{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(tune.index))
        #expect(abs(top - tune.range.upperBound) < 0.01)
        #expect(try instrument.parameter(tune.index) == top)               // what a host reads and saves
        for _ in 0..<200 where told.all.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(told.all == [top])

        try instrument.midi(0xB3, 102, 0)                                     // any channel
        _ = try instrument.render()
        let bottom = try instrument.parameter(tune.index)
        #expect(abs(bottom - tune.range.lowerBound) < 0.01)
        for _ in 0..<200 where told.all.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(told.all == [top, bottom])

        // The next block does not hand the old value back: the controller's stays.
        _ = try instrument.render()
        #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(tune.index)) - tune.range.lowerBound) < 0.01)
    }

    @Test("A knob the host has set stays there until its controller moves")
    func hostAndControllerTakeTurns() throws {
        let instrument = try Instrument()
        let tune = try #require(Parameters.named("tune"))
        try instrument.midi(0xB0, 102, 127)
        _ = try instrument.render()
        try instrument.setParameter("tune", to: 50)
        _ = try instrument.render()
        try instrument.midi(0xB0, 7, 64)                                     // another knob's controller
        _ = try instrument.render()
        #expect(try instrument.parameter(tune.index) == 50)
        #expect(abs(Synth(borrowing: try instrument.engine()).value(of: tune) - 50) < 0.01)

        try instrument.midi(0xB0, 102, 0)
        _ = try instrument.render()
        #expect(abs(try instrument.parameter(tune.index) - tune.range.lowerBound) < 0.01)
    }

    @Test("A host write and a controller on one knob before one block: the controller, played in the block, wins")
    func controllerWinsWithinTheBlock() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let tune = try #require(Parameters.named("tune"))
        try instrument.setParameter("tune", to: 50)
        try instrument.midi(0xB0, 102, 127)
        _ = try instrument.render()
        let top = {{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(tune.index))
        #expect(abs(top - tune.range.upperBound) < 0.01)
        #expect(try instrument.parameter(tune.index) == top)

        _ = try instrument.render()                                          // and the host's 50 is not handed back
        #expect(try instrument.parameter(tune.index) == top)
        #expect({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(tune.index)) == top)
    }

    // MARK: Saved state

    @Test("The saved state brings back the keyboard set, the pads and the mode")
    func stateRoundTrip() throws {
        let saved = try Instrument()
        let synth = Synth(borrowing: try saved.engine())
        let tune = try #require(Parameters.named("tune")), pan = try #require(Parameters.named("pan"))
        synth.loadProgram(TestKnobs.otherProgram, into: .pad(3))
        synth.setValue(75, of: tune, in: .pad(3))
        synth.setPadNote(60, pad: 3)
        synth.setPadGroup(7, pad: 3)
        synth.setPadGroup(nil, pad: 0)
        synth.mode = .pads
        try saved.setParameter("pan", to: 55)
        _ = try saved.render()
        let state = try saved.classInfo()

        let restored = try Instrument()
        let other = Synth(borrowing: try restored.engine())
        #expect(other.state != synth.state)
        try restored.restore(state)
        _ = try restored.render()

        #expect(try restored.parameter(pan.index) == 55)
        #expect(other.state == synth.state)
        #expect(other.mode == .pads && other.padNote(3) == 60 && other.padGroup(3) == 7 && other.padGroup(0) == nil)
        #expect(other.program(in: .pad(3)) == TestKnobs.otherProgram && abs(other.value(of: tune, in: .pad(3)) - 75) < 0.01)
    }

    @Test("A pad's shorter list of values covers the first parameters; the later ones stay at their defaults")
    func stateShorterValues() throws {
        let saved = try Instrument()
        let synth = Synth(borrowing: try saved.engine())
        let amount = try #require(Parameters.named("lfo1tune"))
        let knobs = TestKnobs.all.count
        #expect(amount.index >= knobs)
        synth.setValue(75, of: try #require(Parameters.named("tune")), in: .pad(3))
        synth.setValue(50, of: amount, in: .pad(3))
        let state = try #require(try saved.classInfo() as? [String: Any])

        // The state as a version with only the knobs saved it.
        var pads = try #require(state["{{APP_LOWER}}-pads"] as? [String: Any])
        var list = try #require(pads["pads"] as? [[String: Any]])
        #expect(list.count == 16)
        let values = try #require(list[3]["values"] as? Data)
        #expect(values.count == Parameters.all.count * MemoryLayout<Float32>.size)
        list[3]["values"] = values.prefix(knobs * MemoryLayout<Float32>.size)
        pads["pads"] = list
        var older = state
        older["{{APP_LOWER}}-pads"] = pads

        let restored = try Instrument()
        try restored.restore(older as CFDictionary)
        let other = Synth(borrowing: try restored.engine())
        // The engine keeps knobs as 0...1 positions: a plain value comes back a few ulps off.
        for parameter in Parameters.all {
            if parameter.index < knobs {
                let value = synth.value(of: parameter, in: .pad(3))
                #expect(abs(other.value(of: parameter, in: .pad(3)) - value) <= 1e-5 * max(1, abs(value)), "\(parameter.identifier)")
            } else {
                #expect(other.value(of: parameter, in: .pad(3)) == parameter.defaultValue, "\(parameter.identifier)")
            }
        }
    }

    @Test("A reopened project keeps the keyboard's program, so a reset goes to that program's value")
    func stateKeepsTheKeyboardProgram() throws {
        let saved = try Instrument()
        let program = TestKnobs.otherProgram, knob = TestKnobs.programKnob
        try saved.loadPreset(program)
        try saved.setParameter("pan", to: 55)
        _ = try saved.render()
        let state = try saved.classInfo()

        let restored = try Instrument()
        let other = Synth(borrowing: try restored.engine())
        try restored.restore(state)
        _ = try restored.render()
        let pan = try #require(Parameters.named("pan"))
        #expect(other.program(in: .keyboard) == program)
        #expect(try restored.parameter(pan.index) == 55)       // the values are the project's, not the program's
        #expect(abs(other.value(of: pan, in: .keyboard) - 55) < 0.001)
        #expect(Programs.value(program: other.program(in: .keyboard), parameter: knob) != Programs.value(program: 0, parameter: knob))

        // A state without the key leaves the index alone.
        var older = try #require(state as? [String: Any])
        var pads = try #require(older["{{APP_LOWER}}-pads"] as? [String: Any])
        #expect(pads["keyboardProgram"] as? Int == program)
        pads["keyboardProgram"] = nil
        older["{{APP_LOWER}}-pads"] = pads
        let another = try Instrument()
        try another.loadPreset(program)
        try another.restore(older as CFDictionary)
        #expect({{APP_C}}_get_program(try another.engine(), Int32({{APP_UPPER}}_KEYBOARD_SET)) == Int32(program))
    }

    @Test("Saved state of the wrong shape is ignored, part by part")
    func stateOfTheWrongShape() throws {
        let saved = try Instrument()
        let state = try #require(try saved.classInfo() as? [String: Any])
        let restored = try Instrument()
        let synth = Synth(borrowing: try restored.engine())
        let before = synth.state

        var pads = try #require(state["{{APP_LOWER}}-pads"] as? [String: Any])
        var list = try #require(pads["pads"] as? [Any])
        list[0] = 42                                                        // not a pad
        list[1] = ["note": "C3", "group": 2.5, "program": [1], "values": "loud"] as [String: Any]
        list[2] = ["values": Data([0x01, 0x02, 0x03])] as [String: Any]     // shorter than one value
        list.append(["note": 70] as [String: Any])                          // a 17th pad
        pads["pads"] = list
        pads["mode"] = "pads"
        pads["keyboardProgram"] = Data([3])
        var wrong = state
        wrong["{{APP_LOWER}}-pads"] = pads
        try restored.restore(wrong as CFDictionary)
        #expect(synth.state == before)

        for shape: Any in [7, "pads", [1, 2]] {
            wrong["{{APP_LOWER}}-pads"] = shape
            try restored.restore(wrong as CFDictionary)
        }
        pads["pads"] = ["pad": 1]
        wrong["{{APP_LOWER}}-pads"] = pads
        try restored.restore(wrong as CFDictionary)
        #expect(synth.state == before)
    }

    @Test("The saved state brings back the controllers, the selected pad and the presets in use, but not a learn")
    func stateKeepsControllersAndSelection() throws {
        let saved = try Instrument()
        let synth = Synth(borrowing: try saved.engine())
        let tune = try #require(Parameters.named("tune")), volume = try #require(Parameters.named("volume"))
        let pan = try #require(Parameters.named("pan"))
        let free = TestKnobs.freeControllers
        synth.setController(free[0], of: tune)
        synth.setController(nil, of: volume)
        #expect(saved.setSelectedPad(5) == noErr)
        var names = [String](repeating: "", count: 17)
        names[0] = "Warm"
        names[2] = "Kick"
        names[16] = "Last pad"
        #expect(saved.setPresetNames(names as CFArray) == noErr)
        synth.learn(pan)                                                    // listening when the project is saved
        let state = try saved.classInfo()

        let dictionary = try #require(state as? [String: Any])
        #expect(dictionary.keys.filter { $0.hasPrefix("{{APP_LOWER}}-") }.sorted() == ["{{APP_LOWER}}-controllers", "{{APP_LOWER}}-pads"])
        let controllers = try #require(dictionary["{{APP_LOWER}}-controllers"] as? Data)
        #expect(controllers.count == TestKnobs.all.count * MemoryLayout<Int32>.size)
        let pads = try #require(dictionary["{{APP_LOWER}}-pads"] as? [String: Any])
        #expect(Set(pads.keys) == ["mode", "keyboardProgram", "selectedPad", "keyboardPreset", "pads"])      // nothing of the learn
        #expect(pads["selectedPad"] as? Int == 5)
        #expect(pads["keyboardPreset"] as? String == "Warm")
        let list = try #require(pads["pads"] as? [[String: Any]])
        #expect(list.map { $0["preset"] as? String } == names.dropFirst().map { Optional($0) })

        let restored = try Instrument()
        let other = Synth(borrowing: try restored.engine())
        try restored.restore(state)
        for parameter in Parameters.all {
            #expect(other.controller(of: parameter) == synth.controller(of: parameter), "\(parameter.identifier)")
        }
        #expect(other.controller(of: tune) == free[0] && other.controller(of: volume) == nil)
        #expect(other.learning == nil)
        #expect(try restored.selectedPad() == 5)
        #expect(try restored.presetNames() == names)
    }

    @Test("Saved controllers are checked one by one; a shorter list covers the first knobs")
    func stateControllersAreChecked() throws {
        let instrument = try Instrument()
        let synth = Synth(borrowing: try instrument.engine())
        var state = try #require(try instrument.classInfo() as? [String: Any])
        let knobs = TestKnobs.all, last = knobs.count - 1, free = TestKnobs.freeControllers.map(Int32.init)
        // The first knob a free controller, the second one out of range, the third the sustain
        // pedal (reserved), the fourth below zero, the fifth none, the sixth another free one; the
        // knobs after the sixth are not in the list.
        let saved: [Int32] = [free[0], 300, 64, -7, -1, free[1]]
        state["{{APP_LOWER}}-controllers"] = saved.withUnsafeBufferPointer { Data(buffer: $0) }
        synth.setController(Int(free[2]), of: knobs[last])
        try instrument.restore(state as CFDictionary)

        #expect(synth.controller(of: knobs[0]) == Int(free[0]))
        for index in 1...4 { #expect(synth.controller(of: knobs[index]) == nil, "\(knobs[index].identifier)") }
        #expect(synth.controller(of: knobs[5]) == Int(free[1]))
        #expect(synth.controller(of: knobs[last]) == Int(free[2]))            // after the list: left alone
        for knob in knobs.dropFirst(6) where knob.index != last {
            #expect(synth.controller(of: knob) == Controllers.standard(for: knob), "\(knob.identifier)")
        }

        // The wrong type, or a list too short for one value, leaves them all alone.
        for wrong: Any in ["40", [40, 41], Data([1, 2, 3])] {
            state["{{APP_LOWER}}-controllers"] = wrong
            try instrument.restore(state as CFDictionary)
            #expect(synth.controller(of: knobs[0]) == Int(free[0]) && synth.controller(of: knobs[last]) == Int(free[2]))
        }
    }

    @Test("A project saved before controllers, pad selection and presets keeps the standard controllers and pad 01")
    func olderStateKeepsDefaults() throws {
        let saved = try Instrument()
        let free = TestKnobs.freeControllers[0]
        Synth(borrowing: try saved.engine()).setController(free, of: try #require(Parameters.named("tune")))
        saved.setSelectedPad(9)
        var names = [String](repeating: "Old", count: 17)
        saved.setPresetNames(names as CFArray)
        var older = try #require(try saved.classInfo() as? [String: Any])
        older["{{APP_LOWER}}-controllers"] = nil
        var pads = try #require(older["{{APP_LOWER}}-pads"] as? [String: Any])
        pads["selectedPad"] = nil
        pads["keyboardPreset"] = nil
        pads["pads"] = try #require(pads["pads"] as? [[String: Any]]).map { pad in
            var pad = pad
            pad["preset"] = nil
            return pad
        }
        older["{{APP_LOWER}}-pads"] = pads

        let restored = try Instrument()
        let synth = Synth(borrowing: try restored.engine())
        try restored.restore(older as CFDictionary)
        for parameter in Parameters.all {
            #expect(synth.controller(of: parameter) == Controllers.standard(for: parameter), "\(parameter.identifier)")
        }
        #expect(try restored.selectedPad() == 0)
        #expect(try restored.presetNames() == [String](repeating: "", count: 17))

        // Restored over an instance that has its own: the controllers and the pad stay; the sets
        // that came from the project lose the names of the presets they no longer hold.
        try saved.restore(older as CFDictionary)
        #expect(Synth(borrowing: try saved.engine()).controller(of: try #require(Parameters.named("tune"))) == free)
        #expect(try saved.selectedPad() == 9)
        names = [String](repeating: "", count: 17)
        #expect(try saved.presetNames() == names)

        // Names of the wrong type count as none; a pad the state has no entry for keeps its name.
        saved.setPresetNames([String](repeating: "Old", count: 17) as CFArray)
        var wrong = try #require(try saved.classInfo() as? [String: Any])
        var wrongPads = try #require(wrong["{{APP_LOWER}}-pads"] as? [String: Any])
        wrongPads["keyboardPreset"] = 7
        var list = try #require(wrongPads["pads"] as? [[String: Any]])
        list[0]["preset"] = ["Old"]
        list.removeLast()
        wrongPads["pads"] = list
        wrongPads["selectedPad"] = 16
        wrong["{{APP_LOWER}}-pads"] = wrongPads
        try saved.restore(wrong as CFDictionary)
        #expect(try saved.presetNames() == ["", ""] + [String](repeating: "Old", count: 15))
        #expect(try saved.selectedPad() == 9)
    }

    @Test("The selected pad is a pad: anything else is refused")
    func selectedPadIsAPad() throws {
        let instrument = try Instrument()
        #expect(try instrument.selectedPad() == 0)
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        try #require(AudioUnitGetPropertyInfo(instrument.unit, AudioUnitPropertyID(k{{APP}}Property_SelectedPad), kAudioUnitScope_Global, 0,
                                              &size, &writable) == noErr)
        #expect(size == UInt32(MemoryLayout<UInt32>.size) && writable.boolValue)
        #expect(instrument.setSelectedPad(15) == noErr)
        #expect(try instrument.selectedPad() == 15)
        #expect(instrument.setSelectedPad(16) == kAudioUnitErr_InvalidPropertyValue)
        var short: UInt16 = 3
        #expect(AudioUnitSetProperty(instrument.unit, AudioUnitPropertyID(k{{APP}}Property_SelectedPad), kAudioUnitScope_Global, 0,
                                     &short, UInt32(MemoryLayout<UInt16>.size)) == kAudioUnitErr_InvalidPropertyValue)
        #expect(try instrument.selectedPad() == 15)
    }

    @Test("The presets in use are seventeen names: anything else is refused, and the unit keeps a copy")
    func presetNamesAreSeventeen() throws {
        let instrument = try Instrument()
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        try #require(AudioUnitGetPropertyInfo(instrument.unit, AudioUnitPropertyID(k{{APP}}Property_PresetNames), kAudioUnitScope_Global, 0,
                                              &size, &writable) == noErr)
        #expect(size == UInt32(MemoryLayout<UnsafeRawPointer>.size) && writable.boolValue)
        #expect(try instrument.presetNames() == [String](repeating: "", count: 17))
        let names = NSMutableArray(array: [String](repeating: "", count: 17))
        let first = NSMutableString(string: "Warm")
        names[0] = first
        #expect(instrument.setPresetNames(names) == noErr)
        first.append(" and changed")                                         // the caller's string, not the unit's
        #expect(try instrument.presetNames().first == "Warm")

        #expect(instrument.setPresetNames([String](repeating: "", count: 16) as CFArray) == kAudioUnitErr_InvalidPropertyValue)
        #expect(instrument.setPresetNames(([String](repeating: "", count: 16) as [Any] + [3]) as CFArray) == kAudioUnitErr_InvalidPropertyValue)
        var notAnArray = Unmanaged.passUnretained("Warm" as CFString)
        #expect(AudioUnitSetProperty(instrument.unit, AudioUnitPropertyID(k{{APP}}Property_PresetNames), kAudioUnitScope_Global, 0,
                                     &notAnArray, UInt32(MemoryLayout<Unmanaged<CFString>>.size)) == kAudioUnitErr_InvalidPropertyValue)
        #expect(try instrument.presetNames().first == "Warm")
    }

    @Test("A host saving the project on its own thread while the window sets the presets in use reads whole lists")
    func presetNamesWhileSaving() async throws {
        let instrument = try Instrument()
        nonisolated(unsafe) let unit = instrument.unit
        let saving = Task.detached {
            var whole = true
            for _ in 0..<200 {
                var state: Unmanaged<CFPropertyList>?
                var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
                guard AudioUnitGetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &state, &size) == noErr,
                      let saved = state?.takeRetainedValue() as? [String: Any],
                      let pads = saved["{{APP_LOWER}}-pads"] as? [String: Any],
                      let keyboard = pads["keyboardPreset"] as? String,
                      let list = pads["pads"] as? [[String: Any]] else { return false }
                whole = whole && list.allSatisfy { $0["preset"] as? String == keyboard }    // one list, never a mix
            }
            return whole
        }
        for round in 0..<200 {
            instrument.setPresetNames([String](repeating: "Round \(round)", count: 17) as CFArray)
        }
        #expect(await saving.value)
    }

    @Test("A preset name longer than a preset's can be (60 characters) counts as none, from the window or from a project")
    func presetNamesAreCapped() throws {
        let instrument = try Instrument()
        let longest = String(repeating: "e\u{301}", count: 60)              // 60 characters, 120 UTF-16 units
        let tooLong = String(repeating: "a", count: 61)
        #expect(longest.count == PresetLibrary.longestName)
        var names = [String](repeating: "", count: 17)
        names[0] = longest
        names[1] = tooLong
        names[2] = "Kick"
        #expect(instrument.setPresetNames(names as CFArray) == noErr)
        #expect(try instrument.presetNames() == [longest, "", "Kick"] + [String](repeating: "", count: 14))

        var state = try #require(try instrument.classInfo() as? [String: Any])
        var pads = try #require(state["{{APP_LOWER}}-pads"] as? [String: Any])
        pads["keyboardPreset"] = tooLong
        var list = try #require(pads["pads"] as? [[String: Any]])
        list[1]["preset"] = String(repeating: "b", count: 10_000)
        list[2]["preset"] = longest
        pads["pads"] = list
        state["{{APP_LOWER}}-pads"] = pads
        try instrument.restore(state as CFDictionary)
        #expect(try instrument.presetNames() == ["", "", "", longest] + [String](repeating: "", count: 13))
    }

    @Test("Telling the unit its pads changed tells the host its saved state changed")
    func stateChangedTellsTheHost() throws {
        let instrument = try Instrument()
        let calls = Calls()
        let listener: AudioUnitPropertyListenerProc = { refCon, _, id, scope, _ in
            guard id == kAudioUnitProperty_ClassInfo, scope == kAudioUnitScope_Global else { return }
            Unmanaged<Calls>.fromOpaque(refCon).takeUnretainedValue().count += 1
        }
        let refCon = Unmanaged.passUnretained(calls).toOpaque()
        try #require(AudioUnitAddPropertyListener(instrument.unit, kAudioUnitProperty_ClassInfo, listener, refCon) == noErr)
        defer { AudioUnitRemovePropertyListenerWithUserData(instrument.unit, kAudioUnitProperty_ClassInfo, listener, refCon) }

        var any: UInt32 = 1
        try #require(AudioUnitSetProperty(instrument.unit, AudioUnitPropertyID(k{{APP}}Property_StateChanged), kAudioUnitScope_Global, 0,
                                          &any, UInt32(MemoryLayout<UInt32>.size)) == noErr)
        #expect(calls.count == 1)
    }

    // MARK: Latency, tail and output

    @Test("The latency follows the sample rate: 29 frames below 88.2 kHz, none above")
    func latencyFollowsRate() throws {
        let instrument = try Instrument(rate: 44_100)
        #expect(abs(try instrument.float64Property(kAudioUnitProperty_Latency) - 29.0 / 44_100) < 1e-12)
        for (rate, latency) in [(48_000.0, 29.0 / 48_000), (96_000, 0), (44_100, 29.0 / 44_100)] {
            try #require(AudioUnitUninitialize(instrument.unit) == noErr)
            try instrument.initialise(rate: rate, channels: 2)
            #expect(abs(try instrument.float64Property(kAudioUnitProperty_Latency) - latency) < 1e-12, "\(rate) Hz")
        }
    }

    @Test("A host hears when Initialize changes the latency, and the latency is right before the first Initialize")
    func latencyAnnounced() throws {
        let instrument = try Instrument(rate: 48_000, initialised: false)
        #expect(abs(try instrument.float64Property(kAudioUnitProperty_Latency) - 29.0 / 44_100) < 1e-12)     // the engine starts at 44.1 kHz

        let calls = Calls()
        let listener: AudioUnitPropertyListenerProc = { refCon, _, id, scope, _ in
            guard id == kAudioUnitProperty_Latency, scope == kAudioUnitScope_Global else { return }
            Unmanaged<Calls>.fromOpaque(refCon).takeUnretainedValue().count += 1
        }
        let refCon = Unmanaged.passUnretained(calls).toOpaque()
        try #require(AudioUnitAddPropertyListener(instrument.unit, kAudioUnitProperty_Latency, listener, refCon) == noErr)
        defer { AudioUnitRemovePropertyListenerWithUserData(instrument.unit, kAudioUnitProperty_Latency, listener, refCon) }

        for (step, (rate, heard)) in [(48_000.0, 1), (48_000, 1), (96_000, 2), (192_000, 2), (44_100, 3)].enumerated() {
            if step > 0 { try #require(AudioUnitUninitialize(instrument.unit) == noErr) }
            try instrument.initialise(rate: rate, channels: 2)
            #expect(calls.count == heard, "\(rate) Hz")
        }
        #expect(abs(try instrument.float64Property(kAudioUnitProperty_Latency) - 29.0 / 44_100) < 1e-12)
    }

    // The longest a voice can sound once its key is let go, as the instrument says.
    @Test("The tail is the engine's tail time")
    func tailIsTheEngines() throws {
        let instrument = try Instrument()
        #expect({{APP_C}}_tail_time() > 0)
        #expect(abs(try instrument.float64Property(kAudioUnitProperty_TailTime) - {{APP_C}}_tail_time()) < 1e-9)
    }

    @Test("A mono output gets both sides mixed: (L+R)/2, so a pad panned right is heard")
    func monoBusMixesBothSides() throws {
        let stereo = try Instrument(rate: 48_000, channels: 2), mono = try Instrument(rate: 48_000, channels: 1)
        let pan = try #require(Parameters.named("pan"))
        for instrument in [stereo, mono] {
            let synth = Synth(borrowing: try instrument.engine())
            synth.mode = .pads
            synth.setValue(100, of: pan, in: .pad(0))
            try instrument.midi(0x90, 36, 100)
        }
        let both = try stereo.render(seconds: 0.1), one = try mono.render(seconds: 0.1)
        #expect(one.count == 1)
        #expect(peak(both[0]) < 1e-6 && peak(both[1]) > 0.01)      // hard right
        #expect(peak(one[0]) > 0.005)
        #expect(zip(one[0], zip(both[0], both[1])).allSatisfy { abs($0 - ($1.0 + $1.1) / 2) < 1e-6 })
    }

    // MARK: The engine property and reset

    @Test("The engine property gives the engine the unit plays")
    func enginePropertyGivesTheEngine() throws {
        let instrument = try Instrument()
        var size: UInt32 = 0
        var writable: DarwinBoolean = true
        try #require(AudioUnitGetPropertyInfo(instrument.unit, AudioUnitPropertyID(k{{APP}}Property_Engine), kAudioUnitScope_Global, 0,
                                              &size, &writable) == noErr)
        #expect(size == UInt32(MemoryLayout<UnsafeRawPointer>.size) && !writable.boolValue)

        let engine = try instrument.engine()
        let tune = try #require(Parameters.named("tune"))
        try instrument.setParameter("tune", to: 60)
        _ = try instrument.render()
        #expect(abs({{APP_C}}_get_plain(engine, Int32({{APP_UPPER}}_KEYBOARD_SET), Int32(tune.index)) - 60) < 0.01)
        #expect(try Instrument().engine() != engine)
    }

    @Test("Reset between renders silences the unit at its next render")
    func resetIsDeferred() throws {
        let instrument = try Instrument()
        try instrument.midi(0x90, 60, 100)
        #expect(peak(try instrument.render(seconds: 0.05)[0]) > 0.01)
        try #require(AudioUnitReset(instrument.unit, kAudioUnitScope_Global, 0) == noErr)
        let after = try instrument.render()
        #expect(peak(after[0]) == 0 && peak(after[1]) == 0)
        #expect({{APP_C}}_sounding_voices(try instrument.engine()) == 0)
    }
}
