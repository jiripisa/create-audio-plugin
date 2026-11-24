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

/// One of the prototype's renders: a sound (program and knobs, engine identifiers and plain
/// engine values) and its notes, on the keyboard or, with `pads`, on the default kit's pads
/// (note 36 + pad, each pad at its own pitch).
struct SpikeRender: Sendable, CustomTestStringConvertible {
    let name: String
    var program: Int32 = 0
    var knobs: [String: Float] = [:]
    var pads = false
    let notes: [SpikeNote]

    var testDescription: String { name }

    /// Seconds: the last note and 2.5 s, enough for the default Release to end.
    var seconds: Double { (notes.map { $0.time + ($0.hold ?? 0) }.max() ?? 0) + 2.5 }

    /// What the reference plays: the program's values, and the knobs over them.
    var reference: [String: Float] {
        (PrototypeScores.programs[Int(program)] ?? [:]).merging(knobs) { $1 }
    }
}

/// One MIDI event of a score at a whole frame: a note-on or a note-off of `note`, sounding
/// `key`'s voice (the note on the keyboard, the pad on the pads) at `pitch`.
struct ScoreEvent {
    let frame: Int
    let key: Int
    let note: UInt8
    let pitch: UInt8
    let velocity: UInt8
    let noteOff: Bool
}

/// The prototype's scores and renders, and a way to render them through the reference (the
/// prototype itself). Shared by the tests that compare the engine with it, the regression
/// references and the listening renders.
enum PrototypeScores {

    /// The engine's output scale against the prototype's units (`kOutputLevel` in Params.h).
    static let level = 0.44

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

    /// A melody of quarter notes at 100 BPM, each held for most of its beat.
    static func melody(_ notes: [UInt8], from start: Double = 0.2, beat: Double = 0.6) -> [SpikeNote] {
        notes.enumerated().map { SpikeNote(time: start + Double($0.offset) * beat, note: $0.element,
                                           accent: $0.offset % 2 == 0 ? 0.9 : 0.6, hold: beat * 0.8) }
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
    ]

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

    /// A render's notes as events at `rate`, note-ons and note-offs in time order. On the pads, a
    /// note's key is its pad and its pitch the pad's note in the default kit (`pitchOfPad`).
    static func events(_ render: SpikeRender, rate: Double, pitchOfPad: (Int) -> UInt8 = { UInt8(36 + $0) }) -> [ScoreEvent] {
        var events: [(time: Double, order: Int, event: ScoreEvent)] = []
        for (order, n) in render.notes.enumerated() {
            let key = render.pads ? Int(n.note) - 36 : Int(n.note)
            let pitch = render.pads ? pitchOfPad(key) : n.note
            let on = Int((n.time * rate).rounded())
            events.append((n.time, 2 * order, ScoreEvent(frame: on, key: key, note: n.note, pitch: pitch,
                                                         velocity: velocity(n.accent), noteOff: false)))
            if let hold = n.hold {
                events.append((n.time + hold, 2 * order + 1,
                               ScoreEvent(frame: Int(((n.time + hold) * rate).rounded()), key: key, note: n.note, pitch: pitch,
                                          velocity: 0, noteOff: true)))
            }
        }
        return events.sorted { ($0.event.frame, $0.order) < ($1.event.frame, $1.order) }.map(\.event)
    }

    static func frames(_ render: SpikeRender, rate: Double) -> Int { Int(render.seconds * rate) }

    /// A render's notes as timed MIDI for a `Synth`.
    static func midiEvents(_ render: SpikeRender) -> [GrooveEvent] {
        var events: [(Double, Int, GrooveEvent)] = []
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

    /// Renders `events` through the reference at `rate`. With `oversampled` the voices run at
    /// twice `rate` and the engine's decimator brings them back. `paramsOf` picks an event's
    /// entry of `params` (by default the first).
    static func referenceRender(_ events: [ScoreEvent], frames: Int, params: [{{APP}}RefParams], rate: Double, oversampled: Bool,
                                paramsOf: (ScoreEvent) -> Int = { _ in 0 }) -> [Float] {
        let refEvents = events.map { e in
            {{APP}}RefEvent(time: Double(e.frame) / rate, key: Int32(e.key), hz: noteHz(e.pitch),
                            velocity: Float(e.velocity) / 127, params: Int32(paramsOf(e)), noteOff: e.noteOff ? 1 : 0)
        }
        var out = [Float](repeating: 0, count: frames)
        {{APP_C}}_ref_render(refEvents, Int32(refEvents.count), params, Int32(params.count),
                             oversampled ? 2 * rate : rate, oversampled ? 1 : 0, &out, Int32(frames))
        return out
    }
}
