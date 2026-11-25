// spike_harness.h - the shared part of a throwaway listening prototype (create-audio-plugin skill).
//
// A run's prototype, .planning/research/spike/<slug>_spike.cpp, holds only the instrument (a
// Params struct with the defaults, a Voice, one function per program) and its list of renders.
// Everything else is here: notes and scores, the platform around a voice (play: what the plug-in's
// engine will do with the same notes), a 24-bit WAV writer, and the command line. Copy this file
// next to the spike so the spike folder builds on its own; scripts/spike_example.cpp is the
// pattern to follow.
//
//   clang++ -std=c++17 -O2 <slug>_spike.cpp -o <scratch>/<slug>_spike     (the binary never beside
//                                        the source: the spike folder is committed)
//   <scratch>/<slug>_spike <dir> [prefix...]   writes <dir>/<name>.wav for every render (or only
//                                        those whose name starts with one of the prefixes), then
//                                        says which listed references are in <dir>/references/
//   <scratch>/<slug>_spike --analyze [prefix] [--at seconds]
//                                        renders one render (the first that matches, default the
//                                        first of all) in memory and prints a quick harmonic table
//   <scratch>/<slug>_spike --list        prints the render names
//
// --analyze is a built-in check while tuning, so that no file has to be written and nothing but
// this header is needed. For one note it uses the same rules as scripts/analyze.swift (steady
// window, pitch first by normalised autocorrelation with the octave guard, then H1..H10 read at
// that pitch, the few-periods note), with a direct DFT instead of an FFT; it does not find
// onsets, so in a phrase its window may run into the next stroke. analyze.swift on the written
// WAVs is the measurement that goes into reports and is compared with the recordings.
//
// play() is the platform: what the user approves on these renders is what the plug-in plays from
// the same notes, so the pool here follows the template's engine rule for rule (its
// <APP>Engine.cpp; TEMPLATE_MANIFEST.md "Melodic playing"):
//   - a Voice has the engine's four calls (start, release, render, finished) and reads its pitch
//     from Knobs::hz(note), which carries the pitch bend and the glide;
//   - a note-on on a key whose voice sounds continues that voice (Playing::rehitContinues, the
//     instrument's kRehitContinues) or fades it out in 3 ms and starts a fresh one;
//   - Poly, Mono (last-note priority, every note attacked anew, a return to a key still held
//     continues) and Legato (an overlapping note continues), with the engine's glide: from where
//     the voice was to the new note in Glide ms, evenly in semitones, a control tick of 16
//     samples at a time;
//   - the sustain pedal, the pitch bend by Bend Up / Bend Down, Vel Sens on the level (the voice
//     itself never scales its level by the velocity), 16 voices with the quietest stolen;
//   - pads (Playing::pads): a pad is a key press with a voice of its own or of its group; no
//     voice mode, glide, bend or pedal.
// Not played here: the LFO and VEL amounts and the wheels, which rest at 0 in the default sound
// (the engine's ListeningRenders play them), and the 2x stage below 88.2 kHz (the reference copy
// of the prototype runs play() at the engine's rate, phase 02).
//
// Conventions:
//   - mono, float samples, default 48 kHz (kRate); every helper takes the rate where it matters
//   - keys are MIDI note numbers (60 = C4, 69 = A4 = 440 Hz), velocities 0..1, times in seconds;
//     play() puts every event on a whole sample and takes velocities and bends as MIDI carries
//     them (velocity round(v * 127) / 127 and at least 1 / 127, a 14-bit bend)
//   - an Event with dur < 0 is a stroke: no note-off is sent, the voice rings out by itself
//   - dBFS = 20 log10(RMS) with full scale 1.0 (a full-scale sine reads -3.0 dBFS); -200 stands
//     for digital silence
//   - randomness: a voice that needs random numbers owns a std::mt19937 and seeds it with
//     kVoiceSeed at every fresh start (continuing == false); a continuing start goes on in the
//     same stream. Numbers only through uniform()/white() here, because std's distributions
//     differ between libraries. The engine does the same (the template's VoiceRandom.h holds the
//     same constant and the same two functions), so two equal notes are equal samples in the
//     prototype and in the plug-in, and the port is draw for draw. Nothing else is random: no
//     generator shared between voices, no clock, no count of hits. (seeded()/seedOf() are for
//     test signals mixed into a render, as the example's 00_check_* do, never for a voice.)
//   - the WAV writer does not normalise; call normalize() in the spike's render function
//     (-1 dBFS peak, so that the listener compares colour, not level)
//   - nothing is written outside <dir>; the references folder is never created, only looked at

