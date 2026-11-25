// harness_rules.cpp - checks that scripts/spike_harness.h plays a score by the platform's rules
// (the template's engine): what a re-hit does, Poly / Mono / Legato, the glide law, the sustain
// pedal, the pitch bend, Vel Sens, voice stealing, pads and groups, and that equal notes are
// equal samples. Built and run by tests/test_spike_analyze.sh:
//
//   clang++ -std=c++17 -O2 -Wall -Wextra -Werror -I scripts tests/harness_rules.cpp -o <tmp>/harness_rules
//
// The voices here are probes: they write what the pool tells them (a level, Knobs::glide,
// Knobs::bend, Knobs::hz) instead of a sound, so every check reads exact numbers. That the engine
// gives the same samples from the same notes is checked in the template itself
// (PrototypeEquivalenceTests: its reference is this harness).

#include "spike_harness.h"

#include <cstdio>

using namespace spike;

static int failures = 0;

#define CHECK(condition, ...)                                                    \
    do {                                                                         \
        if (!(condition)) {                                                      \
            ++failures;                                                          \
            std::printf("FAIL line %d: %s: ", __LINE__, #condition);             \
            std::printf(__VA_ARGS__);                                            \
            std::printf("\n");                                                   \
        }                                                                        \
    } while (0)

struct Log
{
    struct Start { int note; bool continuing; float velocity; };
    std::vector<Start> starts;
    int releases = 0;

    int fresh() const { return int(std::count_if(starts.begin(), starts.end(), [](const Start& s) { return !s.continuing; })); }
    int continuing() const { return int(starts.size()) - fresh(); }
};

struct Probe
{
    enum Show { Level, Glide, Bend, Hz, Noise };
    Log* log;
    Show show;
    double lasts;                   // s a voice sounds by itself; 0 = until it is released
    const Knobs* knobs = nullptr;
    int note = 0;
    bool on = false;
    size_t age = 0;
    std::mt19937 rng;

    explicit Probe(Log& l, Show what = Level, double seconds = 0) : log(&l), show(what), lasts(seconds) {}

    void start(const Knobs& k, int n, float velocity, bool continuing)
    {
        knobs = &k;
        note = n;
        log->starts.push_back({n, continuing, velocity});
        if (continuing) return;
        on = true;
        age = 0;
        rng.seed(kVoiceSeed);
    }
    void release() { ++log->releases; on = false; }
    void render(float* out, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            float y = 1.0f;
            if (show == Glide) y = knobs->glide;
            else if (show == Bend) y = knobs->bend;
            else if (show == Hz) y = float(knobs->hz(note));
            else if (show == Noise) y = float(white(rng));
            out[i] = on ? y : 0.0f;
            ++age;
            if (lasts > 0 && double(age) >= lasts * knobs->rate) on = false;
        }
    }
    bool finished() const { return !on; }
};

static size_t at(double seconds) { return size_t(std::llround(seconds * kRate)); }
static bool near(double a, double b, double tolerance = 1e-4) { return std::fabs(a - b) <= tolerance; }

static void rehit()
{
    const Score twice = stroke(0.1, 60, 1.0f) + stroke(0.2, 60, 1.0f);
    {
        Log log;
        const Samples x = play(twice, Probe(log));
        CHECK(log.fresh() == 2 && log.continuing() == 0, "fresh %d, continuing %d", log.fresh(), log.continuing());
        CHECK(x[at(0.15)] == 1.0f, "one voice before the re-hit: %g", x[at(0.15)]);
        CHECK(x[at(0.201)] > 1.0f && x[at(0.201)] < 2.0f, "1 ms into the 3 ms fade: %g", x[at(0.201)]);
        CHECK(x[at(0.203)] > 1.0f && x[at(0.203)] < 1.011f, "40 dB down after 3 ms: %g", x[at(0.203)]);
        CHECK(x[at(0.22)] == 1.0f, "the faded voice has left: %g", x[at(0.22)]);
    }
    {
        Log log;
        Playing how;
        how.rehitContinues = true;
        const Samples x = play(twice, Probe(log), how);
        CHECK(log.fresh() == 1 && log.continuing() == 1, "fresh %d, continuing %d", log.fresh(), log.continuing());
        CHECK(x[at(0.201)] == 1.0f, "the same voice goes on: %g", x[at(0.201)]);
    }
    {
        // A note that ends as the next begins on the same key: let go first, then pressed.
        Log log;
        const Samples x = play(note(0.1, 60, 1.0f, 0.1) + note(0.2, 60, 1.0f, 0.1), Probe(log));
        CHECK(log.fresh() == 2 && log.releases == 2, "fresh %d, releases %d", log.fresh(), log.releases);
        CHECK(x[at(0.25)] == 1.0f && x[at(0.31)] == 0.0f, "second note: %g, after it: %g", x[at(0.25)], x[at(0.31)]);
    }
}

