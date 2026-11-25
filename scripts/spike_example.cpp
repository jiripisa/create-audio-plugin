// spike_example.cpp - EXAMPLE listening prototype written against spike_harness.h (not product code).
//
// The pattern a run's .planning/research/spike/<slug>_spike.cpp follows: only the instrument and
// its renders are new, everything else is the harness. The "instrument" here is a toy struck bar:
//   strike  a short attack ramp, then each partial rings out on its own (upper ones faster)
//   colour  partials k = 1..16 at k * f0 * sqrt(1 + B k^2), falling tiltDb per octave, the
//           fundamental set apart by fundamentalDb; velocity brightens (its level is the
//           platform's: Vel Sens, applied by the harness)
//   release a note-off damps the bar (releaseMs T60), and the voice goes silent for good
// A real spike takes its model and starting numbers from the research report's "Recommendation
// for the engine", and one render group per "Question for the user's ear".
//
// The voice is written as the engine will run it (the template's Voice.h): start, release, render,
// finished; the pitch from knobs.hz(note) in render(), so that it bends and glides; its random
// numbers from a generator of its own, seeded with kVoiceSeed at every fresh start.
//
// Renders 48 kHz / 24-bit mono WAV files, peak-normalised to -1 dBFS:
//   00_check_*   renders with a known answer, for checking the analysis chain (not for the ear):
//                the score helpers' tone, noise in a tail, a weak fundamental, weak odd partials,
//                a low short stroke, a groove and one of its strokes, a hum an octave under,
//                damped low notes alone and in grooves, a stroke cut at the file end, mixed
//                registers, clicks inside swells. They are layered (Playing::layered): strokes
//                ring over each other as in a recording of a real instrument, which is what the
//                analysis tool is checked on; a render for the ear never is
//   01..06       one group per question, decisive question first, each with a long tail
//   07..10       how it plays, as the plug-in will: a re-hit of a sounding key, Legato and Mono
//                with Glide, the sustain pedal, the pitch bend
//   P01_*        one render per planned program
//   S01.., S02.. silence renders: the ways a voice ends, rendered until it is over
//
//   clang++ -std=c++17 -O2 spike_example.cpp -o <scratch>/spike_example && <scratch>/spike_example <outdir>
//   <scratch>/spike_example --analyze 01      quick harmonic table of 01_default

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
    float levelDb = -12.0f;
};

// How the bar is played: the platform's own style (Poly, no glide, Bend 2), and a re-hit of a
// sounding key fades the old voice out and strikes anew (kRehitContinues = false).
static const Playing kPlaying;

struct Voice
{
    static constexpr size_t kPartials = 16;
    const Params* p = nullptr;
    const Knobs* knobs = nullptr;
    int note = 60;
    std::mt19937 rng;
    std::array<double, kPartials> phase{}, amp{};
    double env = 0;
    bool on = false, releasing = false;

    explicit Voice(const Params& params) : p(&params) {}

    void start(const Knobs& k, int n, float velocity, bool continuing)
    {
        knobs = &k;
        note = n;
        if (continuing) return;     // a legato note or a return: the bar rings on, at the new pitch
        rng.seed(kVoiceSeed);       // every fresh voice draws the same numbers: equal notes are equal
        const double tilt = p->tiltDb - p->velBright * (1.0 - velocity);
        for (size_t i = 0; i < kPartials; ++i)
        {
            const double db = p->levelDb + tilt * std::log2(double(i + 1)) + (i == 0 ? p->fundamentalDb : 0.0);
            amp[i] = dbToGain(db);
            phase[i] = 2 * kPi * uniform(rng);
        }
        env = 0;
        on = true;
        releasing = false;
    }

    void release() { releasing = true; }

    // Every coefficient from knobs->rate and knobs->hz(note), worked out for this call: the pool
    // moves the bend and the glide between calls.
    void render(float* out, int frames)
    {
        const double rate = knobs->rate, f0 = knobs->hz(note);
        const double attackStep = 1.0 / std::max(1.0, p->attackMs * 0.001 * rate);
        const double releaseMul = std::pow(10.0, -3.0 / (std::max(1.0f, p->releaseMs) * 0.001 * rate));
        std::array<double, kPartials> inc, decay, heard;
        for (size_t i = 0; i < kPartials; ++i)
        {
            const double k = double(i + 1);
            const double hz = k * f0 * std::sqrt(1.0 + p->stretch * k * k);
            inc[i] = 2 * kPi * hz / rate;
            heard[i] = hz < 0.45 * rate ? 1.0 : 0.0;
            const double t60 = p->ring / (1.0 + p->damping * (k - 1.0));
            decay[i] = p->ring > 0 ? std::pow(10.0, -3.0 / (t60 * rate)) : 1.0;
        }
        for (int f = 0; f < frames; ++f)
        {
            if (releasing) env *= releaseMul;
            else env = std::min(1.0, env + attackStep);
            double s = 0;
            for (size_t i = 0; i < kPartials; ++i)
            {
                s += heard[i] * amp[i] * std::sin(phase[i]);
                phase[i] += inc[i];
                if (phase[i] > 2 * kPi) phase[i] -= 2 * kPi;
                amp[i] *= decay[i];
            }
            if ((releasing && env < 1e-7) || (p->ring > 0 && amp[0] * env < 1e-7 && env >= 1.0)) on = false;
            out[f] = on ? float(s * env) : 0.0f;
        }
    }

