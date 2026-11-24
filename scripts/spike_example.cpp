// spike_example.cpp - EXAMPLE listening prototype written against spike_harness.h (not product code).
//
// The pattern a run's .planning/research/spike/<slug>_spike.cpp follows: only the instrument and
// its renders are new, everything else is the harness. The "instrument" here is a toy struck bar:
//   strike  a short attack ramp, then each partial rings out on its own (upper ones faster)
//   colour  partials k = 1..16 at k * f0 * sqrt(1 + B k^2), falling tiltDb per octave, the
//           fundamental set apart by fundamentalDb; velocity brightens and adds level
//   release a note-off damps the bar (releaseMs T60), and the voice goes silent for good
// A real spike takes its model and starting numbers from the research report's "Recommendation
// for the engine", and one render group per "Question for the user's ear".
//
// Renders 48 kHz / 24-bit mono WAV files, peak-normalised to -1 dBFS:
//   00_check_*   renders with a known answer, for checking the analysis chain (not for the ear):
//                the score helpers' tone, noise in a tail, a weak fundamental, weak odd partials,
//                a low short stroke, a groove and one of its strokes, a hum an octave under
//   01..06       one group per question, decisive question first, each with a long tail
//   P01_*        one render per planned program
//
//   clang++ -std=c++17 -O2 spike_example.cpp -o spike_example && ./spike_example <outdir>
//   ./spike_example --analyze 01      quick harmonic table of 01_default

#include "spike_harness.h"

#include <array>

using namespace spike;

struct Params
{
    // Strike
    float attackMs = 4.0f;       // ms from silence to full level
    float ring = 1.8f;           // s, T60 of the fundamental while held (0 = sustains, an organ)
    float damping = 0.8f;        // partial k rings 1 / (1 + damping (k - 1)) as long
    float releaseMs = 150.0f;    // ms, T60 after the note-off
    // Colour
    float tiltDb = -6.0f;        // dB per octave above the fundamental, at full velocity
    float fundamentalDb = 0.0f;  // the fundamental against the tilt
    float stretch = 0.0003f;     // inharmonicity B
    float velBright = 6.0f;      // dB per octave darker at velocity 0 than at velocity 1
    float vary = 0.5f;           // dB rms of strike-to-strike level spread
    float levelDb = -12.0f;
};

struct Voice
{
    static constexpr size_t kPartials = 16;
    const Params* p = nullptr;
    double rate = kRate;
    std::array<double, kPartials> phase{}, inc{}, amp{}, decay{};
    double env = 0, attackStep = 0, releaseMul = 1;
    bool on = false, releasing = false;

    Voice(const Params& params, double sampleRate) : p(&params), rate(sampleRate) {}

    void strike(const Event& e, std::mt19937& rng)
    {
        const double f0 = noteHz(e.key);
        const double tilt = p->tiltDb - p->velBright * (1.0 - e.vel);
        const double level = p->levelDb + 20.0 * std::log10(0.2 + 0.8 * e.vel) + p->vary * white(rng);
        for (size_t i = 0; i < kPartials; ++i)
        {
            const double k = double(i + 1);
            const double hz = k * f0 * std::sqrt(1.0 + p->stretch * k * k);
            const double db = level + tilt * std::log2(k) + (i == 0 ? p->fundamentalDb : 0.0);
            amp[i] = hz < 0.45 * rate ? dbToGain(db) : 0.0;
            inc[i] = 2 * kPi * hz / rate;
            phase[i] = 2 * kPi * uniform(rng);
            const double t60 = p->ring / (1.0 + p->damping * (k - 1.0));
            decay[i] = p->ring > 0 ? std::pow(10.0, -3.0 / (t60 * rate)) : 1.0;
        }
        env = 0;
        attackStep = 1.0 / std::max(1.0, p->attackMs * 0.001 * rate);
        releaseMul = std::pow(10.0, -3.0 / (std::max(1.0f, p->releaseMs) * 0.001 * rate));
        on = true;
        releasing = false;
    }

    void release() { releasing = true; }

    float process()
    {
        if (releasing) env *= releaseMul;
        else env = std::min(1.0, env + attackStep);
        double s = 0;
        for (size_t i = 0; i < kPartials; ++i)
        {
            s += amp[i] * std::sin(phase[i]);
            phase[i] += inc[i];
            if (phase[i] > 2 * kPi) phase[i] -= 2 * kPi;
            amp[i] *= decay[i];
        }
        if ((releasing && env < 1e-7) || (p->ring > 0 && amp[0] * env < 1e-7 && env >= 1.0)) on = false;
        return float(s * env);
    }

    bool active() const { return on; }
};

// Programs: one function each, the defaults changed only where the program differs.
static Params softMallet()
{
    Params p;
    p.attackMs = 12;
    p.tiltDb = -12;
    p.ring = 2.6f;
    p.damping = 1.4f;
    return p;
}

// The spike's render function: play, then peak-normalise to -1 dBFS.
static Samples render(const Score& s, const Params& p, uint32_t seed = 1)
{
    Samples x = play(s, Voice(p, kRate), kRate, seed);
    normalize(x);
    return x;
}

// One stroke, then a short phrase: what every question group plays.
static Score strokeThenPhrase(int key)
{
    return stroke(kLead, key, 0.9f) + phrase(2.5, {key, key + 4, key + 7, key + 12, key + 7, key + 4, key}, 0.3, 0.25);
}

// Known answers: 220 Hz, H2 6 dB under H1, a sustained tone and then 1 s of digital silence.
static Params checkTone()
{
    Params p;
    p.ring = 0;
    p.damping = 0;
    p.stretch = 0;
    p.vary = 0;
    p.attackMs = 8;
    p.releaseMs = 30;
    return p;
}