static void voiceModes()
{
    // 60 held from 0.1 to 0.6, 64 over it from 0.2 to 0.4.
    const Score overlap = note(0.1, 60, 1.0f, 0.5) + note(0.2, 64, 1.0f, 0.2);
    auto order = [](const Log& log) {
        std::string s;
        for (const Log::Start& start : log.starts) s += std::to_string(start.note) + (start.continuing ? "c " : "f ");
        return s;
    };
    {
        Log log;
        Playing how;
        how.mode = Mode::Mono;
        const Samples x = play(overlap, Probe(log), how);
        CHECK(order(log) == "60f 64f 60c ", "Mono: %s", order(log).c_str());
        CHECK(log.releases == 1, "Mono: %d releases", log.releases);
        CHECK(x[at(0.3)] == 1.0f && x[at(0.5)] == 1.0f && x[at(0.61)] == 0.0f, "Mono: one voice, released with the last key");
    }
    {
        Log log;
        Playing how;
        how.mode = Mode::Legato;
        play(overlap, Probe(log), how);
        CHECK(order(log) == "60f 64c 60c ", "Legato: %s", order(log).c_str());
        CHECK(log.releases == 1, "Legato: %d releases", log.releases);
    }
    {
        Log log;
        Playing how;
        how.mode = Mode::Legato;
        play(note(0.1, 60, 1.0f, 0.05) + note(0.2, 64, 1.0f, 0.05), Probe(log), how);
        CHECK(order(log) == "60f 64f ", "Legato without overlap: %s", order(log).c_str());
    }
    {
        Log log;
        const Samples x = play(overlap, Probe(log));
        CHECK(order(log) == "60f 64f ", "Poly: %s", order(log).c_str());
        CHECK(x[at(0.3)] == 2.0f && log.releases == 2, "Poly: a voice per key (%g), %d releases", x[at(0.3)], log.releases);
    }
}

static void glide()
{
    // 60 held from 0.1 to 1.1, 72 over it from 0.3 to 0.8, Glide 100 ms: 300 control ticks of 16
    // samples, 0.04 semitones each, from 12 below the new note; then back down from 12 above.
    const Score up = note(0.1, 60, 1.0f, 1.0) + note(0.3, 72, 1.0f, 0.5);
    for (Mode mode : {Mode::Legato, Mode::Mono})
    {
        Log log;
        Playing how;
        how.mode = mode;
        how.glideMs = 100;
        const Samples x = play(up, Probe(log, Probe::Glide), how);
        const size_t s = at(0.3), back = at(0.8);
        CHECK(x[s - 1] == 0.0f, "no glide before the second note: %g", x[s - 1]);
        // In Mono the note is a fresh voice while the one it replaces fades out (glide 0): read
        // the glide once that fade is over.
        CHECK(x[s + 16 * 40] != 0.0f && near(x[s + 16 * 40], -12.0 + 0.04 * 40), "40 ticks in: %g", x[s + 16 * 40]);
        CHECK(near(x[s + 16 * 150], -6.0), "halfway: %g", x[s + 16 * 150]);
        CHECK(near(x[s + 16 * 299 + 15], -0.04), "the last tick: %g", x[s + 16 * 299 + 15]);
        // 300 steps of a float 0.04 leave a hundred-thousandth of a semitone, gone a tick later
        // (the engine's own arithmetic, kept so that the two agree sample for sample).
        CHECK(near(x[s + 16 * 300], 0.0) && x[s + 16 * 301] == 0.0f, "there after Glide ms: %g, %g", x[s + 16 * 300], x[s + 16 * 301]);
        CHECK(x[back] == 12.0f, "the return starts 12 above: %g", x[back]);
        CHECK(near(x[back + 16 * 150], 6.0) && near(x[back + 16 * 300], 0.0) && x[back + 16 * 301] == 0.0f,
              "the return: %g, %g", x[back + 16 * 150], x[back + 16 * 300]);
        if (mode == Mode::Legato) CHECK(x[s] == -12.0f, "Legato: the first tick is the whole distance: %g", x[s]);
    }
    {
        // A note played while the pitch still glides starts from where the pitch is: halfway from
        // 60 to 72 (66) to 67 is one semitone.
        Log log;
        Playing how;
        how.mode = Mode::Legato;
        how.glideMs = 100;
        const Samples x = play(up + note(0.35, 67, 1.0f, 0.2), Probe(log, Probe::Glide), how);
        CHECK(near(x[at(0.35)], -1.0, 1e-3), "from the gliding pitch: %g", x[at(0.35)]);
    }
    {
        Log log;
        Playing how;
        how.glideMs = 100;
        const Samples x = play(up, Probe(log, Probe::Glide), how);
        CHECK(std::all_of(x.begin(), x.end(), [](float v) { return v == 0.0f; }), "Poly never glides");
    }
    {
        Log log;
        Playing how;
        how.mode = Mode::Legato;
        const Samples x = play(up, Probe(log, Probe::Glide), how);
        CHECK(std::all_of(x.begin(), x.end(), [](float v) { return v == 0.0f; }), "Glide 0 never glides");
    }
}