    bool finished() const { return !on; }
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

// The spike's render function: play as the plug-in will, then peak-normalise to -1 dBFS.
static Samples render(const Score& s, const Params& p, const Playing& how = kPlaying)
{
    Samples x = play(s, Voice(p), how);
    normalize(x);
    return x;
}

// For the 00_check_* test signals only: every stroke a voice of its own that rings on.
static Playing layered()
{
    Playing how;
    how.layered = true;
    return how;
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
    return p;
}

static Renders renders()
{
    const Params D;
    const int A3 = 57, C4 = 60;
    auto with = [D](auto change) { Params p = D; change(p); return p; };
    const Score check = held(A3, 1.0f, 1.5).withTail(1.0);
    auto every300 = [](int key, bool accents) {
        Score s;
        for (int i = 0; i < 8; ++i) s = s + stroke(kLead + 0.3 * i, key, accents ? (i % 2 ? 0.95f : 0.3f) : 0.8f);
        return s;
    };
    return {
        {"00_check_A_tone_220Hz", [=] { return render(check, checkTone(), layered()); }},
        {"00_check_B_noise_tail", [=] {
             Samples x = render(check, checkTone(), layered());
             std::mt19937 rng = seeded("00_check_B_noise_tail");
             const double g = dbToGain(-60.0);  // white noise at -60 dBFS RMS in the last second
             for (size_t i = x.size() - size_t(kRate); i < x.size(); ++i) x[i] += float(g * white(rng));
             return x;
         }},
        {"00_check_C_weak_fundamental", [=] {
             Params p = checkTone();
             p.fundamentalDb = -26;  // H1 20 dB under H2: the pitch is still 220 Hz
             return render(check, p, layered());
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
             return render(stroke(kLead, 28, 0.9f), with([](Params& p) { p.ring = 0.25f; p.fundamentalDb = -10; }), layered());
         }},
        {"00_check_F_groove", [=] {
             // 16 C3 strokes every 150 ms, accents on the beats: 16 onsets, 6.67 strokes per s.
             Score s;
             for (int i = 0; i < 16; ++i) s = s + stroke(kLead + 0.15 * i, 48, i % 4 == 0 ? 0.95f : 0.75f);
             return render(s, singleRate(), layered());
         }},
        {"00_check_G_one_stroke", [=] { return render(stroke(kLead, 48, 0.95f), singleRate(), layered()); }},
        {"00_check_H_hum_an_octave_under", [=] {
             // G2 with a 49 Hz hum at -45 dBFS: the pitch is still 98 Hz.
             Samples x = render(held(43, 1.0f, 1.5).withTail(1.0), checkTone(), layered());
             for (size_t i = 0; i < x.size(); ++i)
                 x[i] += float(dbToGain(-45) * std::sin(2 * kPi * 49.0 * double(i) / kRate));
             return x;
         }},

        // Damped low notes of the default instrument, whose partials a 20 ms frame does not
        // resolve: one stroke each, an even groove and an accented one (0.3 / 0.95) every 300 ms,
        // and the accented A1 groove with one decay rate. 1 or 8 onsets each.
        {"00_check_I_A1_stroke", [=] { return render(stroke(kLead, 33, 0.95f), D, layered()); }},
        {"00_check_J_E2_stroke", [=] { return render(stroke(kLead, 40, 0.95f), D, layered()); }},
        {"00_check_K_A1_even", [=] { return render(every300(33, false), D, layered()); }},
        {"00_check_L_E2_even", [=] { return render(every300(40, false), D, layered()); }},
        {"00_check_M_A1_accents", [=] { return render(every300(33, true), D, layered()); }},
        {"00_check_N_E2_accents", [=] { return render(every300(40, true), D, layered()); }},
        {"00_check_O_A1_accents_single_rate", [=] { return render(every300(33, true), singleRate(), layered()); }},

        // The end of the file: an E2 stroke cut while it rings (1 onset, none at the cut).
        {"00_check_P_E2_stroke_cut", [=] {
             Score s = stroke(kLead, 40, 0.95f);
             s.length = 1.0;
             return render(s, D, layered());
         }},
        // Mixed registers: loud A#1 (58 Hz) strokes that die within 0.1 s, each with a burst of
        // noise 18 dB under it, and between them C#4 (277 Hz) strokes 18 dB
        // quieter, one every 0.184 s: 16 onsets. The noise keeps the long frames busy, so the
        // quiet high strokes are found only on 20 ms frames.
        {"00_check_Q_low_and_high", [=] {
             Params low = D, high = D;
             low.ring = high.ring = 0.3f;
             high.levelDb = D.levelDb - 18;
             Score s;
             for (int i = 0; i < 16; ++i) {
                 Score one = stroke(kLead + 0.184 * i, i % 2 ? 61 : 34, 0.9f);
                 s = s + (i % 2 ? one.onPart(1) : one);
             }
             Samples x = play(s, std::vector<Voice>{Voice(low), Voice(high)}, layered());
             std::mt19937 rng = seeded("00_check_Q_low_and_high");
             const double g = dbToGain(D.levelDb - 18), fall = std::pow(10.0, -3.0 / (0.3 * kRate));
             double rub = 0;
             size_t next = 0;
             for (size_t i = 0; i < x.size(); ++i) {
                 if (next < 8 && i == size_t((kLead + 0.368 * double(next)) * kRate + 0.5)) { rub = 1; ++next; }
                 x[i] += float(g * rub * white(rng));
                 rub *= fall;
             }
             normalize(x);
             return x;
         }},
        // Onsets inside swells: four strokes every 0.25 s, each a short high click on a C3 tone
        // that swells over 0.7 s, so that each stroke is cut while still rising (as bursts of a
        // rubbed sound); its strokes are flagged as suspect.
        {"00_check_R_clicks_in_swells", [=] {
             Params swell = checkTone(), click = D;
             swell.attackMs = 700;
             click.ring = 0.05f;
             click.levelDb = D.levelDb - 6;
             Score s;
             for (int i = 0; i < 4; ++i)
                 s = s + note(kLead + 0.25 * i, 48, 0.9f, 1.5) + stroke(kLead + 0.25 * i, 88, 0.9f).onPart(1);
             Samples x = play(s, std::vector<Voice>{Voice(swell), Voice(click)}, layered());
             normalize(x);
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

        // 07-10: how it plays, as the plug-in will from the same notes.
        // 07: a key struck again while it rings: the old voice fades out in 3 ms, a fresh one
        // strikes (kRehitContinues = false; an instrument that continues sets rehitContinues).
        {"07_rehit_same_key", [=] { return render(phrase(kLead, {C4, C4, C4, C4}, 0.35, -1, 0.85f), D); }},
        // 08: C4 held, C5 played over it at 1.2 s and let go at 2.2 s, Glide 200 ms. Legato goes
        // on without a new strike and glides up; Mono strikes anew and glides; both glide back to
        // the C4 still held.
        {"08_glide_A_legato_200ms", [=] {
             Playing how;
             how.mode = Mode::Legato;
             how.glideMs = 200;
             return render(note(kLead, C4, 0.9f, 3.0) + note(1.2, C4 + 12, 0.9f, 1.0), with([](Params& p) { p.ring = 0; }), how);
         }},
        {"08_glide_B_mono_200ms", [=] {
             Playing how;
             how.mode = Mode::Mono;
             how.glideMs = 200;
             return render(note(kLead, C4, 0.9f, 3.0) + note(1.2, C4 + 12, 0.9f, 1.0), with([](Params& p) { p.ring = 0; }), how);
         }},
        // 09: short notes with the sustain pedal down from 0.1 s to 2.5 s: they ring until it comes up.
        {"09_sustain_pedal", [=] { return render(phrase(kLead, {48, 55, 60, 64}, 0.3, 0.2).pedal(0.1, 2.5).withTail(kTail), D); }},
        // 10: a held note bent up by Bend Up (2 semitones) over half a second, then let go.
        {"10_bend_up_2_semitones", [=] {
             return render(held(C4, 0.9f, 2.5).bendSlide(0.7, 1.2, 0.0f, 1.0f).bend(2.0, 0.0f), with([](Params& p) { p.ring = 0; }));
         }},

        // Programs
        {"P01_soft_mallet", [=] { return render(strokeThenPhrase(48), softMallet()); }},

        // Silence renders: one per way a voice ends, rendered until the voice is over (finished())
        // and half a second more, whatever its T60; the tail floor bar applies to these.
        {"S01_silence_note_off", [=] { return render(note(kLead, C4, 0.9f, 0.5).untilOver(), D); }},
        {"S02_silence_stroke_rings_out", [=] { return render(stroke(kLead, C4, 0.9f).untilOver(), D); }},
        {"S03_silence_rehit", [=] { return render(phrase(kLead, {C4, C4}, 0.3, -1).untilOver(), D); }},
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
