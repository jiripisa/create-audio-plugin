import Foundation
import Testing
import {{APP}}Reference
@testable import {{APP}}Core

/// One note of a prototype score: `time` seconds in, held `hold` seconds (nil: never let go).
struct SpikeNote: Sendable {
    let time: Double
    let note: UInt8
    let accent: Float
    var hold: Double? = nil
}

/// What a player does besides the notes: the sustain pedal, or the pitch bend at -1 ... +1.
struct SpikeControl: Sendable {
    enum Kind: Sendable { case pedal(down: Bool), bend(Double) }
    let time: Double
    let kind: Kind
}

/// One of the prototype's renders: a sound (program and knobs, engine identifiers and plain
/// engine values; the playing style is knobs too: Voice Mode, Glide, the bend range), its notes
/// and controls, on the keyboard or, with `pads`, on the default kit's pads (note 36 + pad, each
/// pad at its own pitch).
struct SpikeRender: Sendable, CustomTestStringConvertible {
    let name: String
    var program: Int32 = 0
    var knobs: [String: Float] = [:]
    var pads = false
    let notes: [SpikeNote]
    var controls: [SpikeControl] = []

    var testDescription: String { name }

    /// Seconds: the last note or control and 2.5 s, enough for the default Release to end.
    var seconds: Double { ((notes.map { $0.time + ($0.hold ?? 0) } + controls.map(\.time)).max() ?? 0) + 2.5 }

    /// What the reference plays: the program's values, and the knobs over them.
    var reference: [String: Float] {
        (PrototypeScores.programs[Int(program)] ?? [:]).merging(knobs) { $1 }
    }
}

/// One MIDI event of a score at a whole frame: a note-on or a note-off of `note`, sounding
/// `key`'s voice (the note on the keyboard, the pad on the pads) at `pitch`, the sustain pedal,
/// or the pitch bend as its 14 bits (-8192 ... 8191).
struct ScoreEvent {
    enum Kind { case noteOn, noteOff, pedal(down: Bool), bend(Int) }
    let frame: Int
    let kind: Kind
    var key = 0
    var note: UInt8 = 0
    var pitch: UInt8 = 0
    var velocity: UInt8 = 0

    /// The event as MIDI: status and two data bytes.
    var midi: (status: UInt8, data1: UInt8, data2: UInt8) {
        switch kind {
        case .noteOn: (0x90, note, velocity)
        case .noteOff: (0x80, note, 0)
        case .pedal(let down): (0xB0, 64, down ? 127 : 0)
        case .bend(let value): (0xE0, UInt8((value + 8192) & 0x7F), UInt8((value + 8192) >> 7))
        }
    }
}

/// The prototype's scores and renders, and a way to render them through the reference (the
/// prototype itself). Shared by the tests that compare the engine with it, the regression
/// references and the listening renders.
enum PrototypeScores {

    /// The engine's output scale against the prototype's units (`kOutputLevel` in Params.h).
    static let level = 0.125

    static func velocity(_ accent: Float) -> UInt8 {
        UInt8((accent * 127).rounded())
    }

    /// A note's pitch, as the engine works it out (exp2, not pow: see Voice.h).
    static func noteHz(_ note: UInt8) -> Double {
        440.0 * exp2((Double(note) - 69.0) / 12.0)
    }

    // MARK: - The prototype's programs and scores

    /// The programs as the prototype sets them, by index, in engine identifiers and values.
    static let programs: [Int: [String: Float]] = [
        0: [:],
        1: ["attack": 40, "decay": 4, "release": 0.8, "brightness": 5],
    ]

    /// A melody of quarter notes at 100 BPM, each held for most of its beat (or for `hold`
    /// seconds: longer than the beat, each note overlaps the next).
    static func melody(_ notes: [UInt8], from start: Double = 0.2, beat: Double = 0.6, hold: Double? = nil) -> [SpikeNote] {
        notes.enumerated().map { SpikeNote(time: start + Double($0.offset) * beat, note: $0.element,
                                           accent: $0.offset % 2 == 0 ? 0.9 : 0.6, hold: hold ?? beat * 0.8) }
    }