// Known answers for the segmentation: one decay rate for every partial, so that the slope of a
// stroke cut short by the next one says its decay exactly.
static Params singleRate()
{
    Params p;
    p.damping = 0;
    p.stretch = 0;
    p.vary = 0;
    return p;
}

static Renders renders()
{
    const Params D;
    const int A3 = 57, C4 = 60;
    auto with = [D](auto change) { Params p = D; change(p); return p; };
    const Score check = held(A3, 1.0f, 1.5).withTail(1.0);
    return {
        {"00_check_A_tone_220Hz", [=] { return render(check, checkTone()); }},
        {"00_check_B_noise_tail", [=] {
             Samples x = render(check, checkTone());
             std::mt19937 rng = seeded("00_check_B_noise_tail");
             const double g = dbToGain(-60.0);  // white noise at -60 dBFS RMS in the last second
             for (size_t i = x.size() - size_t(kRate); i < x.size(); ++i) x[i] += float(g * white(rng));
             return x;
         }},
        {"00_check_C_weak_fundamental", [=] {
             Params p = checkTone();
             p.fundamentalDb = -26;  // H1 20 dB under H2: the pitch is still 220 Hz
             return render(check, p);
         }},
        {"00_check_D_even_partials", [=] {
             // Written out, not played: 220 Hz whose odd partials are weak (H1 -20 dB, H3, H5 ...
             // -40 dB re H2), so the waveform nearly repeats at 440 Hz; the octave guard must halve.
             Samples x(size_t(2.7 * kRate), 0.0f);
             for (size_t i = size_t(kLead * kRate); i < size_t(1.7 * kRate); ++i)
                 for (int k = 1; k <= 10; ++k)
                     x[i] += float(dbToGain(k == 1 ? -20 : k % 2 ? -40 : -6.0 * std::log2(k / 2.0)) *
                                   std::sin(2 * kPi * 220.0 * k * double(i) / kRate));
             normalize(x);
             return x;
         }},
        {"00_check_E_low_short_stroke", [=] {
             // E1 (41 Hz) dying in 0.25 s: the window holds two periods (fewPeriods).
             return render(stroke(kLead, 28, 0.9f), with([](Params& p) { p.ring = 0.25f; p.fundamentalDb = -10; }));
         }},
        {"00_check_F_groove", [=] {
             // 16 C3 strokes every 150 ms, accents on the beats: 16 onsets, 6.67 strokes per s.
             Score s;
             for (int i = 0; i < 16; ++i) s = s + stroke(kLead + 0.15 * i, 48, i % 4 == 0 ? 0.95f : 0.75f);
             return render(s, singleRate());
         }},
        {"00_check_G_one_stroke", [=] { return render(stroke(kLead, 48, 0.95f), singleRate()); }},
        {"00_check_H_hum_an_octave_under", [=] {
             // G2 with a 49 Hz hum at -45 dBFS: the pitch is still 98 Hz.
             Samples x = render(held(43, 1.0f, 1.5).withTail(1.0), checkTone());
             for (size_t i = 0; i < x.size(); ++i)
                 x[i] += float(dbToGain(-45) * std::sin(2 * kPi * 49.0 * double(i) / kRate));
             return x;
         }},

        // 01: the decisive question first - a struck bar or a synthesizer?
        {"01_default", [=] { return render(strokeThenPhrase(C4), D); }},
        // 02: how long it rings
        {"02_ring_A_0.6s", [=] { return render(strokeThenPhrase(C4), with([](Params& p) { p.ring = 0.6f; })); }},
        {"02_ring_B_1.8s_default", [=] { return render(strokeThenPhrase(C4), D); }},
        {"02_ring_C_4s", [=] { return render(strokeThenPhrase(C4), with([](Params& p) { p.ring = 4.0f; })); }},
        // 03: how bright
        {"03_tilt_A_-3dB_bright", [=] { return render(strokeThenPhrase(C4), with([](Params& p) { p.tiltDb = -3; })); }},
        {"03_tilt_B_-6dB_default", [=] { return render(strokeThenPhrase(C4), D); }},
        {"03_tilt_C_-12dB_dark", [=] { return render(strokeThenPhrase(C4), with([](Params& p) { p.tiltDb = -12; })); }},
        // 04: velocity changes colour as well as level (eight strokes, soft to hard)
        {"04_velocity_ramp", [=] {
             Score s;
             for (int i = 0; i < 8; ++i) s = s + stroke(kLead + 0.7 * i, C4, 0.15f + 0.85f * float(i) / 7.0f);
             return render(s, D);
         }},
        // 05: where it stops sounding like the instrument
        {"05_range_C2_C3_C4_C5_C6", [=] { return render(phrase(kLead, {36, 48, 60, 72, 84}, 1.6, -1, 0.85f), D); }},
        // 06: a strummed chord, then the same struck at once
        {"06_chord_strum_then_block", [=] {
             return render(chord(kLead, {48, 55, 60, 64}, 0.8f, 1.5, 40) + chord(3.0, {48, 55, 60, 64}, 0.8f, 1.5), D);
         }},

        // Programs
        {"P01_soft_mallet", [=] { return render(strokeThenPhrase(48), softMallet()); }},
    };
}

// Recordings to compare with. The listener puts them into <outdir>/references/ by hand (the
// research downloaded them); the spike only lists them and never creates that folder.
static std::vector<Reference> references()
{
    return {
        {"R1_example_bar_C4.wav", "a CC0 / CC BY take: URL, author, licence (the example has none)", "01, 02, 03"},
    };
}

int main(int argc, char** argv) { return run(argc, argv, renders(), references()); }
