import Foundation
import Testing
import {{APP}}DSP
import {{APP}}Reference
@testable import {{APP}}Core

/// The engine against the listening prototype the author approved: the engine renders the
/// prototype's scores, in keyboard mode and in pad mode, and must give the prototype's samples,
/// up to one output scale. The reference is the prototype's voice played by the prototype's own
/// harness, so this is also where the harness's rules (a re-hit, Mono and Legato, the glide, the
/// pedal, the bend) are held to the engine's. At 96 kHz the voices run at the host's rate; at
/// 48 kHz they run at twice it, and the reference goes through the same decimator.
@Suite("Prototype equivalence")
struct PrototypeEquivalenceTests: EngineHarness {

    /// The engine's output scale against the prototype's raw sum: kOutputLevel times Volume -12 dB.
    static let expectedScale = PrototypeScores.level * 0.251188643150958

    static let renders = PrototypeScores.renders

    // MARK: - Rendering and comparing

    /// Renders `events` in `mode` at `rate`, in blocks of 128 frames, each block's events given
    /// with `{{APP_C}}_midi` before it is processed.
    func engineRender(_ events: [ScoreEvent], frames: Int, rate: Double, mode: Int32,
                      set: (OpaquePointer) -> Void) -> (left: [Float], right: [Float]) {
        let engine = {{APP_C}}_create()!
        defer { {{APP_C}}_destroy(engine) }
        {{APP_C}}_prepare(engine, rate)
        {{APP_C}}_reset(engine)
        {{APP_C}}_set_mode(engine, mode)
        set(engine)

        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var next = 0
        var start = 0
        while start < frames {
            let count = min(128, frames - start)
            while next < events.count && events[next].frame < start + count {
                let midi = events[next].midi
                {{APP_C}}_midi(engine, Int32(midi.status), Int32(midi.data1), Int32(midi.data2), Int32(events[next].frame - start))
                next += 1
            }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    {{APP_C}}_process(engine, l.baseAddress! + start, r.baseAddress! + start, Int32(count))
                }
            }
            start += count
        }
        return (left, right)
    }

    /// The least-squares scale of `reference` onto `engine` (<e,r>/<r,r>), and what is left of
    /// the engine's output after it, in dB re the scaled reference.
    func matches(_ engine: [Float], _ reference: [Float]) -> (scale: Double, residualDb: Double) {
        precondition(engine.count == reference.count)
        var er = 0.0, rr = 0.0
        for i in engine.indices { er += Double(engine[i]) * Double(reference[i]); rr += Double(reference[i]) * Double(reference[i]) }
        let scale = er / rr
        var residual = 0.0, signal = 0.0
        for i in engine.indices {
            let s = scale * Double(reference[i])
            residual += (Double(engine[i]) - s) * (Double(engine[i]) - s)
            signal += s * s
        }
        return (scale, 10 * log10(residual / signal))
    }

    /// Puts a render's sound into `set`: its program, its knobs, and Volume -12 dB, which keeps
    /// the peaks under the limiter's 0.6.
    func load(_ render: SpikeRender, into set: Int32, of engine: OpaquePointer) {
        {{APP_C}}_set_program(engine, set, render.program)
        setKnobs(engine, render.knobs, set: set)
        setKnobs(engine, ["volume": -12], set: set)
    }

    /// A prototype render through the engine and through the reference at `rate`: on the keyboard,
    /// or on the default kit's pads, every pad at its kit pitch with the render's sound.
    func compare(_ render: SpikeRender, rate: Double) -> (out: (left: [Float], right: [Float]), scale: Double, residualDb: Double) {
        let probe = {{APP_C}}_create()!
        defer { {{APP_C}}_destroy(probe) }
        let events = PrototypeScores.events(render, rate: rate) { UInt8({{APP_C}}_pad_note(probe, Int32($0))) }
        let frames = PrototypeScores.frames(render, rate: rate)
        let reference = PrototypeScores.referenceRender(events, frames: frames, params: [PrototypeScores.referenceParams(render.reference)],
                                                        playing: PrototypeScores.referencePlaying(render.reference, pads: render.pads),
                                                        rate: rate, oversampled: rate < 88_200)
        let mode = Int32(render.pads ? {{APP_UPPER}}_MODE_PADS : {{APP_UPPER}}_MODE_KEYBOARD)
        let out = engineRender(events, frames: frames, rate: rate, mode: mode) { engine in
            if render.pads {
                for pad: Int32 in 0..<Int32({{APP_UPPER}}_NUM_PADS) { load(render, into: pad + 1, of: engine) }
            } else {
                load(render, into: Self.keyboard, of: engine)
            }
        }
        let m = matches(out.left, reference)
        return (out, m.scale, m.residualDb)
    }

    func expectEquivalent(_ render: SpikeRender, rate: Double) {
        let c = compare(render, rate: rate)
        #expect(c.out.left == c.out.right)                                   // Pan at the centre
        let peak = c.out.left.map(abs).max() ?? 0
        #expect(peak < 0.6, "\(render.name): peak \(peak)")                  // the limiter stays out of it
        #expect(c.residualDb < -60, "\(render.name) at \(Int(rate)) Hz: residual \(c.residualDb) dB")
        #expect(abs(c.scale - Self.expectedScale) / Self.expectedScale < 1e-3, "\(render.name): scale \(c.scale)")
        print(String(format: "equivalence %@ at %d Hz: residual %.1f dB", render.name, Int(rate), c.residualDb))
    }

    // MARK: - Tests

    @Test("The engine plays the approved prototype's renders at 96 kHz", arguments: PrototypeEquivalenceTests.renders)
    func at96k(_ render: SpikeRender) {
        expectEquivalent(render, rate: 96_000)
    }

    @Test("At 48 kHz the oversampled engine plays them through the decimator", arguments: PrototypeEquivalenceTests.renders)
    func at48k(_ render: SpikeRender) {
        expectEquivalent(render, rate: 48_000)
    }
}
