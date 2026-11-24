// Measure recordings and renders: the pitch first, then the harmonics at that pitch, the
// envelope, and the noise floor in the tail (create-audio-plugin skill).
//
//   swift scripts/analyze.swift <audio>... [--json] [--tail a-b] [--window a-b] [--ref <audio>]
//                               [--fmin Hz] [--fmax Hz]
//   swiftc -O scripts/analyze.swift -o "$TMPDIR/analyze"    the same as a binary: no compile
//                                                            step per run, for many files
//
//   --json        one JSON object on stdout (fields below) instead of the plain text
//   --tail a-b    the tail window in seconds from the file's start (default: its last 0.5 s)
//   --window a-b  the steady window for pitch, harmonics, centroid and HNR (default: found)
//   --ref <audio> measure this file too and print each file's differences from it
//   --fmin/--fmax the pitch search range, Hz (default 30-2000)
//
// Exit codes: 0 measured (a file without a stable pitch still counts), 1 a file cannot be read
// or converted, 2 usage error.
//
// Input: WAV files of any bit depth (16/24/32-bit int, 32/64-bit float), mono or more channels,
// any rate, read with AVFoundation and measured as a mono mix (the channels' mean). Any other
// file (.ogg, .mp3, .flac, .aiff, .m4a ...) is first converted by `afconvert -f WAVE -d LEF32`
// into a new folder under the system's temporary folder, never next to the input, and removed
// at exit.
//
// Method (rates, windows and thresholds are fixed so that numbers compare between runs):
//   levels     dBFS = 20 log10(RMS), full scale 1.0 (a full-scale sine reads -3.0 dBFS);
//              -200 stands for digital silence. Frames: 20 ms RMS every 5 ms.
//   note       the measured note: the first one that comes within 3 dB of the loudest frame
//              (in a phrase, not always the loudest note), until it falls 12 dB under that frame;
//              with --window, the note of the loudest frame inside the window. Window, pitch,
//              harmonics and envelope all belong to this note.
//   window     steady window: from 20 ms after that first frame, for 200 ms or until a frame
//              falls 12 dB under the loudest (at least 50 ms); --window sets it.
//   f0         FIRST, on the steady window: normalised autocorrelation (NCCF) over the search
//              range; the first peak within 90 % of the highest one is taken (no octave too
//              low), refined by a parabola. Octave guard: halved when the NCCF at twice the lag
//              closes at least half of the remaining gap to 1 and the spectrum has a component
//              at half the pitch within 40 dB of the strongest harmonic (no octave too high).
//              No f0 when the highest peak is under 0.5 ("no stable pitch").
//   harmonics  then, at that f0: Hann window over the steady window, FFT zero-padded at least
//              4x, the strongest bin within +-3 % of k * f0 (k = 1..10; stretched partials are
//              found), refined by a parabola on dB. Levels in dB re H1; never read at a nominal
//              key's pitch.
//   centroid   magnitude-weighted mean frequency above 50 Hz of the same spectrum.
//   HNR        10 log10(r / (1 - r)) from the NCCF r at the period (the parabola's top), capped
//              at 80 dB.
//   attack     on 5 ms RMS every 1 ms: from the last point 20 dB under the note's peak to the
//              first point within 3 dB of it.
//   decay      frames: from the note's loudest frame to the first frame 20 dB under it.
//   T60        frames: a straight line fitted to dB over time, from the first frame 6 dB under
//              the note's loudest until 60 dB under it, 10 dB over the tail floor or a new onset (a
//              rise of 6 dB over the lowest level so far), extrapolated to 60 dB; none when the
//              fit spans less than 12 dB.
//   tail       RMS of the tail window; floor = 10th percentile of its frames (a tone that still
//              decays there does not lift it); centroid of its spectrum (hiss is high, hum low).
//   ref        each file minus the reference: f0 in cents, the rest in their own units.
//
// JSON (version 1). Absent values are null. Times in s (suffix S), ms (Ms), frequencies in Hz.
//   { "tool": "analyze.swift", "version": 1,
//     "files": [ <file>... ],
//     "ref": <file> | null }
//   <file> = {
//     "file": path as given, "converted": bool (went through afconvert),
//     "sampleRate": Hz, "channels": n, "bits": n | null, "sampleFormat": "int" | "float" | null,
//     "durationS", "peakDb", "peakTimeS", "rmsDb",
//     "windowS": [start, end]                 the steady window used,
//     "f0Hz", "periodicity" (NCCF at the period, 0..1), "octaveGuard": "none" | "halved",
//     "note": "A3" (nearest equal-tempered note, A4 = 440 Hz), "cents": f0 against it,
//     "harmonicsDb": [H1..H10 dB re H1, H1 = 0; null above Nyquist, all null without f0],
//     "harmonicsHz": [the frequencies where they were found],
//     "h1Db": H1's level in dBFS (as a sine's RMS),
//     "centroidHz", "centroidRatio" (centroid / f0), "hnrDb",
//     "noteTimeS" (the measured note's loudest frame), "attackMs", "decayMs", "t60S", "t60SpanDb",
//     "tail": { "startS", "endS", "rmsDb", "floorDb", "centroidHz" },
//     "vsRef": only with --ref, this file minus the reference: { "f0Cents", "harmonicsDb": [10],
//              "centroidHz", "hnrDb", "attackMs", "decayMs", "t60S", "rmsDb", "peakDb",
//              "tailRmsDb", "tailFloorDb" } }