    /// Chords: every note of each chord at once, held for `hold`.
    static func chords(_ chords: [[UInt8]], from start: Double = 0.2, every gap: Double = 1.0, hold: Double = 0.8) -> [SpikeNote] {
        chords.enumerated().flatMap { index, chord in
            chord.map { SpikeNote(time: start + Double(index) * gap, note: $0, accent: 0.8, hold: hold) }
        }
    }

    static let renders: [SpikeRender] = [
        SpikeRender(name: "01_tone_melody", notes: melody([60, 62, 64, 65, 67, 65, 64, 62, 60])),
        SpikeRender(name: "02_soft_tone_chords", program: 1, notes: chords([[48, 55, 64], [53, 57, 65], [55, 59, 67], [48, 52, 60]])),
        SpikeRender(name: "03_bright_repeated_notes", knobs: ["brightness": 100, "decay": 0.5],
                    notes: (0..<12).map { (i: Int) -> SpikeNote in SpikeNote(time: 0.2 + Double(i) * 0.15, note: 57, accent: i % 3 == 0 ? 1 : 0.5) }),
        SpikeRender(name: "04_held_low_notes", knobs: ["attack": 300, "release": 1.5],
                    notes: [SpikeNote(time: 0.2, note: 36, accent: 1, hold: 1.5), SpikeNote(time: 0.9, note: 43, accent: 0.7, hold: 1.2)]),
        SpikeRender(name: "05_default_kit", pads: true, notes: kitHits),
        // How it plays: the platform's voice modes, glide, pedal and bend, as the harness plays them.
        // Legato: every note overlaps the next, which goes on without a new attack and glides;
        // the last one is played after a gap and attacks.
        SpikeRender(name: "06_legato_glide", knobs: ["voicemode": 2, "glide": 80, "decay": 8],
                    notes: melody([60, 67, 64, 72, 60], hold: 0.75) + [SpikeNote(time: 3.6, note: 65, accent: 0.8, hold: 0.4)]),
        // Mono: a low key held while others are played over it and let go: every note attacks
        // anew and glides, every key let go returns to the one still held; the third note cuts
        // the glide of the second short.
        SpikeRender(name: "07_mono_glide_returns", knobs: ["voicemode": 1, "glide": 150],
                    notes: [SpikeNote(time: 0.2, note: 48, accent: 0.9, hold: 2.6), SpikeNote(time: 0.7, note: 60, accent: 0.7, hold: 0.4),
                            SpikeNote(time: 1.5, note: 55, accent: 0.8, hold: 0.9), SpikeNote(time: 1.56, note: 67, accent: 0.6, hold: 0.5)]),
        // The pedal holds short chords, comes up between them, and is still down when a key is
        // struck again.
        SpikeRender(name: "08_sustain_pedal",
                    notes: chords([[48, 55, 64], [53, 57, 65], [53, 60, 69]], every: 0.9, hold: 0.15),
                    controls: [SpikeControl(time: 0.1, kind: .pedal(down: true)), SpikeControl(time: 1.0, kind: .pedal(down: false)),
                               SpikeControl(time: 1.05, kind: .pedal(down: true)), SpikeControl(time: 2.9, kind: .pedal(down: false))]),
        // A held note bent up to the top (Bend Up 7), down to the bottom (Bend Down 12) and let
        // go, while a second note is played under the bend.
        SpikeRender(name: "09_pitch_bend", knobs: ["bendup": 7, "benddown": 12, "decay": 8],
                    notes: [SpikeNote(time: 0.2, note: 57, accent: 0.9, hold: 2.6), SpikeNote(time: 1.3, note: 64, accent: 0.7, hold: 0.6)],
                    controls: bendSlide(from: 0, to: 1, between: 0.5, and: 1.0) + bendSlide(from: 1, to: -1, between: 1.4, and: 2.0)
                        + [SpikeControl(time: 2.4, kind: .bend(0))]),
    ]