static void pedalAndBend()
{
    {
        Log log;
        const Samples x = play(note(0.1, 60, 1.0f, 0.1).pedal(0.15, 0.5).withTail(1.0), Probe(log));
        CHECK(x[at(0.3)] == 1.0f, "the pedal holds the key's voice: %g", x[at(0.3)]);
        CHECK(x[at(0.5) + 16] == 0.0f && log.releases == 1, "released as the pedal comes up: %g, %d", x[at(0.5) + 16], log.releases);
    }
    {
        Log log;
        Playing how;
        how.bendUp = 12;
        how.bendDown = 5;
        const Samples x = play(held(60, 1.0f, 1.0).bend(0.3, 1.0f).bend(0.5, -1.0f).bend(0.7, 0.0f), Probe(log, Probe::Bend), how);
        CHECK(x[at(0.25)] == 0.0f && x[at(0.4)] == 12.0f && x[at(0.6)] == -5.0f && x[at(0.8)] == 0.0f,
              "bend: %g %g %g %g", x[at(0.25)], x[at(0.4)], x[at(0.6)], x[at(0.8)]);
        CHECK(x[at(0.3) + 16] == 12.0f, "the bend lands within a control tick: %g", x[at(0.3) + 16]);
    }
    {
        Log log;
        const Samples x = play(held(69, 1.0f, 0.5).bend(0.3, 1.0f), Probe(log, Probe::Hz));
        CHECK(x[at(0.25)] == 440.0f, "A4: %g", x[at(0.25)]);
        CHECK(near(x[at(0.4)], 440.0 * std::exp2(2.0 / 12.0), 1e-3), "A4 bent up 2 semitones: %g", x[at(0.4)]);
    }
}

static void levels()
{
    {
        Log log;
        const Samples x = play(stroke(0.1, 60, 0.5f), Probe(log));
        const float want = 1.0f - 0.7f * (1.0f - 64.0f / 127.0f);    // 0.5 is played as MIDI's 64
        CHECK(x[at(0.2)] == want && log.starts[0].velocity == 64.0f / 127.0f, "Vel Sens: %g, want %g", x[at(0.2)], want);
    }
    {
        Log log;
        Playing how;
        how.velSens = 0.0f;
        const Samples x = play(stroke(0.1, 60, 0.01f), Probe(log), how);
        CHECK(x[at(0.2)] == 1.0f && log.starts[0].velocity == 1.0f / 127.0f, "velocity 1 at least: %g", log.starts[0].velocity);
    }
    {
        // Seventeen keys: the sixteen sound, and the 17th steals the quietest (key 65, soft).
        Log log;
        Score s;
        for (int key = 60; key < 76; ++key) s = s + stroke(0.1, key, key == 65 ? 0.5f : 1.0f);
        const float soft = 1.0f - 0.7f * (1.0f - 64.0f / 127.0f);
        const Samples x = play(s + stroke(0.2, 80, 1.0f), Probe(log));
        CHECK(near(x[at(0.15)], 15.0 + soft, 1e-5), "sixteen voices: %g", x[at(0.15)]);
        CHECK(x[at(0.25)] == 16.0f, "the soft one was stolen: %g", x[at(0.25)]);
    }
}

