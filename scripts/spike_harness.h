// spike_harness.h - the shared part of a throwaway listening prototype (create-audio-plugin skill).
//
// A run's prototype, .planning/research/spike/<slug>_spike.cpp, holds only the instrument (a
// Params struct with the defaults, a Voice, one function per program) and its list of renders.
// Everything else is here: notes and scores, a voice pool that plays a score, deterministic
// randomness, a 24-bit WAV writer, and the command line. Copy this file next to the spike so the
// spike folder builds on its own; scripts/spike_example.cpp is the pattern to follow.
//
//   clang++ -std=c++17 -O2 <slug>_spike.cpp -o <slug>_spike
//   ./<slug>_spike <dir> [prefix...]     writes <dir>/<name>.wav for every render (or only those
//                                        whose name starts with one of the prefixes), then says
//                                        which listed references are in <dir>/references/
//   ./<slug>_spike --analyze [prefix] [--at seconds]
//                                        renders one render (the first that matches, default the
//                                        first of all) in memory and prints a quick harmonic table
//   ./<slug>_spike --list                prints the render names
//
// --analyze is a built-in check while tuning, so that no file has to be written and nothing but
// this header is needed. It uses the same rules as scripts/analyze.swift (steady window, pitch
// first by normalised autocorrelation with the octave guard, then H1..H10 read at that pitch),
// with a direct DFT instead of an FFT. analyze.swift on the written WAVs is the measurement that
// goes into reports and is compared with the recordings.
//
// Conventions:
//   - mono, float samples, default 48 kHz (kRate); every helper takes the rate where it matters
//   - keys are MIDI note numbers (60 = C4, 69 = A4 = 440 Hz), velocities 0..1, times in seconds
//   - an Event with dur < 0 is a stroke: no note-off is sent, the voice rings out by itself
//   - dBFS = 20 log10(RMS) with full scale 1.0 (a full-scale sine reads -3.0 dBFS); -200 stands
//     for digital silence
//   - randomness only from std::mt19937 seeded explicitly (seeded(), seedOf()) and turned into
//     numbers by uniform()/white() here, because std's distributions differ between libraries:
//     the same source gives the same files on every machine
//   - the WAV writer does not normalise; call normalize() in the spike's render function
//     (-1 dBFS peak, so that the listener compares colour, not level)
//   - nothing is written outside <dir>; the references folder is never created, only looked at

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <random>
#include <string>
#include <string_view>
#include <vector>

namespace spike {

inline constexpr double kPi = 3.14159265358979323846;
inline constexpr double kRate = 48000.0;  // default sample rate, Hz
inline constexpr double kLead = 0.2;      // s of silence before a helper's first event
inline constexpr double kTail = 2.0;      // s rendered after the last note ends (long tails)

using Samples = std::vector<float>;

inline double noteHz(double key) { return 440.0 * std::pow(2.0, (key - 69.0) / 12.0); }
inline double dbToGain(double db) { return db <= -150.0 ? 0.0 : std::pow(10.0, db / 20.0); }
inline double gainToDb(double gain) { return gain > 1e-10 ? 20.0 * std::log10(gain) : -200.0; }

// ---- randomness -------------------------------------------------------------------------------

// FNV-1a of a text: a seed per render or per part that does not move when renders are reordered.
inline uint32_t seedOf(std::string_view text)
{
    uint32_t h = 2166136261u;
    for (char c : text) { h ^= uint8_t(c); h *= 16777619u; }
    return h;
}

inline std::mt19937 seeded(uint32_t seed) { return std::mt19937(seed); }
inline std::mt19937 seeded(std::string_view text) { return std::mt19937(seedOf(text)); }

// Uniform in [0, 1) from the top 24 bits, the same on every platform.
inline double uniform(std::mt19937& rng) { return double(rng() >> 8) * (1.0 / 16777216.0); }

// White noise with unit RMS (uniform, so its peaks are +-1.73).
inline double white(std::mt19937& rng) { return (2.0 * uniform(rng) - 1.0) * 1.7320508075688772; }

// ---- scores -----------------------------------------------------------------------------------

struct Event
{
    double time;    // s
    int key;        // MIDI note number
    float vel;      // 0..1
    double dur;     // s until the note-off; < 0 = a stroke (no note-off)
    int part = 0;   // which voice prototype plays it (a program, a pad, a drum of a kit)
};

struct Score
{
    std::vector<Event> events;
    double length = 0;  // s rendered