#pragma once

// A product and a sum stay two roundings in everything that includes this file, whatever the
// build: the engine and the reference copy of the prototype are built this way, so the approved
// renders are computed as the reference computes them (phase 02 compares the two files).
#pragma clang fp contract(off)

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
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

// The seed of every voice's generator, at every fresh start (see "randomness" above). The same
// constant as the template's VoiceRandom.h: change neither.
inline constexpr uint32_t kVoiceSeed = 0x51ED270Bu;

// FNV-1a of a text: a seed for a test signal that does not move when renders are reordered.
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
    int part = 0;   // which voice prototype plays it: on the pads the pad, else a program to hear
};

// What a player does besides the notes: the sustain pedal and the pitch bend.
struct Control
{
    enum Kind { Pedal, Bend };
    double time;    // s
    Kind kind;
    float value;    // Pedal: 1 down, 0 up; Bend: -1 (all the way down) ... +1 (all the way up)
};

struct Score
{
    std::vector<Event> events;
    std::vector<Control> controls;
    double length = 0;      // s rendered
    double ringOut = -1;    // >= 0: rendered until every voice is over, and this long after (untilOver)
    double ringOutCap = 0;  // ... but no longer than this after the last note ends

    // End of the last note (a stroke counts from its start) or control.
    double lastEnd() const
    {
        double end = 0;
        for (const Event& e : events) end = std::max(end, e.time + std::max(0.0, e.dur));
        for (const Control& c : controls) end = std::max(end, c.time);
        return end;
    }
    // The render lasts until `seconds` after the last note ends.
    Score& withTail(double seconds) { length = lastEnd() + seconds; ringOut = -1; return *this; }
    // The render lasts until every voice is over for good (finished()), and `after` seconds of
    // silence more: what a silence render needs (S01_silence_*), whatever the voice's T60. Never
    // longer than `atMost` seconds after the last note ends (a voice that never ends).
    Score& untilOver(double after = 0.5, double atMost = 60.0)
    {
        ringOut = after;
        ringOutCap = atMost;
        length = lastEnd() + atMost;
        return *this;
    }
    // Every event is played by voice prototype `p`.
    Score& onPart(int p) { for (Event& e : events) e.part = p; return *this; }
    // The sustain pedal down at `down` and up again at `up`.
    Score& pedal(double down, double up)
    {
        controls.push_back({down, Control::Pedal, 1.0f});
        controls.push_back({up, Control::Pedal, 0.0f});
        return *this;
    }
    // The pitch bend at `amount` (-1 ... +1) from `t` on; bend(t, 0) lets it go.
    Score& bend(double t, float amount) { controls.push_back({t, Control::Bend, amount}); return *this; }
    // The bend moved evenly from `from` to `to` between t0 and t1, a message every 5 ms.
    Score& bendSlide(double t0, double t1, float from, float to)
    {
        const int steps = std::max(1, int((t1 - t0) / 0.005 + 0.5));
        for (int i = 0; i <= steps; ++i)
            bend(t0 + (t1 - t0) * double(i) / double(steps), from + (to - from) * float(i) / float(steps));
        return *this;
    }
    // Later by dt seconds (length too).
    Score shifted(double dt) const
    {
        Score s = *this;
        for (Event& e : s.events) e.time += dt;
        for (Control& c : s.controls) c.time += dt;
        s.length += dt;
        return s;
    }
    // Both scores at once; the longer length wins.
    Score& add(const Score& other)
    {
        events.insert(events.end(), other.events.begin(), other.events.end());
        controls.insert(controls.end(), other.controls.begin(), other.controls.end());
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

// The keys one after another, every `step` seconds, each held for `dur` (< 0: strokes). With
// dur > step the notes overlap: what Legato continues and Mono and Legato glide between.
inline Score phrase(double startT, const std::vector<int>& keys, double step, double dur, float vel = 0.8f)
{
    Score s;
    for (size_t i = 0; i < keys.size(); ++i)
        s.events.push_back({startT + double(i) * step, keys[i], vel, dur});
    return s.withTail(kTail);
}

// ---- playing a score: the platform around a voice ---------------------------------------------

// The engine's numbers (the template's <APP>Engine.cpp and <APP>DSP.h): change none of them here.
inline constexpr int kControlFrames = 16;        // samples of a control tick: bend and glide move once a tick
inline constexpr int kMaxVoices = 16;            // voices that sound at once; a 17th steals the quietest
inline constexpr int kMaxHeld = 16;              // keys Mono and Legato remember, newest last
inline constexpr float kStealMs = 3.0f;          // a stolen or re-hit voice falls 40 dB in this long
inline constexpr double kFollowSeconds = 0.02;   // the fall of the peak follower that stealing compares
inline constexpr int kFirstPadNote = 36;         // the note that hits pad 0

enum class Mode { Poly, Mono, Legato };

// How the instrument is played: the spec's playing style (the platform knobs whose defaults the
// instrument sets, kPlatformDefaults) and its choice for a re-hit (kRehitContinues). The
// defaults are the platform's own.
struct Playing
{
    Mode mode = Mode::Poly;         // Voice Mode
    double glideMs = 0.0;           // Glide (Mono and Legato)
    int bendUp = 2, bendDown = 2;   // Bend Up / Bend Down, semitones at the ends of the bend
    float velSens = 0.7f;           // Vel Sens: a note at velocity v plays at 1 - velSens (1 - v)
    bool rehitContinues = false;    // a note-on on a sounding voice: true continues it, false
                                    // fades it out in 3 ms and starts a fresh one
    bool pads = false;              // pad mode: event.part is the pad (0 ... 15) and event.key the
                                    // pitch it sounds at; no voice mode, glide, bend or pedal
    std::vector<int> groups;        // pad mode: the group of each pad, 0 = Off (the default); the
                                    // pads of a group share one voice
    bool layered = false;           // test signals only: every event a voice of its own that
                                    // nothing cuts (no re-hit rule, no stealing), released by its
                                    // own note-off. Never for a render the user hears: the
                                    // plug-in does not play like this.
};

// What a voice reads while it sounds: the engine's Knobs without the instrument's own knobs (the
// spike's Params). The pool updates it before every render() call.
struct Knobs
{
    double rate = kRate;    // the voice's sample rate
    float bend = 0.0f;      // the pitch bend, in semitones
    float glide = 0.0f;     // how far the pitch still is from the note while it glides, in semitones

    // A note's frequency with the bend and the glide (Octave 0, Tune 0). Fractional notes are fine.
    double hz(double note) const { return 440.0 * std::exp2((note + double(bend) + double(glide) - 69.0) / 12.0); }
};

// One thing the platform is told, as MIDI would tell it. A score becomes a list of these
// (messagesOf); a reference copy of the prototype may hand play() the engine's own MIDI.
struct Message
{
    enum Kind { NoteOn, NoteOff, Pedal, Bend };
    double time;        // s; played on the nearest whole sample
    Kind kind;
    int key = 0;        // NoteOn, NoteOff: the MIDI note (on the pads: the pitch the pad sounds at)
    float value = 0;    // NoteOn: velocity 0..1; Pedal: >= 0.5 is down; Bend: -1 ... +1
    int part = 0;       // NoteOn: the voice prototype; on the pads the pad, for NoteOff too
    int id = -1;        // layered only: a NoteOff releases the NoteOn of the same id
};

// A score as messages: the controls, then the note-offs, then the note-ons, each in the score's
// order, so that messages on the same sample are played in that order (a note that ends as the
// next begins on the same key is let go before the key is pressed again).
inline std::vector<Message> messagesOf(const Score& score)
{
    std::vector<Message> m;
    for (const Control& c : score.controls)
        m.push_back({c.time, c.kind == Control::Pedal ? Message::Pedal : Message::Bend, 0, c.value, 0, -1});
    for (size_t i = 0; i < score.events.size(); ++i)
    {
        const Event& e = score.events[i];
        if (e.dur >= 0) m.push_back({e.time + e.dur, Message::NoteOff, e.key, 0.0f, e.part, int(i)});
    }
    for (size_t i = 0; i < score.events.size(); ++i)
    {
        const Event& e = score.events[i];
        m.push_back({e.time, Message::NoteOn, e.key, e.vel, e.part, int(i)});
    }
    return m;
}

namespace detail {

// The voice pool, the keys and the pedal: the engine's rules under the engine's names
// (<APP>Engine.cpp: slotFor, freshSlot, monoNoteOn, moveTo, glideFrom, noteOff, pedalUp, control,
// renderSlot). A fresh note starts on a copy of its part's voice prototype.
template <class Voice>
struct Performer
{
    struct Slot
    {
        bool active = false, choking = false;
        bool fromKey = true;            // a key's voice: it follows the bend and the pedal holds it
        int key = 0;                    // what it belongs to: a key, a group of pads, a pad, the mono voice
        int note = 0;                   // the note (on the pads: the pad) whose note-off releases it
        int id = -1;                    // layered: the event that started it
        bool sustained = false;         // its key is up, the sustain pedal holds it
        bool released = false;
        float velocity = 1.0f;
        float glide = 0.0f;             // semitones the pitch still is from the note (Knobs::glide)
        float glideStep = 0.0f;         // what a control tick takes off it
        int ctl = 0;                    // samples left in this control tick
        float outGain = 1.0f;           // Vel Sens
        float chokeGain = 1.0f, chokeMul = 1.0f;
        float level = 0.0f;             // a peak follower on the output: what voice stealing compares
        Knobs knobs;
        Voice voice;

        explicit Slot(const Voice& prototype) : voice(prototype) {}

        // Fades the voice out: it falls 40 dB in `ms`.
        void choke(float ms, double rate)
        {
            if (choking) return;
            choking = true;
            const float tc = std::max(ms, 1.0f) * 0.001f / 4.6f;
            chokeMul = float(std::exp(-1.0 / (tc * rate)));
        }
    };

    static constexpr int kKeyMono = -1, kKeyFirstNote = 0, kKeyFirstGroup = 1000, kKeyFirstPad = 1000000;

    const std::vector<Voice>& parts;
    const Playing& playing;
    const double rate;
    const float followMul;
    std::deque<Slot> slots;             // a deque: a slot's Knobs stay where its voice found them
    int held[kMaxHeld] = {};
    int numHeld = 0;
    bool sustain = false;
    float bend = 0.0f;                  // -1 ... +1

    Performer(const std::vector<Voice>& voices, const Playing& how, double sampleRate)
        : parts(voices), playing(how), rate(sampleRate), followMul(float(std::exp(-1.0 / (kFollowSeconds * sampleRate)))) {}

    bool poly() const { return playing.pads || playing.layered || playing.mode == Mode::Poly; }

    // Where the bend and the glide of `s` stand now.
    void viewFor(Slot& s) const
    {
        s.knobs.bend = s.fromKey ? bend * (bend >= 0.0f ? float(playing.bendUp) : float(playing.bendDown)) : 0.0f;
        s.knobs.glide = s.glide;
        s.knobs.rate = rate;
    }

    // A control tick of `s`: its Knobs as they stand now, its glide a tick on, its gain.
    void control(Slot& s) const
    {
        viewFor(s);
        if (s.glide != 0.0f)
        {
            const float next = s.glide - s.glideStep;
            s.glide = (next > 0.0f) == (s.glide > 0.0f) ? next : 0.0f;     // there once it would pass the note
        }
        s.outGain = 1.0f - playing.velSens * (1.0f - s.velocity);
    }

    // Before a new voice: if kMaxVoices voices sound, the quietest of them is faded out.
    void makeRoom()
    {
        int sounding = 0;
        Slot* quietest = nullptr;
        for (Slot& s : slots)
        {
            if (!s.active || s.choking) continue;
            ++sounding;
            if (!quietest || s.level < quietest->level) quietest = &s;
        }
        if (sounding >= kMaxVoices) quietest->choke(kStealMs, rate);
    }

    // A slot for a fresh voice of `part` that belongs to `key`.
    Slot& freshSlot(int key, int part)
    {
        if (!playing.layered) makeRoom();
        Slot* slot = nullptr;
        for (Slot& s : slots) if (!s.active) { slot = &s; break; }
        if (slot) *slot = Slot(parts[size_t(part)]);
        else slot = &slots.emplace_back(parts[size_t(part)]);
        slot->active = true;
        slot->key = key;
        return *slot;
    }

    // The slot a note-on on `key` plays: the voice that sounds for it when the instrument
    // continues one, else a fresh one, the sounding one faded out.
    Slot& slotFor(int key, int part, bool& continuing)
    {
        continuing = false;
        if (!playing.layered)
            for (Slot& s : slots)
                if (s.active && !s.choking && s.key == key)
                {
                    if (playing.rehitContinues) { continuing = true; return s; }
                    s.choke(kStealMs, rate);
                    break;
                }
        return freshSlot(key, part);
    }

    void startVoice(Slot& s, int pitch, bool continuing)
    {
        s.sustained = s.released = false;
        s.voice.start(s.knobs, pitch, s.velocity, continuing);
    }

    void start(Slot& s, bool continuing, int note, int pitch, float velocity)
    {
        s.note = note;
        s.velocity = velocity;
        viewFor(s);
        s.ctl = 0;
        startVoice(s, pitch, continuing);
    }

    void releaseVoice(Slot& s)
    {
        s.sustained = false;
        s.released = true;
        s.voice.release();
    }

    Slot* monoSlot()
    {
        for (Slot& s : slots) if (s.active && !s.choking && s.key == kKeyMono) return &s;
        return nullptr;
    }

    // The pitch of `s` starts at `from` (a fractional note) and reaches `note` in Glide ms, at an
    // even number of semitones per second, a control tick at a time.
    void glideFrom(Slot& s, float from, int note) const
    {
        const float distance = from - float(note);
        const double ticks = playing.glideMs / 1000.0 * rate / double(kControlFrames);
        if (distance == 0.0f || ticks < 1.0) { s.glide = s.glideStep = 0.0f; return; }
        s.glide = distance;
        s.glideStep = float(double(distance) / ticks);
    }

    // The voice goes on at `note` without a new attack, gliding there from where it is.
    void moveTo(Slot& s, int note)
    {
        glideFrom(s, float(s.note) + s.glide, note);
        s.note = note;
        viewFor(s);
        s.ctl = 0;
        startVoice(s, note, true);
    }

    void unhold(int note) { numHeld = int(std::remove(held, held + numHeld, note) - held); }
    void hold(int note)
    {
        unhold(note);
        if (numHeld == kMaxHeld) { std::copy(held + 1, held + kMaxHeld, held); --numHeld; }
        held[numHeld++] = note;
    }

    void pedalUp()
    {
        sustain = false;
        for (Slot& s : slots)
            if (s.active && s.sustained)
            {
                if (s.choking) s.sustained = false;
                else releaseVoice(s);
            }
    }

    void noteOn(const Message& m)
    {
        if (m.part < 0 || size_t(m.part) >= parts.size()) return;
        // The velocity as MIDI carries it: 1 ... 127.
        const float velocity = float(std::clamp(int(std::lround(m.value * 127.0f)), 1, 127)) / 127.0f;
        if (playing.layered)
        {
            Slot& s = freshSlot(kKeyFirstNote + m.key, m.part);
            s.id = m.id;
            start(s, false, m.key, m.key, velocity);
        }
        else if (playing.pads)
        {
            const int group = size_t(m.part) < playing.groups.size() ? playing.groups[size_t(m.part)] : 0;
            bool continuing = false;
            Slot& s = slotFor(group != 0 ? kKeyFirstGroup + group : kKeyFirstPad + m.part, m.part, continuing);
            s.fromKey = false;
            start(s, continuing, m.part, m.key, velocity);
        }
        else if (playing.mode == Mode::Poly)
        {
            hold(m.key);
            bool continuing = false;
            Slot& s = slotFor(kKeyFirstNote + m.key, m.part, continuing);
            start(s, continuing, m.key, m.key, velocity);
        }
        else
        {
            // Mono and Legato: the one voice plays the newest key. Legato takes the voice over
            // while another key is held; otherwise a fresh voice attacks, gliding (Mono) from
            // where the voice it replaces was.
            const bool legato = playing.mode == Mode::Legato;
            hold(m.key);
            Slot* current = monoSlot();
            if (legato && current && numHeld > 1) { moveTo(*current, m.key); return; }
            const float from = current ? float(current->note) + current->glide : 0.0f;
            if (current) current->choke(kStealMs, rate);
            Slot& s = freshSlot(kKeyMono, m.part);
            if (current && !legato) glideFrom(s, from, m.key);
            start(s, false, m.key, m.key, velocity);
        }
    }

    // A released key releases the voice it started; the pedal holds a key's voice. In Mono and
    // Legato the voice of the newest key goes back to the newest key still held.
    void noteOff(const Message& m)
    {
        const int note = playing.pads ? m.part : m.key;
        if (!playing.pads && !playing.layered) unhold(note);
        for (Slot& s : slots)
        {
            if (!s.active || s.choking || s.released) continue;
            if (playing.layered ? s.id != m.id : s.note != note) continue;
            if (s.key == kKeyMono && !poly() && numHeld > 0) moveTo(s, held[numHeld - 1]);
            else if (s.fromKey && sustain) s.sustained = true;
            else releaseVoice(s);
        }
    }

    void handle(const Message& m)
    {
        switch (m.kind)
        {
            case Message::NoteOn: noteOn(m); break;
            case Message::NoteOff: noteOff(m); break;
            case Message::Pedal:
                if (playing.pads) break;
                if (m.value >= 0.5f) sustain = true;
                else pedalUp();
                break;
            case Message::Bend:
            {
                // The bend as MIDI carries it: 14 bits, -8192 ... 8191.
                const int b = std::clamp(int(std::lround(double(m.value) * (m.value >= 0.0f ? 8191.0 : 8192.0))), -8192, 8191);
                bend = float(b) / (b >= 0 ? 8191.0f : 8192.0f);
                break;
            }
        }
    }

    // `n` samples of one voice, added into out. The voice renders up to the end of its control
    // tick at a time; it leaves the pool when it is finished or faded out.
    void renderSlot(Slot& s, float* out, size_t n)
    {
        float buffer[kControlFrames];
        size_t pos = 0;
        while (pos < n && s.active)
        {
            if (s.ctl <= 0) { control(s); s.ctl = kControlFrames; }
            const int m = int(std::min(size_t(s.ctl), n - pos));
            s.voice.render(buffer, m);
            for (int j = 0; j < m; ++j)
            {
                const float o = buffer[j] * s.outGain * s.chokeGain;
                out[pos + size_t(j)] += o;
                s.level = std::max(std::fabs(o), s.level * followMul);
                if (s.choking) s.chokeGain *= s.chokeMul;
            }
            s.ctl -= m;
            pos += size_t(m);
            if (s.voice.finished() || (s.choking && s.chokeGain < 1e-5f)) s.active = false;
        }
    }

    bool sounding() const
    {
        for (const Slot& s : slots) if (s.active) return true;
        return false;
    }
};

}  // namespace detail

// Plays messages on a pool of copies of the parts' voice prototypes, as the engine would
// (Playing, and the rules at the top of this file), for `length` seconds. With ringOut >= 0 the
// render ends `ringOut` seconds after the last voice is over, and at `length` at the latest.
// A Voice is written as the engine will run it (the template's Voice.h), with the same four calls:
//   void start(const Knobs& knobs, int note, float velocity, bool continuing);
//       a note-on. `knobs` stays valid while the voice sounds and is updated before every
//       render(); the pitch is knobs.hz(note), read in render(), so that the voice bends and
//       glides. `velocity` 0..1 may colour the sound; the level by velocity is the pool's (Vel
//       Sens). `continuing` is true when the note-on takes over this voice while it sounds (a
//       re-hit the instrument continues, a legato note, a return to a key still held): go on at
//       the new note with no new attack. A voice that draws random numbers seeds its generator
//       with kVoiceSeed here when `continuing` is false.
//   void release();                          the note-off
//   void render(float* out, int frames);     the next 1 ... 16 samples at knobs.rate, written
//   bool finished() const;                   true once it is silent for good
// and it can be copied and assigned: every fresh note starts on a copy of its part's prototype
// (which carries the spike's Params, as a pointer).
template <class Voice>
Samples perform(std::vector<Message> messages, const std::vector<Voice>& parts, const Playing& playing,
                double rate, double length, double ringOut = -1.0)
{
    auto sampleOf = [rate](const Message& m) { return size_t(std::max(0LL, std::llround(m.time * rate))); };
    std::stable_sort(messages.begin(), messages.end(),
                     [&](const Message& a, const Message& b) { return sampleOf(a) < sampleOf(b); });
    detail::Performer<Voice> pool(parts, playing, rate);
    const size_t n = size_t(std::max(0.0, length) * rate + 0.5);
    Samples out(n, 0.0f);
    size_t pos = 0, next = 0;
    while (pos < n)
    {
        for (; next < messages.size() && sampleOf(messages[next]) <= pos; ++next) pool.handle(messages[next]);
        size_t until = next < messages.size() ? std::min(n, sampleOf(messages[next])) : n;
        if (ringOut >= 0 && next == messages.size())
        {
            // No message is left: go on a control tick at a time until the last voice is over.
            if (!pool.sounding())
            {
                out.resize(std::min(n, pos + size_t(ringOut * rate + 0.5)));
                break;
            }
            until = std::min(until, pos + size_t(kControlFrames));
        }
        for (auto& s : pool.slots) if (s.active) pool.renderSlot(s, out.data() + pos, until - pos);
        pos = until;
    }
    return out;
}

// Plays a score: event.part picks the voice prototype.
template <class Voice>
Samples play(const Score& score, const std::vector<Voice>& parts, const Playing& playing = {}, double rate = kRate)
{
    return perform(messagesOf(score), parts, playing, rate, score.length, score.ringOut);
}

template <class Voice>
Samples play(const Score& score, const Voice& voice, const Playing& playing = {}, double rate = kRate)
{
    return play(score, std::vector<Voice>{voice}, playing, rate);
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
    // highest (no octave too low). Octave guard (no octave too high): halved when the peak near
    // twice the lag closes half the gap to 1 and the halved pitch's odd harmonics (0.5, 1.5 ...
    // 4.5 f) together come within 25 dB of the strongest harmonic.
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
    if (maxLag < minLag + 3) { std::printf("f0 none (window too short)\n"); return 1; }
    std::vector<double> rs(maxLag + 2, 0.0);
    for (size_t l = minLag; l <= maxLag + 1 && l < n; ++l) rs[l] = r(l);
    double top = -1;
    for (size_t l = minLag + 1; l <= maxLag; ++l)
        if (rs[l] > rs[l - 1] && rs[l] >= rs[l + 1]) top = std::max(top, rs[l]);
    if (top < 0.5) { std::printf("f0 none (periodicity %.2f)\n", top); return 1; }
    size_t lag = 0;
    for (size_t l = minLag + 1; l <= maxLag; ++l)
        if (rs[l] > rs[l - 1] && rs[l] >= rs[l + 1] && rs[l] >= 0.9 * top) { lag = l; break; }
    // The top of a parabola through a, b, c (offset kept within +-0.5; none when b is no maximum).
    auto refine = [](double a, double b, double c, double* value) {
        const double den = a - 2 * b + c;
        const double d = den < 0 ? std::clamp(0.5 * (a - c) / den, -0.5, 0.5) : 0.0;
        *value = std::min(1.0, b - 0.25 * (a - c) * d);
        return d;
    };
    double periodicity = 0;
    double period = double(lag) + refine(rs[lag - 1], rs[lag], rs[lag + 1], &periodicity);
    std::vector<double> w(n);
    for (size_t i = 0; i < n; ++i) w[i] = 0.5 - 0.5 * std::cos(2 * kPi * double(i) / double(n - 1));
    const size_t lag2 = size_t(std::lround(2 * period));
    if (lag2 + 3 < n * 2 / 3 && rate / (2 * period) >= 30.0)
    {
        double around[5];
        size_t j = 0;
        for (size_t i = 0; i < 5; ++i)
        {
            around[i] = r(lag2 - 2 + i);
            if (around[i] > around[j]) j = i;
        }
        double top2 = around[j], offset2 = 0;
        if (j > 0 && j < 4) offset2 = refine(around[j - 1], around[j], around[j + 1], &top2);
        const double f = rate / period;
        double strongest = 0, odd = 0;
        for (int k = 1; k <= 10; ++k) strongest = std::max(strongest, levelNear(w, seg, rate, k * f));
        for (int k = 1; k <= 9; k += 2) odd += std::pow(levelNear(w, seg, rate, k * f / 2), 2);
        if (top2 > periodicity && top2 - periodicity >= 0.5 * (1 - periodicity) &&
            odd >= strongest * strongest * std::pow(10.0, -2.5))
        {
            period = double(lag2 - 2 + j) + offset2;
            periodicity = top2;
            std::printf("octave guard: halved\n");
        }
    }
    const double f0 = rate / period;
    std::printf("f0 %.3f Hz  periodicity %.4f\n", f0, periodicity);
    const double periods = double(n) / rate * f0;
    if (periods < 4) std::printf("few periods: the window holds %.1f (under 4), levels are rough\n", periods);
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
