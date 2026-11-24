/// One MIDI message of a score, `time` seconds after its start.
struct GrooveEvent {
    let time: Double
    let status: UInt8
    let data1: UInt8
    let data2: UInt8

    init(_ time: Double, _ status: UInt8, _ data1: UInt8, _ data2: UInt8) {
        self.time = time
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }
}

/// Scores the tests and the listening renders share.
enum Grooves {

    /// The velocity byte of an accent (0...1).
    static func velocity(_ accent: Float) -> UInt8 { UInt8((accent * 127).rounded()) }

    /// The default kit, every pad, 4 bars at 100 BPM, as (time, pad, accent): the lowest pads on
    /// the beats, the others in turn on the eighths between them, each pad hit at least once.
    static let defaultKitHits: [(time: Double, pad: Int, accent: Float)] = {
        let sixteenth = 60.0 / 100.0 / 4
        var hits: [(time: Double, pad: Int, accent: Float)] = []
        for bar in 0..<4 {
            for step in stride(from: 0, to: 16, by: 2) {
                let pad = step % 4 == 0 ? (step / 4) % 2 : 2 + (bar * 4 + step / 4) % 14
                hits.append((0.2 + Double(bar * 16 + step) * sixteenth, pad, step % 4 == 0 ? 0.9 : 0.6))
            }
        }
        return hits
    }()

    /// The same as MIDI events: a pad is hit by the note 36 + its index.
    static let defaultKit: [GrooveEvent] = defaultKitHits.map {
        GrooveEvent($0.time, 0x90, UInt8(36 + $0.pad), velocity($0.accent))
    }

    /// The kit's length: the last bar and a 3 s tail.
    static let defaultKitLength = 0.2 + 16 * 60.0 / 100 + 3.0
}