    // End of the last note (a stroke counts from its start).
    double lastEnd() const
    {
        double end = 0;
        for (const Event& e : events) end = std::max(end, e.time + std::max(0.0, e.dur));
        return end;
    }
    // The render lasts until `seconds` after the last note ends.
    Score& withTail(double seconds) { length = lastEnd() + seconds; return *this; }
    // Every event is played by voice prototype `p`.
    Score& onPart(int p) { for (Event& e : events) e.part = p; return *this; }
    // Later by dt seconds (length too).
    Score shifted(double dt) const
    {
        Score s = *this;
        for (Event& e : s.events) e.time += dt;
        s.length += dt;
        return s;
    }
    // Both scores at once; the longer length wins.
    Score& add(const Score& other)
    {
        events.insert(events.end(), other.events.begin(), other.events.end());
        length = std::max(length, other.length);
        return *this;
    }
};

inline Score operator+(Score a, const Score& b) { return a.add(b); }

// One note held for dur seconds.
inline Score note(double t, int key, float vel, double dur)
{
    Score s;
    s.events.push_back({t, key, vel, dur});
    return s.withTail(kTail);
}

// One stroke: no note-off, the voice rings out by itself.
inline Score stroke(double t, int key, float vel)
{
    Score s;
    s.events.push_back({t, key, vel, -1.0});
    return s.withTail(kTail);
}

// The keys together, each spreadMs after the one before (a strum; 0 = struck at once).
inline Score chord(double t, const std::vector<int>& keys, float vel, double dur, double spreadMs = 0)
{
    Score s;
    for (size_t i = 0; i < keys.size(); ++i)
        s.events.push_back({t + double(i) * spreadMs / 1000.0, keys[i], vel, dur});
    return s.withTail(kTail);
}

// One long note after kLead: for sustain, decay and the tail's noise floor.
inline Score held(int key, float vel, double dur) { return note(kLead, key, vel, dur); }

// The keys one after another, every `step` seconds, each held for `dur` (< 0: strokes).
inline Score phrase(double startT, const std::vector<int>& keys, double step, double dur, float vel = 0.8f)
{
    Score s;
    for (size_t i = 0; i < keys.size(); ++i)
        s.events.push_back({startT + double(i) * step, keys[i], vel, dur});
    return s.withTail(kTail);
}

// ---- playing a score --------------------------------------------------------------------------

// Plays a score on a pool of copies of the parts' voice prototypes (event.part picks one).
// A new event takes a free voice; when maxVoices are busy, the oldest is cut and reused. A Voice
// needs:
//   void strike(const Event& e, std::mt19937& rng);   start a note (the pool's seeded generator)
//   void release();                                   the note-off
//   float process();                                  the next sample
//   bool active() const;                              false once it is silent for good
template <class Voice>
Samples play(const Score& score, const std::vector<Voice>& parts, double rate = kRate,
             uint32_t seed = 1, size_t maxVoices = 32)
{
    struct Off { double time; size_t slot; uint64_t gen; };
    std::vector<Event> events = score.events;
    std::stable_sort(events.begin(), events.end(), [](const Event& a, const Event& b) { return a.time < b.time; });
    std::vector<Off> offs;
    std::vector<Voice> voices;
    std::vector<uint64_t> gens;  // which strike a slot is playing (a note-off finds only its own)
    uint64_t counter = 0;
    std::mt19937 rng = seeded(seed);
    const size_t n = size_t(std::max(0.0, score.length) * rate + 0.5);
    Samples out(n, 0.0f);
    size_t next = 0;
    for (size_t i = 0; i < n; ++i)
    {
        const double now = double(i) / rate;
        for (; next < events.size() && events[next].time <= now; ++next)
        {
            const Event& e = events[next];
            if (e.part < 0 || size_t(e.part) >= parts.size()) continue;
            size_t slot = voices.size();
            for (size_t v = 0; v < voices.size(); ++v)
                if (!voices[v].active()) { slot = v; break; }
            if (slot == voices.size() && voices.size() >= maxVoices)
                slot = size_t(std::min_element(gens.begin(), gens.end()) - gens.begin());
            if (slot == voices.size()) { voices.push_back(parts[size_t(e.part)]); gens.push_back(0); }
            else voices[slot] = parts[size_t(e.part)];
            gens[slot] = ++counter;
            voices[slot].strike(e, rng);
            if (e.dur >= 0) offs.push_back({e.time + e.dur, slot, counter});
        }
        for (size_t k = 0; k < offs.size();)
        {
            if (offs[k].time <= now)
            {
                if (gens[offs[k].slot] == offs[k].gen) voices[offs[k].slot].release();
                offs.erase(offs.begin() + std::ptrdiff_t(k));
            }
            else ++k;
        }
        float sum = 0.0f;
        for (Voice& v : voices)
            if (v.active()) sum += v.process();
        out[i] = sum;
    }
    return out;
}

template <class Voice>
Samples play(const Score& score, const Voice& voice, double rate = kRate, uint32_t seed = 1,
             size_t maxVoices = 32)
{
    return play(score, std::vector<Voice>{voice}, rate, seed, maxVoices);
}

// ---- levels and files -------------------------------------------------------------------------

inline double peakDb(const Samples& x)
{
    float peak = 0.0f;
    for (float v : x) peak = std::max(peak, std::fabs(v));
    return gainToDb(peak);
}

// Scales x so that its peak is at peakDbfs; returns the gain applied in dB. Silence stays silent.
inline double normalize(Samples& x, double peakDbfs = -1.0)
{
    const double now = peakDb(x);
    if (now <= -200.0) return 0.0;
    const double gainDb = peakDbfs - now;
    const float g = float(dbToGain(gainDb));
    for (float& v : x) v *= g;
    return gainDb;
}

// Mono 24-bit PCM WAV. Samples beyond +-1 are clipped and counted on stderr. Returns false when
// the file cannot be written.
inline bool writeWav(const std::string& path, const Samples& samples, double rate = kRate)
{
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) { std::perror(path.c_str()); return false; }
    const uint32_t sr = uint32_t(std::lround(rate)), n = uint32_t(samples.size()), dataBytes = n * 3;
    auto u32 = [&](uint32_t v) { uint8_t b[4] = {uint8_t(v), uint8_t(v >> 8), uint8_t(v >> 16), uint8_t(v >> 24)}; std::fwrite(b, 1, 4, f); };
    auto u16 = [&](uint16_t v) { uint8_t b[2] = {uint8_t(v), uint8_t(v >> 8)}; std::fwrite(b, 1, 2, f); };
    std::fwrite("RIFF", 1, 4, f); u32(36 + dataBytes); std::fwrite("WAVE", 1, 4, f);
    std::fwrite("fmt ", 1, 4, f); u32(16); u16(1); u16(1); u32(sr); u32(sr * 3); u16(3); u16(24);
    std::fwrite("data", 1, 4, f); u32(dataBytes);
    size_t clipped = 0;
    std::vector<uint8_t> bytes(size_t(n) * 3);
    for (size_t i = 0; i < n; ++i)
    {
        double v = samples[i];
        if (v > 1.0 || v < -1.0) { ++clipped; v = std::clamp(v, -1.0, 1.0); }
        const int32_t s = int32_t(std::lround(v * 8388607.0));
        bytes[3 * i] = uint8_t(s & 0xff);
        bytes[3 * i + 1] = uint8_t((s >> 8) & 0xff);
        bytes[3 * i + 2] = uint8_t((s >> 16) & 0xff);
    }
    const bool ok = std::fwrite(bytes.data(), 1, bytes.size(), f) == bytes.size();
    std::fclose(f);
    if (clipped) std::fprintf(stderr, "warning: %s: %zu samples clipped\n", path.c_str(), clipped);
    if (!ok) std::fprintf(stderr, "error: %s: short write\n", path.c_str());
    return ok;
}