import AVFoundation
import Accelerate
import Foundation

let usageText = """
    usage: analyze.swift <audio>... [--json] [--tail a-b] [--window a-b] [--ref <audio>] [--fmin Hz] [--fmax Hz]
    """

var tempDir: URL?

func cleanUp() {
    if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
}

func fail(_ message: String, _ code: Int32) -> Never {
    cleanUp()
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// ---- arguments ---------------------------------------------------------------------------------

struct Options {
    var json = false
    var tail: (Double, Double)?
    var window: (Double, Double)?
    var ref: String?
    var fmin = 30.0
    var fmax = 2000.0
    var files: [String] = []
}

func parseRange(_ text: String) -> (Double, Double)? {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), a >= 0, b > a else { return nil }
    return (a, b)
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())[...]
    func value(_ flag: String) -> String {
        guard let v = args.popFirst() else { fail("\(flag) needs a value\n\(usageText)", 2) }
        return v
    }
    while let a = args.popFirst() {
        switch a {
        case "--json": o.json = true
        case "--tail":
            guard let r = parseRange(value(a)) else { fail("--tail wants a-b in seconds, a < b\n\(usageText)", 2) }
            o.tail = r
        case "--window":
            guard let r = parseRange(value(a)) else { fail("--window wants a-b in seconds, a < b\n\(usageText)", 2) }
            o.window = r
        case "--ref": o.ref = value(a)
        case "--fmin":
            guard let v = Double(value(a)), v > 0 else { fail("--fmin wants Hz\n\(usageText)", 2) }
            o.fmin = v
        case "--fmax":
            guard let v = Double(value(a)), v > 0 else { fail("--fmax wants Hz\n\(usageText)", 2) }
            o.fmax = v
        case "-h", "--help":
            print(usageText)
            exit(0)
        default:
            if a.hasPrefix("--") { fail("unknown option \(a)\n\(usageText)", 2) }
            o.files.append(a)
        }
    }
    if o.files.isEmpty { fail(usageText, 2) }
    if o.fmin >= o.fmax { fail("--fmin must be under --fmax\n\(usageText)", 2) }
    return o
}

// ---- reading -----------------------------------------------------------------------------------

struct Audio {
    var mono: [Float]
    var rate: Double
    var channels: Int
    var bits: Int?
    var isFloat: Bool?
    var converted: Bool
}

func convert(_ path: String, index: Int) -> URL {
    if tempDir == nil {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("analyze-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            fail("cannot create a temporary folder: \(error.localizedDescription)", 1)
        }
        tempDir = dir
    }
    let out = tempDir!.appendingPathComponent("\(index).wav")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    p.arguments = ["-f", "WAVE", "-d", "LEF32", path, out.path]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { fail("cannot run afconvert: \(error.localizedDescription)", 1) }
    p.waitUntilExit()
    if p.terminationStatus != 0 { fail("afconvert could not convert \(path)", 1) }
    return out
}