static void equalNotes()
{
    Log log;
    const Samples x = play(stroke(0.1, 60, 1.0f) + stroke(0.5, 60, 1.0f), Probe(log, Probe::Noise, 0.05));
    CHECK(x[at(0.1)] != 0.0f && x[at(0.1)] != x[at(0.1) + 1], "the voice draws noise");
    CHECK(std::equal(x.begin() + long(at(0.1)), x.begin() + long(at(0.16)), x.begin() + long(at(0.5))), "two equal notes differ");
    // A continuing start goes on in the same stream: one long note and the same note re-hit halfway.
    Playing continues;
    continues.rehitContinues = true;
    const Samples one = play(stroke(0.1, 60, 1.0f), Probe(log, Probe::Noise, 0.2), continues);
    const Samples two = play(stroke(0.1, 60, 1.0f) + stroke(0.2, 60, 1.0f), Probe(log, Probe::Noise, 0.2), continues);
    CHECK(std::equal(one.begin(), one.end(), two.begin()), "a continuing start restarted the generator");
    std::mt19937 first(kVoiceSeed);
    CHECK(x[at(0.1)] == float(white(first)), "the first draw is not kVoiceSeed's");
}

static void padsAndLayers()
{
    Log low, high;
    const std::vector<Probe> pads{Probe(low), Probe(high)};
    const Score hits = stroke(0.1, 40, 1.0f) + stroke(0.2, 40, 1.0f) + stroke(0.3, 52, 1.0f).onPart(1);
    {
        Playing how;
        how.pads = true;
        how.mode = Mode::Mono;      // the pads ignore the voice mode
        const Samples x = play(hits, pads, how);
        CHECK(low.fresh() == 2 && high.fresh() == 1, "a re-hit pad: %d, the other pad: %d", low.fresh(), high.fresh());
        CHECK(x[at(0.25)] == 1.0f && x[at(0.35)] == 2.0f, "each pad its own voice: %g, %g", x[at(0.25)], x[at(0.35)]);
    }
    {
        low = Log();
        high = Log();
        Playing how;
        how.pads = true;
        how.groups = {3, 3};
        const Samples x = play(hits, pads, how);
        CHECK(x[at(0.35)] == 1.0f, "the pads of a group share one voice: %g", x[at(0.35)]);
    }
    {
        low = Log();
        Playing how;
        how.pads = true;
        const Samples x = play(note(0.1, 40, 1.0f, 0.1).pedal(0.05, 0.5).bend(0.05, 1.0f).withTail(1.0), Probe(low, Probe::Bend), how);
        CHECK(low.releases == 1 && std::all_of(x.begin(), x.end(), [](float v) { return v == 0.0f; }), "pads: no pedal, no bend");
    }
    {
        low = Log();
        Playing how;
        how.layered = true;
        const Samples x = play(stroke(0.1, 60, 1.0f) + note(0.15, 60, 1.0f, 0.1) + stroke(0.2, 60, 1.0f), Probe(low), how);
        CHECK(x[at(0.22)] == 3.0f && x[at(0.3)] == 2.0f, "layered: %g, then %g", x[at(0.22)], x[at(0.3)]);
    }
}

static void lengths()
{
    Log log;
    // A stroke at 0.1 s whose voice is over 0.2 s later, and half a second more.
    const Samples x = play(stroke(0.1, 60, 1.0f).untilOver(0.5), Probe(log, Probe::Level, 0.2));
    CHECK(x.size() >= at(0.8) && x.size() <= at(0.8) + 32, "untilOver: %zu samples, want %zu", x.size(), at(0.8));
    CHECK(play(stroke(0.1, 60, 1.0f).untilOver(0.5, 3.0), Probe(log)).size() == at(3.1), "untilOver: a voice that never ends stops at the cap");
    CHECK(play(stroke(0.1, 60, 1.0f), Probe(log)).size() == at(0.1 + kTail), "the default tail");
    // The reference copy's path: the same notes as messages.
    Log a, b;
    const Score s = note(0.1, 60, 0.8f, 0.3) + note(0.2, 64, 0.6f, 0.3);
    std::vector<Message> messages{{0.1, Message::NoteOn, 60, 0.8f}, {0.2, Message::NoteOn, 64, 0.6f},
                                  {0.4, Message::NoteOff, 60}, {0.5, Message::NoteOff, 64}};
    CHECK(play(s, Probe(a)) == perform(messages, std::vector<Probe>{Probe(b)}, Playing(), kRate, s.length), "messages and score differ");
}

int main()
{
    rehit();
    voiceModes();
    glide();
    pedalAndBend();
    levels();
    equalNotes();
    padsAndLayers();
    lengths();
    if (failures) { std::printf("%d harness rule checks failed\n", failures); return 1; }
    std::printf("harness rules ok\n");
    return 0;
}