    /// The pitch bend moved evenly from one place to another, a message every 10 ms.
    static func bendSlide(from: Double, to: Double, between start: Double, and end: Double) -> [SpikeControl] {
        let steps = Int(((end - start) / 0.01).rounded())
        return (0...steps).map { SpikeControl(time: start + (end - start) * Double($0) / Double(steps),
                                               kind: .bend(from + (to - from) * Double($0) / Double(steps))) }
    }

    /// Every pad of the default kit once, then pad 1 twice in quick succession: a re-hit on a
    /// sounding voice.
    private static var kitHits: [SpikeNote] {
        var notes: [SpikeNote] = []
        for pad in 0..<16 {
            notes.append(SpikeNote(time: 0.2 + Double(pad) * 0.2, note: UInt8(36 + pad), accent: 0.5 + Float(pad % 4) * 0.15))
        }
        notes.append(SpikeNote(time: 3.6, note: 36, accent: 1))
        notes.append(SpikeNote(time: 3.65, note: 36, accent: 0.6))
        return notes
    }

    static func render(named name: String) -> SpikeRender {
        guard let render = renders.first(where: { $0.name == name }) else { preconditionFailure("no prototype render \(name)") }
        return render
    }

    /// The pitch bend as MIDI carries it: 14 bits, -8192 ... 8191.
    static func bend14(_ amount: Double) -> Int {
        min(8191, max(-8192, Int((amount * (amount >= 0 ? 8191 : 8192)).rounded())))
    }

    /// A render's notes and controls as events at `rate`, in time order; on the same frame the
    /// controls first, then the notes in the score's order, a note's end before a later note's
    /// start. On the pads, a note's key is its pad and its pitch the pad's note in the default
    /// kit (`pitchOfPad`).
    static func events(_ render: SpikeRender, rate: Double, pitchOfPad: (Int) -> UInt8 = { UInt8(36 + $0) }) -> [ScoreEvent] {
        var events: [(order: Int, event: ScoreEvent)] = []
        for (order, c) in render.controls.enumerated() {
            let frame = Int((c.time * rate).rounded())
            switch c.kind {
            case .pedal(let down): events.append((order - render.controls.count, ScoreEvent(frame: frame, kind: .pedal(down: down))))
            case .bend(let amount): events.append((order - render.controls.count, ScoreEvent(frame: frame, kind: .bend(bend14(amount)))))
            }
        }
        for (order, n) in render.notes.enumerated() {
            let key = render.pads ? Int(n.note) - 36 : Int(n.note)
            let pitch = render.pads ? pitchOfPad(key) : n.note
            let on = Int((n.time * rate).rounded())
            events.append((2 * order, ScoreEvent(frame: on, kind: .noteOn, key: key, note: n.note, pitch: pitch,
                                                 velocity: velocity(n.accent))))
            if let hold = n.hold {
                events.append((2 * order + 1, ScoreEvent(frame: Int(((n.time + hold) * rate).rounded()), kind: .noteOff, key: key,
                                                         note: n.note, pitch: pitch)))
            }
        }
        return events.sorted { ($0.event.frame, $0.order) < ($1.event.frame, $1.order) }.map(\.event)
    }

    static func frames(_ render: SpikeRender, rate: Double) -> Int { Int(render.seconds * rate) }

