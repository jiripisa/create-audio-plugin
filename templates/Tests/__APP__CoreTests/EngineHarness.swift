import Accelerate
import Foundation
import {{APP}}DSP
@testable import {{APP}}Core

/// What the engine's test suites share: a fresh engine (at 96 kHz unless a test names another
/// rate), renders in blocks of 128 frames, and the measures they compare renders with. A suite
/// conforms to use them.
protocol EngineHarness {}

extension EngineHarness {

    static var rate: Double { 96_000 }
    static var keyboard: Int32 { Int32({{APP_UPPER}}_KEYBOARD_SET) }

    static func index(_ identifier: String) -> Int32 {
        guard let parameter = Parameters.named(identifier) else { preconditionFailure("unknown knob \(identifier)") }
        return Int32(parameter.index)
    }

    static func frames(_ seconds: Double, at rate: Double = rate) -> Int { Int((seconds * rate).rounded()) }

    /// Puts `knobs` (plain values) into `set`.
    func setKnobs(_ engine: OpaquePointer, _ knobs: [String: Float], set: Int32 = Int32({{APP_UPPER}}_KEYBOARD_SET)) {
        for (key, value) in knobs { {{APP_C}}_set_plain(engine, set, Self.index(key), value) }
    }

    /// A fresh engine at `rate` in keyboard mode, with `knobs` (plain values) in the keyboard set.
    func makeEngine(_ knobs: [String: Float] = [:], rate: Double = Self.rate) -> OpaquePointer {
        let engine = {{APP_C}}_create()!
        {{APP_C}}_prepare(engine, rate)
        {{APP_C}}_reset(engine)
        {{APP_C}}_set_mode(engine, Int32({{APP_UPPER}}_MODE_KEYBOARD))
        setKnobs(engine, knobs)
        return engine
    }

    /// Renders `frames` of the left channel in blocks of 128 frames.
    func render(_ engine: OpaquePointer, frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        var start = 0
        out.withUnsafeMutableBufferPointer { buffer in
            while start < frames {
                let count = min(128, frames - start)
                {{APP_C}}_process(engine, buffer.baseAddress! + start, nil, Int32(count))
                start += count
            }
        }
        return out
    }

    func render(_ engine: OpaquePointer, seconds: Double, at rate: Double = Self.rate) -> [Float] {
        render(engine, frames: Self.frames(seconds, at: rate))
    }

    /// Renders `frames` of both channels in blocks of 128 frames.
    func renderStereo(_ engine: OpaquePointer, frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames), right = [Float](repeating: 0, count: frames)
        var start = 0
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                while start < frames {
                    let count = min(128, frames - start)
                    {{APP_C}}_process(engine, l.baseAddress! + start, r.baseAddress! + start, Int32(count))
                    start += count
                }
            }
        }
        return (left, right)
    }

    func rms<C: Collection>(_ x: C) -> Double where C.Element == Float {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1))).squareRoot()
    }

    /// dB of (a - b) re b.
    func residualDb<A: Collection, B: Collection>(_ a: A, _ b: B) -> Double where A.Element == Float, B.Element == Float {
        var difference = 0.0, signal = 0.0
        for (x, y) in zip(a, b) { difference += Double(x - y) * Double(x - y); signal += Double(y) * Double(y) }
        return 10 * log10(difference / signal)
    }

    /// The fundamental of `x` in Hz: the normalised autocorrelation's highest peak from its first zero
    /// crossing up to 1.5 periods of `expected`, placed between samples by a parabola. The window
    /// keeps out an octave error (half or twice the period) without steering the answer.
    func fundamental(_ x: [Float], rate: Double, expected: Double) -> Double {
        let maxLag = Int(1.5 * rate / expected)
        let length = x.count - maxLag
        var r = [Float](repeating: 0, count: maxLag + 1)
        x.withUnsafeBufferPointer { signal in
            vDSP_conv(signal.baseAddress!, 1, signal.baseAddress!, 1, &r, 1, vDSP_Length(maxLag + 1), vDSP_Length(length))
        }
        // Normalised: each lag's product over the energies of the two stretches it multiplies, so
        // that a decaying note does not pull the peak towards the shorter lags.
        var energy = [Double](repeating: 0, count: x.count + 1)
        for (i, sample) in x.enumerated() { energy[i + 1] = energy[i] + Double(sample) * Double(sample) }
        for lag in 0...maxLag {
            let a = energy[length] - energy[0], b = energy[lag + length] - energy[lag]
            r[lag] = a > 0 && b > 0 ? Float(Double(r[lag]) / (a * b).squareRoot()) : 0
        }
        guard let firstNegative = r.firstIndex(where: { $0 < 0 }) else { return 0 }
        var best = firstNegative
        for lag in firstNegative..<maxLag where r[lag] > r[best] { best = lag }
        guard best > firstNegative && best < maxLag else { return rate / Double(best) }
        let a = Double(r[best - 1]), b = Double(r[best]), c = Double(r[best + 1])
        return rate / (Double(best) + 0.5 * (a - c) / (a - 2 * b + c))
    }
}

/// The knobs the platform's tests address: the platform block by identifier, the instrument's by
/// position, never by name, so that the tests hold for every instrument.
enum TestKnobs {

    /// The platform block, the first knobs of every instrument's table, in their permanent order.
    static let platform = ["volume", "pan", "tune", "octave", "bendup", "benddown", "voicemode", "glide", "lfostart",
                           "lfo1rate", "lfo1shape", "lfo2rate", "lfo2shape", "velsens"]

    /// Every knob, in table order: the parameters that come with a MIDI controller.
    static let all = Parameters.all.filter { Controllers.standard(for: $0) != nil }

    /// The instrument's knobs, after the platform block.
    static let instrument = Array(all.dropFirst(platform.count))

    /// The first of the instrument's knobs.
    static var first: Parameter { instrument[0] }

    /// The first of the instrument's knobs that is continuous and has a VEL amount.
    static let firstVelTarget: Parameter = {
        guard let knob = instrument.first(where: { $0.kind == .continuous && Velocity.amount(of: $0) != nil })
        else { preconditionFailure("the velocity moves no knob of the instrument") }
        return knob
    }()

    static func named(_ identifier: String) -> Parameter {
        guard let parameter = Parameters.named(identifier) else { preconditionFailure("unknown knob \(identifier)") }
        return parameter
    }

    /// Controllers no knob comes with and MIDI does not reserve, lowest first: what a test teaches
    /// a knob, or moves to see that nothing listens.
    static let freeControllers: [Int] = (0...127).filter { cc in
        !Controllers.isReserved(cc) && !all.contains { Controllers.standard(for: $0) == cc }
    }

    /// The last program, which a test loads where it needs one that is not the first.
    static var otherProgram: Int { Programs.names.count - 1 }

    /// A knob that `otherProgram` sets to another value than the first program does.
    static let programKnob: Parameter = {
        guard let knob = all.first(where: { Programs.value(program: otherProgram, parameter: $0) != Programs.value(program: 0, parameter: $0) })
        else { preconditionFailure("the last program sets no knob apart from the first") }
        return knob
    }()
}
