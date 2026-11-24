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
// or converted, 2 usage error, 128 + n killed by signal n (the temporary folder is removed).
//
// Input: WAV files of any bit depth (16/24/32-bit int, 32/64-bit float), mono or more channels,
// any rate, read with AVFoundation and measured as a mono mix (the channels' mean). Any other
// file (.ogg, .mp3, .flac, .aiff, .m4a ...) is first converted by `afconvert -f WAVE -d LEF32`
// into a new folder under $TMPDIR (else the system's temporary folder), never next to the input,
// and removed at exit, also when the run is killed.
//
// Method (rates, windows and thresholds are fixed so that numbers compare between runs):
//   levels     dBFS = 20 log10(RMS), full scale 1.0 (a full-scale sine reads -3.0 dBFS);
//              -200 stands for digital silence. Frames: 20 ms RMS every 5 ms.
//   onsets     rectified complex-domain onset detection (see detectOnsets: Hann frames of about
//              20 ms every 5 ms; a stroke breaks the predicted magnitude and phase even where it
//              hardly raises the level). Each onset starts a stroke that ends one frame before the
//              next onset. Times are within about 5 ms; low notes (under about 60 Hz) can read up
//              to half a period late. strokeRate = 1 / the median interval. Rubbed or rough sounds (HNR under
//              about 10 dB) can show bursts of the rubbing as onsets; check against the research.
//   note       the file-level note: the stroke that holds the first frame within 3 dB of the
//              loudest frame (in a phrase, not always the loudest note; before the first onset,
//              the start of the file); with --window, the stroke where the window starts. Window,
//              pitch, harmonics and envelope all belong to this note and stop at the next onset.
//   window     steady window: from 20 ms after the note's first frame within 3 dB of its
//              loudest, for 200 ms, until a frame falls 12 dB under the loudest or the next onset
//              comes (at least 50 ms when the note is that long; a shorter stroke is used whole
//              from that frame); --window sets it. fewPeriods: it holds fewer than 4 periods of
//              f0, so harmonic levels and HNR are rough.
//   f0         FIRST, on the steady window: normalised autocorrelation (NCCF) over the search
//              range; the first peak within 90 % of the highest one is taken (no octave too
//              low), refined by a parabola. Octave guard: halved when the NCCF at twice the lag
//              (refined only when its peak lies inside lag2 +- 2) closes at least half of the
//              remaining gap to 1 and the halved pitch's odd harmonics (0.5, 1.5 ... 4.5 f)
//              together come within 25 dB of the strongest harmonic (no octave too high; a hum
//              an octave under the note does not halve it).
//              No f0 when the highest peak is under 0.5 ("no stable pitch").
//   harmonics  then, at that f0: Hann window over the steady window, FFT zero-padded at least
//              4x and to bins of at most 1 % of fmin, the strongest bin within +-3 % of k * f0
//              (k = 1..10; stretched partials are found), refined by a parabola on dB (offset
//              kept within half a bin; none when the strongest bin is at the band's edge), so
//              no frequency lies outside its band. Levels in dB re H1; never read at a nominal
//              key's pitch.
//   centroid   magnitude-weighted mean frequency above 50 Hz of the same spectrum.
//   HNR        10 log10(r / (1 - r)) from the NCCF r at the period (the parabola's top), capped
//              at 80 dB.
//   attack     on 5 ms RMS every 1 ms: from the last point 20 dB under the note's peak to the
//              first point within 3 dB of it (file-level note only).
//   decay      frames: from the note's loudest frame to the first frame 20 dB under it; null
//              when the next onset comes first. For a stroke (strokes.each) it is then
//              extrapolated from a line through its frames after the peak (at least 50 ms
//              falling at least 3 dB; decayFitted). A short segment sees only the early decay,
//              which in a multi-rate decay (upper partials faster) is faster than the full one.
//   T60        frames: a straight line fitted to dB over time, from the first frame 6 dB under
//              the note's loudest until 60 dB under it, 10 dB over the tail floor, a rise of 6 dB
//              over the lowest level so far or the next onset, extrapolated to 60 dB; none when
//              the fit spans less than 12 dB.
//   tail       RMS of the tail window; floor = 10th percentile of its frames (a tone that still
//              decays there does not lift it); centroid of its spectrum (hiss is high, hum low).
//   ref        each file minus the reference: f0 in cents, the rest in their own units.
//
// JSON (version 2: onsets, strokeRate, strokes, noteS and fewPeriods added). Absent values are
// null. Times in s (suffix S; onsets in s too), ms (Ms), frequencies in Hz.
//   { "tool": "analyze.swift", "version": 2,
//     "files": [ <file>... ],
//     "ref": <file> | null }
//   <file> = {
//     "file": path as given, "converted": bool (went through afconvert),
//     "sampleRate": Hz, "channels": n, "bits": n | null, "sampleFormat": "int" | "float" | null,
//     "durationS", "peakDb", "peakTimeS", "rmsDb",
//     "noteS": [start, end]                   the file-level note,
//     "windowS": [start, end]                 the steady window used, "fewPeriods": bool,
//     "f0Hz", "periodicity" (NCCF at the period, 0..1), "octaveGuard": "none" | "halved",
//     "note": "A3" (nearest equal-tempered note, A4 = 440 Hz), "cents": f0 against it,
//     "harmonicsDb": [H1..H10 dB re H1, H1 = 0; null above Nyquist, all null without f0],
//     "harmonicsHz": [the frequencies where they were found],
//     "h1Db": H1's level in dBFS (as a sine's RMS),
//     "centroidHz", "centroidRatio" (centroid / f0), "hnrDb",
//     "noteTimeS" (the measured note's loudest frame), "attackMs", "decayMs", "t60S", "t60SpanDb",
//     "tail": { "startS", "endS", "rmsDb", "floorDb", "centroidHz" },
//     "onsets": [s], "strokeRate": strokes per s (1 / median interval; null under 2 onsets),
//     "strokes": { "count", "each": [ { "startS", "endS", "f0Hz", "peakDb" (sample peak, dBFS),
//                  "decayMs", "decayFitted", "t60S", "centroidHz" } ],
//                  "median": { "f0Hz", "peakDb", "decayMs", "t60S", "centroidHz" } (over the
//                  strokes where the value exists) },
//     "vsRef": only with --ref, this file minus the reference: { "f0Cents", "harmonicsDb": [10],
//              "centroidHz", "hnrDb", "attackMs", "decayMs", "t60S", "rmsDb", "peakDb",
//              "tailRmsDb", "tailFloorDb", "strokeRate" } }

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
        let base = ProcessInfo.processInfo.environment["TMPDIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("analyze-\(UUID().uuidString)")
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

// Hann-windowed, zero-padded to a power of two of at least `pad` times the length and fine
// enough for bins of at most maxBinHz.
func spectrum(_ x: ArraySlice<Float>, rate: Double, pad: Int = 4, maxBinHz: Double? = nil) -> Spectrum {
    let n = x.count
    let minSize = max(2, n * pad, maxBinHz.map { Int((rate / $0).rounded(.up)) } ?? 0)
    var size = 1, log2n: vDSP_Length = 0
    while size < minSize { size *= 2; log2n += 1 }
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

// The vertex of a parabola through (-1, a), (0, b), (1, c): (offset, value), the offset kept
// within +-0.5; no offset when b is not a maximum.
func parabola(_ a: Double, _ b: Double, _ c: Double) -> (offset: Double, value: Double) {
    let den = a - 2 * b + c
    let d = den < 0 ? min(0.5, max(-0.5, 0.5 * (a - c) / den)) : 0
    return (d, b - 0.25 * (a - c) * d)
}

// The strongest component within +-3 % of hz: (amplitude, Hz), refined by a parabola on dB
// unless the strongest bin is at the band's edge (then it is the edge's value). nil above Nyquist.
func peak(near hz: Double, in s: Spectrum) -> (amp: Double, hz: Double)? {
    let last = s.mag.count - 1
    guard hz * 1.03 < s.binHz * Double(last) else { return nil }
    let lo = max(1, Int((hz * 0.97 / s.binHz).rounded(.up))), hi = min(last - 1, Int((hz * 1.03 / s.binHz).rounded(.down)))
    guard lo <= hi else { return nil }
    var best = lo
    for k in lo...hi where s.mag[k] > s.mag[best] { best = k }
    guard best > lo, best < hi else { return (s.mag[best], Double(best) * s.binHz) }
    let v = parabola(db(amplitude: s.mag[best - 1]), db(amplitude: s.mag[best]), db(amplitude: s.mag[best + 1]))
    return (pow(10, v.value / 20), (Double(best) + v.offset) * s.binHz)
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
    var periodicity = min(1, vertex.value)
    var halved = false
    // Octave guard: the NCCF's peak near twice the lag (refined only when it lies inside lag2 +- 2)
    // and the halved pitch's odd harmonics (0.5, 1.5, ... 4.5 f) in the spectrum.
    let lag2 = Int((2 * period).rounded())
    if lag2 + 3 < n * 2 / 3, rate / (2 * period) >= fmin {
        let around = (-2...2).map { r.at(lag2 + $0) }
        let j = around.indices.max { around[$0] < around[$1] }!
        let top2 = j > 0 && j < 4 ? parabola(around[j - 1], around[j], around[j + 1]) : (offset: 0.0, value: around[j])
        let f = rate / period
        var strongest = 0.0, odd = 0.0
        for k in 1...10 { if let p = peak(near: Double(k) * f, in: s) { strongest = max(strongest, p.amp) } }
        for k in [1, 3, 5, 7, 9] { if let p = peak(near: Double(k) * f / 2, in: s) { odd += p.amp * p.amp } }
        let value2 = min(1, top2.value)
        if value2 > periodicity, value2 - periodicity >= 0.5 * (1 - periodicity),
           odd >= strongest * strongest * pow(10, -25.0 / 10) {
            period = Double(lag2 - 2 + j) + top2.offset
            periodicity = value2
            halved = true
        }
    }
    return Pitch(f0: rate / period, periodicity: periodicity, halved: halved)
}

// Onsets by the rectified complex-domain detection function (Bello et al. 2004, Dixon 2006):
// Hann frames of about 20 ms every 5 ms; for each bin whose magnitude grows, the distance from
// the value predicted by the two frames before (same magnitude, same phase advance). A new
// stroke breaks the prediction even where it hardly raises the level (a stroke into the ring of
// the ones before). Peaks: the highest within +-15 ms and at least 1 % of the file's highest;
// either 4 times the function's median within +-0.25 s (silent frames after the peak left
// out, so that a note's end does not lift the beating before it), or twice it where the level
// rises 6 dB within +-30 ms (a note out of silence); the level must rise at least 0.25 dB (a
// note-off or a decay does not count), to no more than 45 dB under the loudest. Of peaks closer
// than 40 ms the first is kept. The time: the peak's frame (refined by a parabola) plus 5 ms.
func detectOnsets(_ x: [Float], rate: Double, hop: Int, levels: [Double]) -> [Int] {
    var size = 1, log2n: vDSP_Length = 0
    while Double(size) < 0.02 * rate { size *= 2; log2n += 1 }
    let half = size / 2, n = x.count
    guard n > size, let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return [] }
    defer { vDSP_destroy_fftsetupD(setup) }
    let w = (0..<size).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size - 1)) }
    var mag1 = [Double](repeating: 0, count: half), ph1 = mag1, ph2 = mag1
    var buf = [Double](repeating: 0, count: size), re = [Double](repeating: 0, count: half), im = re
    var odf: [Double] = []
    var start = 0
    while start < n {
        for i in 0..<size { buf[i] = start + i < n ? Double(x[start + i]) * w[i] : 0 }
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                buf.withUnsafeBytes { raw in
                    vDSP_ctozD(raw.bindMemory(to: DSPDoubleComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        var d = 0.0
        for k in 1..<half {
            let m = (re[k] * re[k] + im[k] * im[k]).squareRoot(), ph = atan2(im[k], re[k])
            if m >= mag1[k] {
                let predicted = 2 * ph1[k] - ph2[k]
                d += max(0, m * m + mag1[k] * mag1[k] - 2 * m * mag1[k] * cos(ph - predicted)).squareRoot()
            }
            ph2[k] = ph1[k]; ph1[k] = ph; mag1[k] = m
        }
        odf.append(d)
        start += hop
    }
    guard let globalTop = odf.max(), globalTop > 0 else { return [] }
    let top = levels.max() ?? -200
    let frames = { (s: Double) in max(1, Int((s * rate / Double(hop)).rounded())) }
    let near = frames(0.015), mid = frames(0.25), rise = frames(0.030)
    let last = levels.count - 1
    var picked: [Int] = []
    for t in 0..<odf.count {
        let lo = max(0, t - near), hi = min(odf.count - 1, t + near)
        guard odf[t] > 0, odf[t] == odf[lo...hi].max(), odf[t] >= 0.01 * globalTop else { continue }
        // Against the local median: partials closer than the frame resolves beat in a steady low
        // tone and keep the function busy there, but a stroke stands far out of it.
        // (Silence after a note-off must not pull the median down; silence before is a real start.)
        let around = (max(0, t - mid)...min(odf.count - 1, t + mid)).filter { $0 <= t || levels[min(last, $0)] >= top - 45 }
        let ratio = odf[t] / max(1e-300, median(around.map { odf[$0] }) ?? 0)
        let before = t >= 1 ? levels[max(0, min(last, t - rise))...min(last, t - 1)].min() ?? -200 : -200
        let after = t + 1 <= last ? levels[(t + 1)...min(last, t + rise)].max() ?? -200 : -200
        guard after >= top - 45, after - before >= 0.25, ratio >= 4 || (ratio >= 2 && after - before >= 6) else { continue }
        if let first = picked.last, t - first < frames(0.040) { continue }   // one stroke: its first sign
        picked.append(t)
    }
    // The peak's frame refined by a parabola; the attack then lies about 5 ms into that frame
    // (measured on the skill's check renders: a 4 ms attack, strokes into a ringing tone).
    return picked.map { t in
        let d = t > 0 && t + 1 < odf.count ? parabola(odf[t - 1], odf[t], odf[t + 1]).offset : 0
        return min(n - 1, max(0, Int(((Double(t) + d) * Double(hop) + 0.005 * rate).rounded())))
    }
}

// One note or stroke: x[start..<end] (end = the next onset), measured as the file-level note is.
struct Note {
    var start = 0, end = 0
    var window = (0, 0)
    var pitch: Pitch?
    var fewPeriods = false
    var harmonicsDb: [Double?] = Array(repeating: nil, count: 10)
    var harmonicsHz: [Double?] = Array(repeating: nil, count: 10)
    var h1Db: Double?
    var centroidHz: Double?
    var hnrDb: Double?
    var peakDb = -200.0
    var noteTime: Double?
    var attackMs: Double?, decayMs: Double?, t60: Double?, t60Span: Double?
    var decayFitted = false
}

struct Frames {
    let levels: [Double]
    let hop: Int, win: Int
    let rate: Double
    var hopS: Double { Double(hop) / rate }
}

// A line through dB over time (least squares): the slope in dB/s and the span of the values.
func fitLine(_ lv: [Double], _ range: Range<Int>, hopS: Double) -> (slope: Double, span: Double)? {
    guard range.count >= 3 else { return nil }
    let ts = range.map { Double($0) * hopS }, ys = Array(lv[range])
    let mt = ts.reduce(0, +) / Double(ts.count), my = ys.reduce(0, +) / Double(ys.count)
    var sxy = 0.0, sxx = 0.0
    for i in 0..<ts.count { sxy += (ts[i] - mt) * (ys[i] - my); sxx += (ts[i] - mt) * (ts[i] - mt) }
    return sxx > 0 ? (sxy / sxx, (ys.max() ?? 0) - (ys.min() ?? 0)) : nil
}

// stroke: the note is one stroke of a phrase; when the next onset comes before the level has
// fallen 20 dB, the decay is extrapolated from a line through its frames after the peak (at
// least 50 ms of them falling at least 3 dB; decayFitted). The file-level note leaves it null.
func measureNote(_ x: [Float], frames fr: Frames, start: Int, end: Int, window: (Double, Double)?,
                 tailFloor: Double, options o: Options, attack: Bool, stroke: Bool = false) -> Note {
    let rate = fr.rate, lv = fr.levels, hopS = fr.hopS
    var note = Note(start: start, end: end)
    // Frames that lie wholly inside the note (at least one).
    let fs = min(lv.count - 1, Int((Double(start) / Double(fr.hop)).rounded(.up)))
    var fe = fs
    while fe + 1 < lv.count, (fe + 1) * fr.hop + fr.win <= end { fe += 1 }
    let localTop = lv[fs...fe].max() ?? -200
    let anchor: Int
    if let w = window {
        let a = max(fs, min(fe, Int(w.0 / hopS))), b = max(a, min(fe, Int(w.1 / hopS)))
        anchor = (a...b).max { lv[$0] < lv[$1] } ?? a
    } else {
        anchor = (fs...fe).first { lv[$0] >= localTop - 3 } ?? fs
    }
    var noteEnd = anchor
    while noteEnd + 1 <= fe, lv[noteEnd + 1] >= lv[anchor] - 12 { noteEnd += 1 }
    let peakFrame = (anchor...noteEnd).max { lv[$0] < lv[$1] } ?? anchor
    let noteTop = lv[peakFrame]
    note.noteTime = Double(peakFrame) * hopS + 0.010
    var peakAmp: Float = 0
    if end > start { vDSP_maxmgv(Array(x[start..<end]), 1, &peakAmp, vDSP_Length(end - start)) }
    note.peakDb = db(amplitude: Double(peakAmp))

    // Steady window: 20 ms after the anchor, for 200 ms, until a frame falls 12 dB under the
    // note's loudest or the next onset comes; at least 50 ms when the note is that long.
    var s0: Int, s1: Int
    if let w = window {
        s0 = max(0, min(x.count - 1, Int(w.0 * rate)))
        s1 = max(s0 + 1, min(x.count, Int(w.1 * rate)))
    } else {
        let wa = Double(anchor) * hopS + 0.020
        var g = Int((wa / hopS).rounded(.up))
        while g <= fe, lv[g] >= localTop - 12, Double(g) * hopS < wa + 0.2 { g += 1 }
        let wb = max(wa + 0.05, min(wa + 0.2, Double(g) * hopS))
        s0 = Int(wa * rate)
        s1 = min(end, x.count, Int(wb * rate))
        if s1 - s0 < Int(0.03 * rate) {   // a short stroke: all of it from the anchor
            s0 = max(start, Int(Double(anchor) * hopS * rate))
            s1 = end
        }
    }
    note.window = (s0, s1)
    if s1 - s0 >= 64 {
        let seg = x[s0..<s1]
        let spec = spectrum(seg, rate: rate, maxBinHz: 0.01 * o.fmin)
        note.centroidHz = centroid(spec)
        if let p = findPitch(seg, spectrum: spec, rate: rate, fmin: o.fmin, fmax: o.fmax) {
            note.pitch = p
            note.fewPeriods = Double(s1 - s0) / rate * p.f0 < 4
            let rr = min(max(p.periodicity, 1e-9), 1 - 1e-8)
            note.hnrDb = 10 * log10(rr / (1 - rr))
            if let h1 = peak(near: p.f0, in: spec) {
                note.h1Db = db(amplitude: h1.amp / 2.0.squareRoot())
                for k in 1...10 {
                    if let h = peak(near: Double(k) * p.f0, in: spec) {
                        note.harmonicsDb[k - 1] = db(amplitude: h.amp) - db(amplitude: h1.amp)
                        note.harmonicsHz[k - 1] = h.hz
                    }
                }
            }
        }
    }

    // Attack on 5 ms RMS every 1 ms, around the note's peak.
    if attack {
        let envHop = max(1, Int((0.001 * rate).rounded()))
        let envHopS = Double(envHop) / rate
        let env = frameLevels(x, win: max(1, Int((0.005 * rate).rounded())), hop: envHop)
        let e0 = min(env.count - 1, max(0, Int((Double(start) / rate - 0.05) / envHopS)))
        let e1 = max(e0, min(env.count - 1, Int((Double(noteEnd) * hopS + 0.020) / envHopS)))
        if let p = (e0...e1).max(by: { env[$0] < env[$1] }), env[p] > -200 {
            let envTop = env[p]
            if let a = env[e0..<p].lastIndex(where: { $0 <= envTop - 20 }),
               let b = env[a...].firstIndex(where: { $0 >= envTop - 3 }) {
                note.attackMs = Double(b - a) * envHopS * 1000
            }
        }
    }
    // Decay and T60 from the note's loudest frame, inside the note only.
    if noteTop > -200 {
        if let d = (peakFrame...fe).first(where: { lv[$0] <= noteTop - 20 }) {
            note.decayMs = Double(d - peakFrame) * hopS * 1000
        } else if stroke, Double(fe - peakFrame) * hopS >= 0.05,
                  let line = fitLine(lv, peakFrame..<(fe + 1), hopS: hopS), line.slope < 0, line.span >= 3 {
            note.decayMs = -20 / line.slope * 1000
            note.decayFitted = true
        }
        if let s = (peakFrame...fe).first(where: { lv[$0] < noteTop - 6 }) {
            let stop = max(noteTop - 60, tailFloor + 10)
            var e = s, low = lv[s]
            while e <= fe, lv[e] > stop, lv[e] < low + 6 { low = min(low, lv[e]); e += 1 }
            if let line = fitLine(lv, s..<e, hopS: hopS), line.slope < 0, line.span >= 12 {
                note.t60 = -60 / line.slope
                note.t60Span = line.span
            }
        }
    }
    return note
}

struct Measurement {
    var file: String
    var audio: Audio
    var duration: Double
    var peakDb: Double, peakTime: Double, rmsDb: Double
    var note: Note
    var onsets: [Int]
    var strokes: [Note]
    var tail: (start: Double, end: Double, rmsDb: Double, floorDb: Double, centroidHz: Double?)
    var strokeRate: Double? {
        guard onsets.count >= 2 else { return nil }
        let gaps = zip(onsets.dropFirst(), onsets).map { Double($0 - $1) / audio.rate }
        return 1 / median(gaps)!
    }
}

func median(_ v: [Double]) -> Double? {
    guard !v.isEmpty else { return nil }
    let s = v.sorted(), m = s.count / 2
    return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
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
    let fr = Frames(levels: frameLevels(x, win: win, hop: hop), hop: hop, win: win, rate: rate)
    let (ta, tb) = o.tail ?? (max(0, duration - 0.5), duration)
    let t0 = min(n - 1, Int(ta * rate)), t1 = max(t0 + 1, min(n, Int(tb * rate)))
    var tailMs: Float = 0
    vDSP_measqv(Array(x[t0..<t1]), 1, &tailMs, vDSP_Length(t1 - t0))
    let tailFrames = frameLevels(x, from: t0, to: t1, win: win, hop: hop)
    let tailSpectrum = spectrum(x[t0..<t1], rate: rate, pad: 1)
    let tail = (start: Double(t0) / rate, end: Double(t1) / rate, rmsDb: db(power: Double(tailMs)),
                floorDb: percentile(tailFrames, 0.10), centroidHz: tailMs > 0 ? centroid(tailSpectrum) : nil)

    // Onsets cut the file into strokes; each ends one frame before the next onset.
    let onsets = detectOnsets(x, rate: rate, hop: hop, levels: fr.levels)
    let bounds = onsets.isEmpty ? [(0, n)] : onsets.indices.map { i in
        (onsets[i], i + 1 < onsets.count ? max(onsets[i] + 1, onsets[i + 1] - hop) : n)
    }
    let strokes = onsets.isEmpty ? [] : bounds.map {
        measureNote(x, frames: fr, start: $0.0, end: $0.1, window: nil, tailFloor: tail.floorDb, options: o, attack: false,
                    stroke: true)
    }

    // The file-level note: the stroke holding the first frame within 3 dB of the loudest (with
    // --window, the stroke where the window starts); before the first onset, the start of the file.
    let top = fr.levels.max() ?? -200
    let at = o.window.map { Int($0.0 * rate) } ?? (fr.levels.firstIndex { $0 >= top - 3 } ?? 0) * hop + win
    // (A low note's first onset can read up to 30 ms after the frame that is already loud.)
    let k = onsets.lastIndex { $0 <= at } ?? onsets.firstIndex { $0 <= at + Int(0.03 * rate) }
    let noteStart = k.map { onsets[$0] } ?? 0
    let noteEnd = k.map { bounds[$0].1 } ?? (onsets.first.map { max(1, $0 - hop) } ?? n)
    let note = measureNote(x, frames: fr, start: noteStart, end: noteEnd, window: o.window, tailFloor: tail.floorDb,
                           options: o, attack: true)
    return Measurement(file: path, audio: audio, duration: duration, peakDb: db(amplitude: Double(peakAmp)),
                       peakTime: Double(peakIndex) / rate, rmsDb: db(power: Double(ms)), note: note,
                       onsets: onsets, strokes: strokes, tail: tail)
}

// ---- output ------------------------------------------------------------------------------------

func round(_ v: Double?, _ digits: Int) -> Any {
    guard let v, v.isFinite else { return NSNull() }
    let p = pow(10, Double(digits))
    return (v * p).rounded() / p
}

func seconds(_ samples: Int, _ rate: Double) -> Double { Double(samples) / rate }

func strokeJSON(_ s: Note, rate: Double) -> [String: Any] {
    ["startS": round(seconds(s.start, rate), 4), "endS": round(seconds(s.end, rate), 4), "f0Hz": round(s.pitch?.f0, 3),
     "peakDb": round(s.peakDb, 2), "decayMs": round(s.decayMs, 1), "decayFitted": s.decayFitted, "t60S": round(s.t60, 3),
     "centroidHz": round(s.centroidHz, 1)]
}

func strokeMedians(_ strokes: [Note]) -> [String: Double?] {
    ["f0Hz": median(strokes.compactMap { $0.pitch?.f0 }), "peakDb": median(strokes.map { $0.peakDb }),
     "decayMs": median(strokes.compactMap { $0.decayMs }), "t60S": median(strokes.compactMap { $0.t60 }),
     "centroidHz": median(strokes.compactMap { $0.centroidHz })]
}

func json(_ m: Measurement) -> [String: Any] {
    let n = m.note, rate = m.audio.rate
    let med = strokeMedians(m.strokes)
    var o: [String: Any] = [
        "file": m.file, "converted": m.audio.converted, "sampleRate": rate, "channels": m.audio.channels,
        "bits": m.audio.bits.map { $0 as Any } ?? NSNull(),
        "sampleFormat": m.audio.isFloat.map { ($0 ? "float" : "int") as Any } ?? NSNull(),
        "durationS": round(m.duration, 4), "peakDb": round(m.peakDb, 2), "peakTimeS": round(m.peakTime, 4),
        "rmsDb": round(m.rmsDb, 2),
        "noteS": [round(seconds(n.start, rate), 4), round(seconds(n.end, rate), 4)],
        "windowS": [round(seconds(n.window.0, rate), 4), round(seconds(n.window.1, rate), 4)],
        "fewPeriods": n.fewPeriods,
        "f0Hz": round(n.pitch?.f0, 3), "periodicity": round(n.pitch?.periodicity, 4),
        "octaveGuard": n.pitch.map { ($0.halved ? "halved" : "none") as Any } ?? NSNull(),
        "harmonicsDb": n.harmonicsDb.map { round($0, 2) }, "harmonicsHz": n.harmonicsHz.map { round($0, 2) },
        "h1Db": round(n.h1Db, 2), "centroidHz": round(n.centroidHz, 1),
        "centroidRatio": round(n.pitch.flatMap { p in n.centroidHz.map { $0 / p.f0 } }, 3),
        "hnrDb": round(n.hnrDb, 2), "noteTimeS": round(n.noteTime, 3),
        "attackMs": round(n.attackMs, 1), "decayMs": round(n.decayMs, 1),
        "t60S": round(n.t60, 3), "t60SpanDb": round(n.t60Span, 1),
        "onsets": m.onsets.map { round(seconds($0, rate), 4) },
        "strokeRate": round(m.strokeRate, 3),
        "strokes": ["count": m.strokes.count, "each": m.strokes.map { strokeJSON($0, rate: rate) },
                    "median": ["f0Hz": round(med["f0Hz"]!, 3), "peakDb": round(med["peakDb"]!, 2),
                               "decayMs": round(med["decayMs"]!, 1), "t60S": round(med["t60S"]!, 3),
                               "centroidHz": round(med["centroidHz"]!, 1)]] as [String: Any],
        "tail": ["startS": round(m.tail.start, 4), "endS": round(m.tail.end, 4), "rmsDb": round(m.tail.rmsDb, 2),
                 "floorDb": round(m.tail.floorDb, 2), "centroidHz": round(m.tail.centroidHz, 1)],
    ]
    if let p = n.pitch {
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
    let a = m.note, b = ref.note
    let cents: Double? = {
        guard let x = a.pitch?.f0, let y = b.pitch?.f0 else { return nil }
        return 1200 * log2(x / y)
    }()
    return [
        "f0Cents": round(cents, 1),
        "harmonicsDb": (0..<10).map { round(minus(a.harmonicsDb[$0], b.harmonicsDb[$0]), 2) },
        "centroidHz": round(minus(a.centroidHz, b.centroidHz), 1), "hnrDb": round(minus(a.hnrDb, b.hnrDb), 2),
        "attackMs": round(minus(a.attackMs, b.attackMs), 1), "decayMs": round(minus(a.decayMs, b.decayMs), 1),
        "t60S": round(minus(a.t60, b.t60), 3), "rmsDb": round(minus(m.rmsDb, ref.rmsDb), 2),
        "peakDb": round(minus(m.peakDb, ref.peakDb), 2), "tailRmsDb": round(minus(m.tail.rmsDb, ref.tail.rmsDb), 2),
        "tailFloorDb": round(minus(m.tail.floorDb, ref.tail.floorDb), 2),
        "strokeRate": round(minus(m.strokeRate, ref.strokeRate), 3),
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
    let a = m.audio, n = m.note, rate = a.rate
    var bits = a.bits.map { "\($0)-bit" } ?? "converted"
    if let f = a.isFloat { bits += f ? " float" : " int" }
    var lines = ["\(m.file)  \(fmt(a.rate, 0)) Hz, \(a.channels) ch, \(bits), \(fmt(m.duration, 2)) s"]
    lines.append("  level      peak \(fmt(m.peakDb, 1)) dBFS at \(fmt(m.peakTime, 3)) s, RMS \(fmt(m.rmsDb, 1)) dBFS")
    lines.append("  note       \(fmt(seconds(n.start, rate), 3))-\(fmt(seconds(n.end, rate), 3)) s, steady window \(fmt(seconds(n.window.0, rate), 3))-\(fmt(seconds(n.window.1, rate), 3)) s")
    if let p = n.pitch {
        let (name, cents) = noteName(p.f0)
        let guardText = p.halved ? ", octave guard halved" : ""
        lines.append("  f0         \(fmt(p.f0, 2)) Hz (\(name) \(signed(cents, 0)) c), periodicity \(fmt(p.periodicity, 3))\(guardText), HNR \(fmt(n.hnrDb, 1)) dB")
        let hs = n.harmonicsDb.enumerated().map { "H\($0.offset + 1) \(fmt($0.element, 1))" }
        lines.append("  harmonics  dB re H1: " + hs.joined(separator: "  "))
        lines.append("             H1 \(fmt(n.h1Db, 1)) dBFS")
        if n.fewPeriods {
            let periods = seconds(n.window.1 - n.window.0, rate) * p.f0
            lines.append("  note       the window holds \(fmt(periods, 1)) periods (under 4): harmonic levels and HNR are rough")
        }
    } else {
        lines.append("  f0         none (no stable pitch in the window)")
    }
    let ratio = n.pitch.flatMap { p in n.centroidHz.map { $0 / p.f0 } }
    lines.append("  centroid   \(fmt(n.centroidHz, 0, " Hz"))" + (ratio.map { " (\(fmt($0, 2)) x f0)" } ?? ""))
    lines.append("  envelope   peak at \(fmt(n.noteTime, 2)) s: attack \(fmt(n.attackMs, 0)) ms, decay to -20 dB \(fmt(n.decayMs, 0, " ms")), T60 \(fmt(n.t60, 2, " s"))" + (n.t60Span.map { " (fit over \(fmt($0, 0)) dB)" } ?? ""))
    if !m.strokes.isEmpty {
        let med = strokeMedians(m.strokes)
        let fitted = m.strokes.filter { $0.decayFitted }.count
        lines.append("  strokes    \(m.strokes.count), \(fmt(m.strokeRate, 2, " per s")); medians: f0 \(fmt(med["f0Hz"]!, 1, " Hz")), peak \(fmt(med["peakDb"]!, 1, " dBFS")), decay \(fmt(med["decayMs"]!, 0, " ms")) (\(fitted) of \(m.strokes.count) extrapolated), T60 \(fmt(med["t60S"]!, 2, " s")), centroid \(fmt(med["centroidHz"]!, 0, " Hz"))")
        let shown = m.onsets.prefix(16).map { fmt(seconds($0, rate), 3) }.joined(separator: " ")
        lines.append("             onsets \(shown)\(m.onsets.count > 16 ? " ..." : "") s")
    }
    lines.append("  tail       \(fmt(m.tail.start, 2))-\(fmt(m.tail.end, 2)) s: RMS \(fmt(m.tail.rmsDb, 1)) dBFS, floor \(fmt(m.tail.floorDb, 1)) dBFS, centroid \(fmt(m.tail.centroidHz, 0, " Hz"))")
    if let r = ref {
        let d = differences(m, r)
        func v(_ k: String) -> Double? { d[k] as? Double }
        let hs = (d["harmonicsDb"] as? [Any] ?? []).enumerated().map { "H\($0.offset + 1) \(signed($0.element as? Double, 1))" }
        lines.append("  vs ref     f0 \(signed(v("f0Cents"), 1)) c, centroid \(signed(v("centroidHz"), 0)) Hz, HNR \(signed(v("hnrDb"), 1)) dB, RMS \(signed(v("rmsDb"), 1)) dB, peak \(signed(v("peakDb"), 1)) dB, stroke rate \(signed(v("strokeRate"), 2)) per s")
        lines.append("             harmonics " + hs.joined(separator: "  "))
        lines.append("             attack \(signed(v("attackMs"), 0)) ms, decay \(signed(v("decayMs"), 0)) ms, T60 \(signed(v("t60S"), 2)) s, tail RMS \(signed(v("tailRmsDb"), 1)) dB, tail floor \(signed(v("tailFloorDb"), 1)) dB")
    }
    return lines.joined(separator: "\n")
}

// ---- main --------------------------------------------------------------------------------------

// The temporary folder goes also when the run is interrupted (Ctrl-C, kill, a closed terminal).
let signalSources: [DispatchSourceSignal] = [SIGINT, SIGTERM, SIGHUP].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    source.setEventHandler {
        cleanUp()
        exit(128 + sig)
    }
    source.resume()
    return source
}

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
    let top: [String: Any] = ["tool": "analyze.swift", "version": 2, "files": files, "ref": ref.map { json($0) as Any } ?? NSNull()]
    print(encode(top))
} else {
    if let r = ref { print("reference:\n" + plain(r, ref: nil) + "\n") }
    print(results.map { plain($0, ref: ref) }.joined(separator: "\n\n"))
}