// ---- renders ----------------------------------------------------------------------------------

struct Render
{
    std::string name;               // file name without .wav: "01_default", "02_ring_A_short"
    std::function<Samples()> make;  // renders it (at the rate given to renderAll / run)
};
using Renders = std::vector<Render>;

// A recording to compare with, put by hand into <dir>/references/ (gitignored, never committed).
struct Reference
{
    std::string file;         // name inside references/, e.g. "R1_<instrument>_<player>.wav"
    std::string source;       // URL, author and licence (CC0 / CC BY only)
    std::string compareWith;  // which renders it answers, e.g. "01, 02"
};

inline bool matches(const std::string& name, const std::vector<std::string>& prefixes)
{
    if (prefixes.empty()) return true;
    for (const std::string& p : prefixes)
        if (name.compare(0, p.size(), p) == 0) return true;
    return false;
}

// Writes <dir>/<name>.wav for every render whose name starts with one of the prefixes (all when
// there are none). Returns 0, or 1 when a name is used twice or a file cannot be written.
inline int renderAll(const std::string& dir, const Renders& renders, double rate = kRate,
                     const std::vector<std::string>& prefixes = {})
{
    for (size_t i = 0; i < renders.size(); ++i)
        for (size_t j = i + 1; j < renders.size(); ++j)
            if (renders[i].name == renders[j].name)
            {
                std::fprintf(stderr, "error: render name used twice: %s\n", renders[i].name.c_str());
                return 1;
            }
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    if (ec) { std::fprintf(stderr, "error: cannot create %s: %s\n", dir.c_str(), ec.message().c_str()); return 1; }
    int written = 0;
    for (const Render& r : renders)
    {
        if (!matches(r.name, prefixes)) continue;
        const Samples x = r.make();
        if (!writeWav(dir + "/" + r.name + ".wav", x, rate)) return 1;
        std::printf("%-44s %6.2f s  peak %6.1f dBFS\n", (r.name + ".wav").c_str(), double(x.size()) / rate, peakDb(x));
        ++written;
    }
    if (written == 0) { std::fprintf(stderr, "error: no render matches\n"); return 1; }
    return 0;
}