func read(_ path: String, index: Int) -> Audio {
    guard FileManager.default.isReadableFile(atPath: path) else { fail("cannot read \(path)", 1) }
    let ext = (path as NSString).pathExtension.lowercased()
    let converted = !(ext == "wav" || ext == "wave")
    let url = converted ? convert(path, index: index) : URL(fileURLWithPath: path)
    let file: AVAudioFile
    do { file = try AVAudioFile(forReading: url) } catch { fail("cannot read \(path): \(error.localizedDescription)", 1) }
    let format = file.processingFormat
    let frames = AVAudioFrameCount(file.length)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        fail("\(path) holds no audio", 1)
    }
    do { try file.read(into: buffer) } catch { fail("cannot read \(path): \(error.localizedDescription)", 1) }
    let n = Int(buffer.frameLength), channels = Int(format.channelCount)
    guard n > 0, let data = buffer.floatChannelData else { fail("\(path) holds no audio", 1) }
    var mono = [Float](repeating: 0, count: n)
    for c in 0..<channels { vDSP_vadd(mono, 1, data[c], 1, &mono, 1, vDSP_Length(n)) }
    if channels > 1 {
        var scale = 1 / Float(channels)
        vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(n))
    }
    let settings = file.fileFormat.settings
    return Audio(mono: mono, rate: format.sampleRate, channels: channels,
                 bits: converted ? nil : settings[AVLinearPCMBitDepthKey] as? Int,
                 isFloat: converted ? nil : settings[AVLinearPCMIsFloatKey] as? Bool, converted: converted)
}

// ---- signal helpers ----------------------------------------------------------------------------

func db(power: Double) -> Double { power > 1e-20 ? 10 * log10(power) : -200 }
func db(amplitude: Double) -> Double { amplitude > 1e-10 ? 20 * log10(amplitude) : -200 }

// dB of windows of `win` samples every `hop` samples over x[from..<to] (at least one frame).
func frameLevels(_ x: [Float], from: Int = 0, to: Int? = nil, win: Int, hop: Int) -> [Double] {
    let end = min(to ?? x.count, x.count)
    var out: [Double] = []
    var s = from
    x.withUnsafeBufferPointer { p in
        while s + win <= end || (out.isEmpty && s < end) {
            let len = min(win, end - s)
            var ms: Float = 0
            vDSP_measqv(p.baseAddress! + s, 1, &ms, vDSP_Length(len))
            out.append(db(power: Double(ms)))
            s += hop
        }
    }
    return out
}

struct Spectrum {
    var mag: [Double]   // amplitude of a sinusoid at each bin
    var binHz: Double
}