    /// A render's notes and controls as timed MIDI for a `Synth`.
    static func midiEvents(_ render: SpikeRender) -> [GrooveEvent] {
        var events: [(Double, Int, GrooveEvent)] = []
        for (order, c) in render.controls.enumerated() {
            switch c.kind {
            case .pedal(let down): events.append((c.time, order - render.controls.count, GrooveEvent(c.time, 0xB0, 64, down ? 127 : 0)))
            case .bend(let amount):
                let value = bend14(amount) + 8192
                events.append((c.time, order - render.controls.count, GrooveEvent(c.time, 0xE0, UInt8(value & 0x7F), UInt8(value >> 7))))
            }
        }
        for (order, n) in render.notes.enumerated() {
            events.append((n.time, 2 * order, GrooveEvent(n.time, 0x90, n.note, velocity(n.accent))))
            if let hold = n.hold { events.append((n.time + hold, 2 * order + 1, GrooveEvent(n.time + hold, 0x80, n.note, 0))) }
        }
        return events.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    /// Puts a render's sound into `synth`: into the keyboard set, or into every pad's set over
    /// the default kit.
    static func setUp(_ render: SpikeRender, in synth: Synth) {
        let sets: [SoundSet] = render.pads ? (0..<16).map { .pad($0) } : [.keyboard]
        for set in sets {
            synth.loadProgram(Int(render.program), into: set)
            for (id, value) in render.knobs { synth.setValue(value, of: Parameters.named(id)!, in: set) }
        }
    }

    /// The prototype's parameters for a sound given as engine knobs: the engine's defaults with
    /// `overrides` applied (identifiers and plain engine values), each value as the engine holds
    /// it (a knob stores its position, and a position gives the value back to within a
    /// rounding). Percent knobs become fractions.
    static func referenceParams(_ overrides: [String: Float]) -> {{APP}}RefParams {
        func value(_ id: String) -> Float {
            let knob = Parameters.named(id)!
            return knob.plain(knob.normalised(overrides[id] ?? knob.defaultValue))
        }
        return {{APP}}RefParams(attack: value("attack"), decay: value("decay"), release: value("release"),
                                brightness: value("brightness") / 100, velsens: value("velsens") / 100)
    }

    /// The prototype's playing style for a sound given as engine knobs: Voice Mode, Glide and the
    /// bend range as the engine holds them (the platform's defaults where `overrides` names
    /// none), on the keyboard or on the pads.
    static func referencePlaying(_ overrides: [String: Float], pads: Bool = false) -> {{APP}}RefPlaying {
        func value(_ id: String) -> Float {
            let knob = Parameters.named(id)!
            return knob.plain(knob.normalised(overrides[id] ?? knob.defaultValue))
        }
        return {{APP}}RefPlaying(mode: Int32(value("voicemode").rounded()), glideMs: value("glide"),
                                 bendUp: Int32(value("bendup").rounded()), bendDown: Int32(value("benddown").rounded()),
                                 pads: pads ? 1 : 0)
    }

    /// Renders `events` through the reference (the prototype's voice, played by its harness) at
    /// `rate`. With `oversampled` the voices run at twice `rate` and the engine's decimator
    /// brings them back. `paramsOf` picks a note's entry of `params` (by default the first).
    static func referenceRender(_ events: [ScoreEvent], frames: Int, params: [{{APP}}RefParams],
                                playing: {{APP}}RefPlaying = referencePlaying([:]), rate: Double, oversampled: Bool,
                                paramsOf: (ScoreEvent) -> Int = { _ in 0 }) -> [Float] {
        let refEvents = events.map { e -> {{APP}}RefEvent in
            let time = Double(e.frame) / rate
            switch e.kind {
            case .noteOn:
                return {{APP}}RefEvent(time: time, kind: Int32({{APP_UPPER}}_REF_NOTE_ON), key: Int32(e.key), pitch: Int32(e.pitch),
                                       value: Float(e.velocity) / 127, params: Int32(paramsOf(e)))
            case .noteOff:
                return {{APP}}RefEvent(time: time, kind: Int32({{APP_UPPER}}_REF_NOTE_OFF), key: Int32(e.key), pitch: Int32(e.pitch), value: 0, params: 0)
            case .pedal(let down):
                return {{APP}}RefEvent(time: time, kind: Int32({{APP_UPPER}}_REF_PEDAL), key: 0, pitch: 0, value: down ? 1 : 0, params: 0)
            case .bend(let value):
                return {{APP}}RefEvent(time: time, kind: Int32({{APP_UPPER}}_REF_BEND), key: 0, pitch: 0,
                                       value: Float(value) / (value >= 0 ? 8191 : 8192), params: 0)
            }
        }
        var out = [Float](repeating: 0, count: frames)
        var how = playing
        {{APP_C}}_ref_render(refEvents, Int32(refEvents.count), params, Int32(params.count), &how,
                             oversampled ? 2 * rate : rate, oversampled ? 1 : 0, &out, Int32(frames))
        return out
    }
}