// ---- the quick analysis (--analyze) -----------------------------------------------------------

namespace detail {

// dB of the 20 ms frames every 5 ms (frame i starts at i * 5 ms).
inline std::vector<double> frameLevels(const Samples& x, double rate, size_t from = 0, size_t to = SIZE_MAX)
{
    to = std::min(to, x.size());
    const size_t win = size_t(0.020 * rate), hop = size_t(0.005 * rate);
    std::vector<double> lv;
    for (size_t s = from; s + win <= to || (lv.empty() && s < to); s += hop)
    {
        const size_t e = std::min(to, s + win);
        double sum = 0;
        for (size_t i = s; i < e; ++i) sum += double(x[i]) * x[i];
        lv.push_back(sum > 0 ? 10.0 * std::log10(sum / double(e - s)) : -200.0);
    }
    return lv;
}

// Hann-windowed amplitude of the strongest component within +-3 % of hz (0.1 % steps).
inline double levelNear(const std::vector<double>& w, const std::vector<double>& seg, double rate,
                        double hz, double* found = nullptr)
{
    double best = 0, bestHz = hz, wsum = 0;
    for (double v : w) wsum += v;
    for (int step = -30; step <= 30; ++step)
    {
        const double f = hz * (1.0 + step * 0.001);
        if (f <= 0 || f >= rate / 2) continue;
        double re = 0, im = 0;
        const double d = 2 * kPi * f / rate;
        for (size_t i = 0; i < seg.size(); ++i)
        {
            re += w[i] * seg[i] * std::cos(d * double(i));
            im -= w[i] * seg[i] * std::sin(d * double(i));
        }
        const double a = 2.0 * std::sqrt(re * re + im * im) / wsum;
        if (a > best) { best = a; bestHz = f; }
    }
    if (found) *found = bestHz;
    return best;
}

}  // namespace detail