// Hann-windowed, zero-padded to a power of two of at least `pad` times the length.
func spectrum(_ x: ArraySlice<Float>, rate: Double, pad: Int = 4) -> Spectrum {
    let n = x.count
    var size = 1, log2n: vDSP_Length = 0
    while size < max(2, n * pad) { size *= 2; log2n += 1 }
    var buf = [Double](repeating: 0, count: size)
    var wsum = 0.0
    for (i, v) in x.enumerated() {
        let w = n > 1 ? 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1)) : 1
        buf[i] = w * Double(v)
        wsum += w
    }
    let half = size / 2
    var re = [Double](repeating: 0, count: half), im = [Double](repeating: 0, count: half)
    var mag = [Double](repeating: 0, count: half + 1)
    guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { fail("FFT setup failed", 1) }
    re.withUnsafeMutableBufferPointer { rp in
        im.withUnsafeMutableBufferPointer { ip in
            var split = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            buf.withUnsafeBytes { raw in
                vDSP_ctozD(raw.bindMemory(to: DSPDoubleComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
            }
            vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
        }
    }
    vDSP_destroy_fftsetupD(setup)
    // vDSP's real FFT is twice the DFT; a sinusoid of amplitude A gives |DFT| = A * wsum / 2.
    let scale = wsum > 0 ? 1 / wsum : 0
    mag[0] = abs(re[0]) * scale / 2
    mag[half] = abs(im[0]) * scale / 2
    for k in 1..<half { mag[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot() * scale }
    return Spectrum(mag: mag, binHz: rate / Double(size))
}

// The strongest component within +-3 % of hz (at least +-2 bins): (amplitude, Hz), refined by a
// parabola on dB. nil above Nyquist.
func peak(near hz: Double, in s: Spectrum) -> (amp: Double, hz: Double)? {
    let nyquistBin = s.mag.count - 1
    let lo = max(1, Int(((hz * 0.97) / s.binHz).rounded(.down)))
    let hi = min(nyquistBin - 1, max(Int(((hz * 1.03) / s.binHz).rounded(.up)), Int((hz / s.binHz).rounded()) + 2))
    guard hz * 1.03 < s.binHz * Double(nyquistBin), lo <= hi else { return nil }
    var best = lo
    for k in lo...hi where s.mag[k] > s.mag[best] { best = k }
    let a = db(amplitude: s.mag[best - 1]), b = db(amplitude: s.mag[best]), c = db(amplitude: s.mag[best + 1])
    let den = a - 2 * b + c
    let d = den < 0 ? 0.5 * (a - c) / den : 0
    let level = b - 0.25 * (a - c) * d
    return (pow(10, level / 20), (Double(best) + d) * s.binHz)
}

func centroid(_ s: Spectrum) -> Double? {
    var num = 0.0, den = 0.0
    for k in 0..<s.mag.count {
        let f = Double(k) * s.binHz
        if f <= 50 { continue }
        num += f * s.mag[k]
        den += s.mag[k]
    }
    return den > 1e-12 ? num / den : nil
}

func percentile(_ v: [Double], _ p: Double) -> Double {
    let s = v.sorted()
    return s[min(s.count - 1, max(0, Int((p * Double(s.count - 1)).rounded())))]
}

func noteName(_ f: Double) -> (String, Double) {
    let midi = 69 + 12 * log2(f / 440)
    let nearest = midi.rounded()
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let i = Int(nearest)
    return ("\(names[((i % 12) + 12) % 12])\(Int((Double(i) / 12).rounded(.down)) - 1)", (midi - nearest) * 100)
}

// ---- the measurement ---------------------------------------------------------------------------

struct Pitch {
    var f0: Double
    var periodicity: Double
    var halved: Bool
}

// Normalised autocorrelation of x at `lag`, over the overlapping part.
final class NCCF {
    let x: [Double]
    let cum: [Double]
    init(_ samples: ArraySlice<Float>) {
        x = samples.map { Double($0) }
        var c = [Double](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { c[i + 1] = c[i] + x[i] * x[i] }
        cum = c
    }
    func at(_ lag: Int) -> Double {
        let n = x.count
        guard lag > 0, lag < n else { return 0 }
        var dot = 0.0
        x.withUnsafeBufferPointer { p in vDSP_dotprD(p.baseAddress!, 1, p.baseAddress! + lag, 1, &dot, vDSP_Length(n - lag)) }
        let e = (cum[n - lag] * (cum[n] - cum[lag])).squareRoot()
        return e > 0 ? dot / e : 0
    }
}

// The vertex of a parabola through (-1, a), (0, b), (1, c): (offset, value).
func parabola(_ a: Double, _ b: Double, _ c: Double) -> (offset: Double, value: Double) {
    let den = a - 2 * b + c
    let d = den < 0 ? 0.5 * (a - c) / den : 0
    return (d, min(1, b - 0.25 * (a - c) * d))
}

func findPitch(_ seg: ArraySlice<Float>, spectrum s: Spectrum, rate: Double, fmin: Double, fmax: Double) -> Pitch? {
    let r = NCCF(seg)
    let n = seg.count
    let minLag = max(2, Int(rate / fmax)), maxLag = min(Int(rate / fmin) + 1, n / 2)
    guard maxLag > minLag + 2 else { return nil }
    var rs = [Double](repeating: 0, count: maxLag + 2)
    for l in minLag...(maxLag + 1) { rs[l] = r.at(l) }
    var top = -1.0
    for l in (minLag + 1)...maxLag where rs[l] > rs[l - 1] && rs[l] >= rs[l + 1] { top = max(top, rs[l]) }
    guard top >= 0.5 else { return nil }
    var lag = minLag + 1
    for l in (minLag + 1)...maxLag where rs[l] > rs[l - 1] && rs[l] >= rs[l + 1] && rs[l] >= 0.9 * top {
        lag = l
        break
    }
    let vertex = parabola(rs[lag - 1], rs[lag], rs[lag + 1])
    var period = Double(lag) + vertex.offset
    var periodicity = vertex.value
    var halved = false
    let lag2 = Int((2 * period).rounded())
    if lag2 + 1 < n * 2 / 3, rate / (2 * period) >= fmin {
        let a = r.at(lag2 - 1), b = r.at(lag2), c = r.at(lag2 + 1)
        var strongest = 0.0
        for k in 1...10 { if let p = peak(near: Double(k) * rate / period, in: s) { strongest = max(strongest, p.amp) } }
        let half = peak(near: rate / (2 * period), in: s)?.amp ?? 0
        let b2 = parabola(a, b, c).value
        if b2 > periodicity, b2 - periodicity >= 0.5 * (1 - periodicity), half > strongest * 0.01 {
            let v2 = parabola(a, b, c)
            period = Double(lag2) + v2.offset
            periodicity = v2.value
            halved = true
        }
    }
    return Pitch(f0: rate / period, periodicity: periodicity, halved: halved)
}

struct Measurement {
    var file: String
    var audio: Audio
    var duration: Double
    var peakDb: Double, peakTime: Double, rmsDb: Double
    var window: (Double, Double)
    var pitch: Pitch?
    var harmonicsDb: [Double?] = Array(repeating: nil, count: 10)
    var harmonicsHz: [Double?] = Array(repeating: nil, count: 10)
    var h1Db: Double?
    var centroidHz: Double?
    var hnrDb: Double?
    var noteTime: Double?
    var attackMs: Double?, decayMs: Double?, t60: Double?, t60Span: Double?
    var tail: (start: Double, end: Double, rmsDb: Double, floorDb: Double, centroidHz: Double?)
}

func measure(_ path: String, index: Int, options o: Options) -> Measurement {
    let audio = read(path, index: index)
    let x = audio.mono, rate = audio.rate, n = x.count
    let duration = Double(n) / rate
    var peakAmp: Float = 0
    var peakIndex: vDSP_Length = 0
    vDSP_maxmgvi(x, 1, &peakAmp, &peakIndex, vDSP_Length(n))
    var ms: Float = 0
    vDSP_measqv(x, 1, &ms, vDSP_Length(n))

    // Frames (20 ms every 5 ms) and the tail first: the T60 fit stops above the tail floor.
    let hop = Int((0.005 * rate).rounded()), win = Int((0.020 * rate).rounded())
    let frames = frameLevels(x, win: win, hop: hop)
    let hopS = Double(hop) / rate
    let (ta, tb) = o.tail ?? (max(0, duration - 0.5), duration)
    let t0 = min(n - 1, Int(ta * rate)), t1 = max(t0 + 1, min(n, Int(tb * rate)))
    var tailMs: Float = 0
    vDSP_measqv(Array(x[t0..<t1]), 1, &tailMs, vDSP_Length(t1 - t0))
    let tailFrames = frameLevels(x, from: t0, to: t1, win: win, hop: hop)
    let tailSpectrum = spectrum(x[t0..<t1], rate: rate, pad: 1)
    let tail = (start: Double(t0) / rate, end: Double(t1) / rate, rmsDb: db(power: Double(tailMs)),
                floorDb: percentile(tailFrames, 0.10), centroidHz: tailMs > 0 ? centroid(tailSpectrum) : nil)

    // The measured note: the first one that comes within 3 dB of the loudest frame (with
    // --window, the loudest frame inside it), from there until it falls 12 dB under that frame.
    let top = frames.max() ?? -200
    let anchor: Int
    if let w = o.window {
        let a = min(frames.count - 1, Int(w.0 / hopS)), b = max(a, min(frames.count - 1, Int(w.1 / hopS)))
        anchor = (a...b).max { frames[$0] < frames[$1] } ?? a
    } else {
        anchor = frames.firstIndex { $0 >= top - 3 } ?? 0
    }
    var noteEnd = anchor
    while noteEnd + 1 < frames.count, frames[noteEnd + 1] >= frames[anchor] - 12 { noteEnd += 1 }
    let notePeak = (anchor...noteEnd).max { frames[$0] < frames[$1] } ?? anchor
    let noteTop = frames[notePeak]

    // Steady window.
    var wa: Double, wb: Double
    if let w = o.window {
        (wa, wb) = w
    } else {
        wa = Double(anchor) * hopS + 0.020
        var g = Int((wa / hopS).rounded(.up))
        while g < frames.count, frames[g] >= top - 12, Double(g) * hopS < wa + 0.2 { g += 1 }
        wb = max(wa + 0.05, min(wa + 0.2, Double(g) * hopS))
    }
    var s0 = Int(wa * rate), s1 = min(n, Int(wb * rate))
    if s1 - s0 < 64 { s1 = n; s0 = max(0, n - Int(0.05 * rate)) }
    let seg = x[s0..<s1]
    let spec = spectrum(seg, rate: rate)

    var m = Measurement(file: path, audio: audio, duration: duration, peakDb: db(amplitude: Double(peakAmp)),
                        peakTime: Double(peakIndex) / rate, rmsDb: db(power: Double(ms)),
                        window: (Double(s0) / rate, Double(s1) / rate), tail: tail)

    // Pitch first, then everything that is read at it.
    m.centroidHz = centroid(spec)
    if let p = findPitch(seg, spectrum: spec, rate: rate, fmin: o.fmin, fmax: o.fmax) {
        m.pitch = p
        let rr = min(max(p.periodicity, 1e-9), 1 - 1e-8)
        m.hnrDb = 10 * log10(rr / (1 - rr))
        if let h1 = peak(near: p.f0, in: spec) {
            m.h1Db = db(amplitude: h1.amp / 2.0.squareRoot())
            for k in 1...10 {
                if let h = peak(near: Double(k) * p.f0, in: spec) {
                    m.harmonicsDb[k - 1] = db(amplitude: h.amp) - db(amplitude: h1.amp)
                    m.harmonicsHz[k - 1] = h.hz
                }
            }
        }
    }

    // Attack on 5 ms RMS every 1 ms, around the measured note's peak.
    m.noteTime = Double(notePeak) * hopS + 0.010
    let envHop = max(1, Int((0.001 * rate).rounded()))
    let envHopS = Double(envHop) / rate
    let env = frameLevels(x, win: max(1, Int((0.005 * rate).rounded())), hop: envHop)
    let e0 = min(env.count - 1, max(0, Int((Double(anchor) * hopS - 0.05) / envHopS)))
    let e1 = max(e0, min(env.count - 1, Int((Double(noteEnd) * hopS + 0.020) / envHopS)))
    if let p = (e0...e1).max(by: { env[$0] < env[$1] }), env[p] > -200 {
        let envTop = env[p]
        if let a = env[..<p].lastIndex(where: { $0 <= envTop - 20 }), let b = env[a...].firstIndex(where: { $0 >= envTop - 3 }) {
            m.attackMs = Double(b - a) * envHopS * 1000
        }
    }
    // Decay and T60 on the frames, from the measured note's peak.
    if noteTop > -200 {
        if let d = frames[notePeak...].firstIndex(where: { $0 <= noteTop - 20 }) { m.decayMs = Double(d - notePeak) * hopS * 1000 }
        if let s = frames[notePeak...].firstIndex(where: { $0 < noteTop - 6 }) {
            let stop = max(noteTop - 60, tail.floorDb + 10)
            var e = s, low = frames[s]
            while e < frames.count, frames[e] > stop, frames[e] < low + 6 { low = min(low, frames[e]); e += 1 }
            if e - s >= 3 {
                let ts = (s..<e).map { Double($0) * hopS }, ys = Array(frames[s..<e])
                let mt = ts.reduce(0, +) / Double(ts.count), my = ys.reduce(0, +) / Double(ys.count)
                var sxy = 0.0, sxx = 0.0
                for i in 0..<ts.count { sxy += (ts[i] - mt) * (ys[i] - my); sxx += (ts[i] - mt) * (ts[i] - mt) }
                let slope = sxx > 0 ? sxy / sxx : 0
                let span = (ys.max() ?? 0) - (ys.min() ?? 0)
                if slope < 0, span >= 12 { m.t60 = -60 / slope; m.t60Span = span }
            }
        }
    }
    return m
}

// ---- output ------------------------------------------------------------------------------------

func round(_ v: Double?, _ digits: Int) -> Any {
    guard let v, v.isFinite else { return NSNull() }
    let p = pow(10, Double(digits))
    return (v * p).rounded() / p
}

func json(_ m: Measurement) -> [String: Any] {
    var o: [String: Any] = [
        "file": m.file, "converted": m.audio.converted, "sampleRate": m.audio.rate, "channels": m.audio.channels,
        "bits": m.audio.bits.map { $0 as Any } ?? NSNull(),
        "sampleFormat": m.audio.isFloat.map { ($0 ? "float" : "int") as Any } ?? NSNull(),
        "durationS": round(m.duration, 4), "peakDb": round(m.peakDb, 2), "peakTimeS": round(m.peakTime, 4),
        "rmsDb": round(m.rmsDb, 2), "windowS": [round(m.window.0, 4), round(m.window.1, 4)],
        "f0Hz": round(m.pitch?.f0, 3), "periodicity": round(m.pitch?.periodicity, 4),
        "octaveGuard": m.pitch.map { ($0.halved ? "halved" : "none") as Any } ?? NSNull(),
        "harmonicsDb": m.harmonicsDb.map { round($0, 2) }, "harmonicsHz": m.harmonicsHz.map { round($0, 2) },
        "h1Db": round(m.h1Db, 2), "centroidHz": round(m.centroidHz, 1),
        "centroidRatio": round(m.pitch.flatMap { p in m.centroidHz.map { $0 / p.f0 } }, 3),
        "hnrDb": round(m.hnrDb, 2), "noteTimeS": round(m.noteTime, 3),
        "attackMs": round(m.attackMs, 1), "decayMs": round(m.decayMs, 1),
        "t60S": round(m.t60, 3), "t60SpanDb": round(m.t60Span, 1),
        "tail": ["startS": round(m.tail.start, 4), "endS": round(m.tail.end, 4), "rmsDb": round(m.tail.rmsDb, 2),
                 "floorDb": round(m.tail.floorDb, 2), "centroidHz": round(m.tail.centroidHz, 1)],
    ]
    if let p = m.pitch {
        let (name, cents) = noteName(p.f0)
        o["note"] = name
        o["cents"] = round(cents, 1)
    } else {
        o["note"] = NSNull()
        o["cents"] = NSNull()
    }
    return o
}

// JSON text with sorted keys, two-space indents and numbers in their shortest form (-60.15, not
// -60.149999999999999 as JSONSerialization writes it).
func encode(_ value: Any, indent: String = "") -> String {
    let inner = indent + "  "
    switch value {
    case let d as [String: Any]:
        if d.isEmpty { return "{}" }
        let items = d.keys.sorted().map { "\(inner)\(encode($0)): \(encode(d[$0]!, indent: inner))" }
        return "{\n" + items.joined(separator: ",\n") + "\n\(indent)}"
    case let a as [Any]:
        if a.isEmpty { return "[]" }
        if a.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) {
            return "[" + a.map { encode($0) }.joined(separator: ", ") + "]"
        }
        return "[\n" + a.map { inner + encode($0, indent: inner) }.joined(separator: ",\n") + "\n\(indent)]"
    case let b as Bool: return b ? "true" : "false"
    case let i as Int: return String(i)
    case let x as Double:
        if !x.isFinite { return "null" }
        if x == x.rounded(), abs(x) < 1e15 { return String(Int(x)) }
        return String(x)
    case let t as String:
        var out = "\""
        for c in t.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    default: return "null"
    }
}

func minus(_ a: Double?, _ b: Double?) -> Double? {
    guard let a, let b else { return nil }
    return a - b
}

func differences(_ m: Measurement, _ ref: Measurement) -> [String: Any] {
    let cents: Double? = {
        guard let a = m.pitch?.f0, let b = ref.pitch?.f0 else { return nil }
        return 1200 * log2(a / b)
    }()
    return [
        "f0Cents": round(cents, 1),
        "harmonicsDb": (0..<10).map { round(minus(m.harmonicsDb[$0], ref.harmonicsDb[$0]), 2) },
        "centroidHz": round(minus(m.centroidHz, ref.centroidHz), 1), "hnrDb": round(minus(m.hnrDb, ref.hnrDb), 2),
        "attackMs": round(minus(m.attackMs, ref.attackMs), 1), "decayMs": round(minus(m.decayMs, ref.decayMs), 1),
        "t60S": round(minus(m.t60, ref.t60), 3), "rmsDb": round(minus(m.rmsDb, ref.rmsDb), 2),
        "peakDb": round(minus(m.peakDb, ref.peakDb), 2), "tailRmsDb": round(minus(m.tail.rmsDb, ref.tail.rmsDb), 2),
        "tailFloorDb": round(minus(m.tail.floorDb, ref.tail.floorDb), 2),
    ]
}

func fmt(_ v: Double?, _ digits: Int, _ unit: String = "") -> String {
    guard let v, v.isFinite else { return "-" }
    return String(format: "%.\(digits)f", v) + unit
}

func signed(_ v: Double?, _ digits: Int, _ unit: String = "") -> String {
    guard let v, v.isFinite else { return "-" }
    return String(format: "%+.\(digits)f", v) + unit
}

func plain(_ m: Measurement, ref: Measurement?) -> String {
    let a = m.audio
    var bits = a.bits.map { "\($0)-bit" } ?? "converted"
    if let f = a.isFloat { bits += f ? " float" : " int" }
    var lines = ["\(m.file)  \(fmt(a.rate, 0)) Hz, \(a.channels) ch, \(bits), \(fmt(m.duration, 2)) s"]
    lines.append("  level      peak \(fmt(m.peakDb, 1)) dBFS at \(fmt(m.peakTime, 3)) s, RMS \(fmt(m.rmsDb, 1)) dBFS")
    lines.append("  window     \(fmt(m.window.0, 3))-\(fmt(m.window.1, 3)) s (steady)")
    if let p = m.pitch {
        let (name, cents) = noteName(p.f0)
        let guardText = p.halved ? ", octave guard halved" : ""
        lines.append("  f0         \(fmt(p.f0, 2)) Hz (\(name) \(signed(cents, 0)) c), periodicity \(fmt(p.periodicity, 3))\(guardText), HNR \(fmt(m.hnrDb, 1)) dB")
        let hs = m.harmonicsDb.enumerated().map { "H\($0.offset + 1) \(fmt($0.element, 1))" }
        lines.append("  harmonics  dB re H1: " + hs.joined(separator: "  "))
        lines.append("             H1 \(fmt(m.h1Db, 1)) dBFS")
    } else {
        lines.append("  f0         none (no stable pitch in the window)")
    }
    let ratio = m.pitch.flatMap { p in m.centroidHz.map { $0 / p.f0 } }
    lines.append("  centroid   \(fmt(m.centroidHz, 0, " Hz"))" + (ratio.map { " (\(fmt($0, 2)) x f0)" } ?? ""))
    lines.append("  envelope   note at \(fmt(m.noteTime, 2)) s: attack \(fmt(m.attackMs, 0)) ms, decay to -20 dB \(fmt(m.decayMs, 0)) ms, T60 \(fmt(m.t60, 2, " s"))" + (m.t60Span.map { " (fit over \(fmt($0, 0)) dB)" } ?? ""))
    lines.append("  tail       \(fmt(m.tail.start, 2))-\(fmt(m.tail.end, 2)) s: RMS \(fmt(m.tail.rmsDb, 1)) dBFS, floor \(fmt(m.tail.floorDb, 1)) dBFS, centroid \(fmt(m.tail.centroidHz, 0, " Hz"))")
    if let r = ref {
        let d = differences(m, r)
        func v(_ k: String) -> Double? { d[k] as? Double }
        let hs = (d["harmonicsDb"] as? [Any] ?? []).enumerated().map { "H\($0.offset + 1) \(signed($0.element as? Double, 1))" }
        lines.append("  vs ref     f0 \(signed(v("f0Cents"), 1)) c, centroid \(signed(v("centroidHz"), 0)) Hz, HNR \(signed(v("hnrDb"), 1)) dB, RMS \(signed(v("rmsDb"), 1)) dB, peak \(signed(v("peakDb"), 1)) dB")
        lines.append("             harmonics " + hs.joined(separator: "  "))
        lines.append("             attack \(signed(v("attackMs"), 0)) ms, decay \(signed(v("decayMs"), 0)) ms, T60 \(signed(v("t60S"), 2)) s, tail RMS \(signed(v("tailRmsDb"), 1)) dB, tail floor \(signed(v("tailFloorDb"), 1)) dB")
    }
    return lines.joined(separator: "\n")
}

// ---- main --------------------------------------------------------------------------------------

let options = parseOptions()
let ref = options.ref.map { measure($0, index: 0, options: options) }
let results = options.files.enumerated().map { measure($0.element, index: $0.offset + 1, options: options) }
cleanUp()

if options.json {
    var files: [[String: Any]] = []
    for m in results {
        var o = json(m)
        if let r = ref { o["vsRef"] = differences(m, r) }
        files.append(o)
    }
    let top: [String: Any] = ["tool": "analyze.swift", "version": 1, "files": files, "ref": ref.map { json($0) as Any } ?? NSNull()]
    print(encode(top))
} else {
    if let r = ref { print("reference:\n" + plain(r, ref: nil) + "\n") }
    print(results.map { plain($0, ref: ref) }.joined(separator: "\n\n"))
}