// Prints the steady window, f0, H1..H10 re H1, the peak and the RMS of the last 0.5 s.
// Returns 1 when no pitch is found.
inline int quickAnalyze(const std::string& name, const Samples& x, double rate, double at = -1)
{
    using namespace detail;
    std::printf("%s  (quick check; scripts/analyze.swift on the WAV is the measurement)\n", name.c_str());
    if (x.empty()) { std::printf("empty render\n"); return 1; }
    // Steady window: 20 ms after the first frame within 3 dB of the loudest, for 200 ms or until
    // a frame falls 12 dB under the loudest (at least 50 ms); --at t: t .. t + 0.2 s.
    const std::vector<double> lv = frameLevels(x, rate);
    const double hop = 0.005;
    double from = at, to = at + 0.2;
    if (at < 0)
    {
        const double top = *std::max_element(lv.begin(), lv.end());
        size_t f = 0;
        while (f < lv.size() && lv[f] < top - 3) ++f;
        from = double(f) * hop + 0.020;
        size_t g = size_t(std::ceil(from / hop));
        while (g < lv.size() && lv[g] >= top - 12 && double(g) * hop < from + 0.2) ++g;
        to = std::max(from + 0.05, std::min(from + 0.2, double(g) * hop));
    }
    size_t start = size_t(from * rate), end = std::min(x.size(), size_t(to * rate));
    if (start >= end) start = end > size_t(0.05 * rate) ? end - size_t(0.05 * rate) : 0;
    std::printf("window %.3f-%.3f s\n", double(start) / rate, double(end) / rate);
    std::vector<double> seg(x.begin() + std::ptrdiff_t(start), x.begin() + std::ptrdiff_t(end));
    const size_t n = seg.size();

    // Pitch first: normalised autocorrelation over 30..2000 Hz; the first peak within 90 % of the
    // highest (no octave too low), halved when twice the lag fits better and the spectrum has a
    // component at half the pitch (no octave too high).
    std::vector<double> cum(n + 1, 0.0);
    for (size_t i = 0; i < n; ++i) cum[i + 1] = cum[i] + seg[i] * seg[i];
    auto r = [&](size_t lag) {
        if (lag >= n) return 0.0;
        double dot = 0;
        for (size_t i = 0; i + lag < n; ++i) dot += seg[i] * seg[i + lag];
        const double e = std::sqrt(cum[n - lag] * (cum[n] - cum[lag]));
        return e > 0 ? dot / e : 0.0;
    };
    const size_t minLag = size_t(rate / 2000.0), maxLag = std::min(size_t(rate / 30.0) + 1, n / 2);
    std::vector<double> rs(maxLag + 2, 0.0);
    for (size_t l = minLag; l <= maxLag + 1 && l < n; ++l) rs[l] = r(l);
    double top = -1;
    for (size_t l = minLag + 1; l <= maxLag; ++l)
        if (rs[l] > rs[l - 1] && rs[l] >= rs[l + 1]) top = std::max(top, rs[l]);
    if (top < 0.5) { std::printf("f0 none (periodicity %.2f)\n", top); return 1; }
    size_t lag = 0;
    for (size_t l = minLag + 1; l <= maxLag; ++l)
        if (rs[l] > rs[l - 1] && rs[l] >= rs[l + 1] && rs[l] >= 0.9 * top) { lag = l; break; }
    // The top of a parabola through the lags l - 1, l, l + 1: the period and the NCCF there.
    auto refine = [&](size_t l, double a, double b, double c, double* value) {
        const double den = a - 2 * b + c;
        const double d = den < 0 ? 0.5 * (a - c) / den : 0.0;
        *value = std::min(1.0, b - 0.25 * (a - c) * d);
        return double(l) + d;
    };
    double periodicity = 0;
    double period = refine(lag, rs[lag - 1], rs[lag], rs[lag + 1], &periodicity);
    std::vector<double> w(n);
    for (size_t i = 0; i < n; ++i) w[i] = 0.5 - 0.5 * std::cos(2 * kPi * double(i) / double(n - 1));
    const size_t lag2 = size_t(std::lround(2 * period));
    if (lag2 + 1 < n * 2 / 3 && rate / (2 * period) >= 30.0)
    {
        const double a = r(lag2 - 1), b = r(lag2), c = r(lag2 + 1);
        double strongest = 0;
        for (int k = 1; k <= 10; ++k) strongest = std::max(strongest, levelNear(w, seg, rate, k * rate / period));
        const double half = levelNear(w, seg, rate, rate / (2 * period));
        double top2 = 0;
        const double period2 = refine(lag2, a, b, c, &top2);
        if (top2 > periodicity && top2 - periodicity >= 0.5 * (1 - periodicity) && half > strongest * 0.01)
        {
            period = period2;
            periodicity = top2;
            std::printf("octave guard: halved\n");
        }
    }
    const double f0 = rate / period;
    std::printf("f0 %.3f Hz  periodicity %.4f\n", f0, periodicity);
    double h1 = 0;
    for (int k = 1; k <= 10; ++k)
    {
        if (k * f0 * 1.03 >= rate / 2) break;
        double hz = 0;
        const double a = levelNear(w, seg, rate, k * f0, &hz);
        if (k == 1) h1 = a;
        std::printf("H%d %.2f dB re H1  %.1f Hz\n", k, gainToDb(a) - gainToDb(h1), hz);
    }
    std::printf("peak %.2f dBFS\n", peakDb(x));
    const size_t tail = std::min(x.size(), size_t(0.5 * rate));
    double sum = 0;
    for (size_t i = x.size() - tail; i < x.size(); ++i) sum += double(x[i]) * x[i];
    std::printf("tail %.1f dBFS (RMS of the last %.2f s)\n", tail && sum > 0 ? 10 * std::log10(sum / double(tail)) : -200.0,
                double(tail) / rate);
    return 0;
}

// ---- the main helper --------------------------------------------------------------------------

// The spike's whole main():  int main(int argc, char** argv) { return spike::run(argc, argv, renders(), references()); }
inline int run(int argc, char** argv, const Renders& renders, const std::vector<Reference>& references = {},
               double rate = kRate)
{
    const char* self = argc > 0 ? argv[0] : "spike";
    auto usage = [&] {
        std::fprintf(stderr,
                     "usage: %s <dir> [prefix...]     write the renders (those whose name starts with a prefix)\n"
                     "       %s --analyze [prefix] [--at seconds]   quick harmonic table of one render\n"
                     "       %s --list                list the render names\n",
                     self, self, self);
        return 2;
    };
    if (argc < 2) return usage();
    const std::string first = argv[1];
    if (first == "--list")
    {
        for (const Render& r : renders) std::printf("%s\n", r.name.c_str());
        return 0;
    }
    if (first == "--analyze")
    {
        std::string prefix;
        double at = -1;
        for (int i = 2; i < argc; ++i)
        {
            const std::string a = argv[i];
            if (a == "--at" && i + 1 < argc) at = std::atof(argv[++i]);
            else if (!a.empty() && a[0] != '-' && prefix.empty()) prefix = a;
            else return usage();
        }
        for (const Render& r : renders)
            if (prefix.empty() || r.name.compare(0, prefix.size(), prefix) == 0)
                return quickAnalyze(r.name, r.make(), rate, at);
        std::fprintf(stderr, "error: no render starts with %s\n", prefix.c_str());
        return 1;
    }
    if (first.empty() || first[0] == '-') return usage();
    std::vector<std::string> prefixes;
    for (int i = 2; i < argc; ++i) prefixes.push_back(argv[i]);
    const int status = renderAll(first, renders, rate, prefixes);
    if (status != 0 || references.empty()) return status;
    std::printf("references (%s/references/, gitignored, never committed):\n", first.c_str());
    for (const Reference& ref : references)
    {
        const bool there = std::filesystem::exists(first + "/references/" + ref.file);
        std::printf("  %-8s %s  compare with %s  (%s)\n", there ? "present" : "MISSING", ref.file.c_str(),
                    ref.compareWith.c_str(), ref.source.c_str());
    }
    return 0;
}

}  // namespace spike
