// {{APP}}Engine.cpp - the {{APP}} sound engine and its C interface: the platform around the
// instrument's voice (Voice.h).
//
// One engine is a pool of voices and seventeen knob sets: the keyboard's and one per pad. At
// most 16 voices sound at once: a note that would be the 17th steals the quietest, which fades
// out in 3 ms.
//   * In keyboard mode every note plays the keyboard set at its own pitch, as Voice Mode says,
//     and the voice follows the keyboard set while it sounds:
//       Poly    a voice of its own for every note;
//       Mono    one voice, the last key held: a new note attacks anew (a fresh voice, the one it
//               replaces fades out in 3 ms), letting the newest key go returns the voice to the
//               newest key still held, without a new attack (continuing), and letting the last
//               key go releases it;
//       Legato  as Mono, but a note played while another key is held takes the voice over
//               without a new attack (continuing); a note played with no key held attacks.
//     Glide moves the pitch from where the voice was to the new note in Glide ms, at an even
//     number of semitones per second (Knobs::glide): in Mono at every note while the voice still
//     sounds, in Legato between notes that overlap, and on the return to a key still held. A
//     legato note and a return keep the voice's velocity and LFOs. The keys held are a stack of
//     16 (the oldest falls out), kept in every voice mode, so that a mode changed while keys are
//     down finds them. A voice mode changed while voices sound leaves them to their note-offs.
//   * The sustain pedal (CC 64, down from 64 up) holds a key's voice its note-off would release,
//     in every voice mode, until the pedal comes up. It holds no pad's voice.
//   * In pad mode notes 36-51 hit pads 1-16. A pad hit is a key press frozen: its voice takes the
//     pad's set at the hit and sounds at the pad's note. The pads of one group share one voice; a
//     pad whose group is Off has one of its own.
//   * A note-on on a voice that sounds (the same key, or a pad of the same group) continues it
//     or fades it out for a fresh one, as the instrument says (kRehitContinues).
//
//   voices -> Volume, Vel Sens, Pan -> sum (L, R) -> kOutputLevel -> [half-band decimator] -> limiter -> out
//
// Below 88.2 kHz everything up to kOutputLevel runs at twice the host rate (the internal rate),
// and a half-band filter (HalfBand.h) decimates it, so that what a voice makes above the host's
// band does not fold back into it. From 88.2 kHz up the internal rate is the host's and there is
// no filter. The limiter always runs at the host rate.
//
// What a voice plays is its Knobs (viewFor): the knob set, moved by the voice's two LFOs, the
// hit's velocity and, for a keyboard voice, the wheels, worked out every 16 internal samples
// (a control tick).
//
// MIDI controllers: every knob of the keyboard set listens to a control change number (it comes
// with one, and can be given another: "learn"), and a control change puts the knob where its
// value says, at the control change's place in the block.

// A product and a sum stay two roundings. An optimised build would otherwise fuse them into one
// multiply-add where a debug build does not, and the two builds would render different last
// bits: the engine's sound must be the same in both, and the same as the references it is
// tested against.
#pragma clang fp contract(off)

#include "{{APP}}DSP.h"
#include "HalfBand.h"
#include "Lfo.h"
#include "MidiQueue.h"
#include "ParamTable.h"
#include "Voice.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

using namespace {{APP_LOWER}};

namespace {

bool validSet(int set) { return set >= 0 && set < {{APP_UPPER}}_NUM_SETS; }

// For every knob, the amounts that move it (-1 where a source cannot), how far the wheels move it
// at the top, and the knobs that anything can move: an LFO, the velocity or a wheel.
struct Moves
{
    int lfo[kNumKnobs][kNumLfos];
    int vel[kNumKnobs];
    float modWheel[kNumKnobs];
    float pressure[kNumKnobs];
    int knobs[kNumKnobs];
    int numKnobs;
};

constexpr Moves makeMoves()
{
    Moves m{};
    for (const Target& t : kModWheelTargets) if (t.param != kNoTarget) m.modWheel[t.param] += t.depth;
    for (const Target& t : kAftertouchTargets) if (t.param != kNoTarget) m.pressure[t.param] += t.depth;
    for (int i = 0; i < kNumKnobs; ++i)
    {
        bool moves = m.modWheel[i] != 0.0f || m.pressure[i] != 0.0f;
        for (int k = 0; k < kNumLfos; ++k) { m.lfo[i][k] = amountOf(k, i); moves = moves || m.lfo[i][k] >= 0; }
        m.vel[i] = velAmountOf(i);
        moves = moves || m.vel[i] >= 0;
        if (moves) m.knobs[m.numKnobs++] = i;
    }
    return m;
}

constexpr Moves kMoves = makeMoves();

// The seeds of the LFOs' generators: a voice's at every hit with LFO Start = Hit, the engine's
// free-running ones at every reset.
constexpr uint32_t kHitSeed = 0x9E3779B9u, kFreeSeed = 0x2F6E2B11u;
bool validPad(int pad) { return pad >= 0 && pad < {{APP_UPPER}}_NUM_PADS; }
int  padSet(int pad) { return pad + 1; }

// The note Send to pad gives a pad when no note has been played: C2.
constexpr int kSendNoteIfNone = 36;

// The internal samples of a control tick, and of the engine's own blocks.
constexpr int kControlFrames = 16;
constexpr int kChunk = 64;

// What a voice belongs to: a key in keyboard mode, a group of pads, or a pad whose group is Off.
// A note-on on what a sounding voice belongs to finds that voice.
enum VoiceKey
{
    kKeyFirstNote = 0,                                          // + note
    kKeyFirstGroup = kKeyFirstNote + 128,                       // + group - 1
    kKeyFirstPad = kKeyFirstGroup + {{APP_UPPER}}_NUM_GROUPS,   // + pad
    kKeyMono = kKeyFirstPad + {{APP_UPPER}}_NUM_PADS,           // the one voice of Mono and Legato
};

// The keys held down that Mono and Legato remember, newest last.
constexpr int kMaxHeld = 16;

inline float dbToGain(float db) { return std::pow(10.0f, db / 20.0f); }

// tanh as a Padé approximant, exact enough for a limiter and cheap.
inline float fastTanh(float x)
{
    if (x > 4.97f) return 1.0f;
    if (x < -4.97f) return -1.0f;
    const float x2 = x * x;
    const float a = x * (135135.0f + x2 * (17325.0f + x2 * (378.0f + x2)));
    const float b = 135135.0f + x2 * (62370.0f + x2 * (3150.0f + x2 * 28.0f));
    return a / b;
}

// One voice of the pool: the instrument's Voice and what the platform keeps around it.
struct Slot
{
    bool active = false, choking = false;
    bool fromKey = true;            // a key's voice plays the keyboard set as it is now, whatever the mode
    int key = 0;                    // what it belongs to (VoiceKey)
    int note = 0;                   // the MIDI note whose note-off releases it
    bool sustained = false;         // its key is up, the sustain pedal holds it
    bool released = false;          // the voice has been released (Voice::release)
    float velocity = 1.0f;
    float glide = 0.0f;             // semitones the pitch still is from the note (Knobs::glide)
    float glideStep = 0.0f;         // what a control tick takes off it
    Knobs knobs;
    // A pad's knob set as it stood at the hit, normalised and as plain values: what its Knobs are
    // worked out from. A key's voice reads the keyboard set instead.
    float setAtHit[kNumParams] = {};
    float plainAtHit[kNumParams] = {};
    Lfo lfo[kNumLfos];
    int ctl = 0;                    // internal samples left in this control tick
    float velocityGain = 1.0f;      // VEL>Volume's gain
    float outGain = 1.0f, panL = 1.0f, panR = 1.0f;
    float chokeGain = 1.0f, chokeMul = 1.0f;
    float level = 0.0f;             // a peak follower on the output: what voice stealing compares
    Voice voice;

    // Fades the voice out: it falls 40 dB in `ms`.
    void choke(float ms, double rate)
    {
        if (choking) return;
        choking = true;
        const float tc = std::max(ms, 1.0f) * 0.001f / 4.6f;
        chokeMul = (float)std::exp(-1.0 / (tc * rate));
    }
};

} // namespace

// ---------------------------------------------------------------------------------------------
// The engine
// ---------------------------------------------------------------------------------------------
struct {{APP}}Engine
{
    {{APP}}Engine()
    {
        for (int s = 0; s < {{APP_UPPER}}_NUM_SETS; ++s)
            for (int i = 0; i < kNumParams; ++i) sets_[s][i].store(param(i).toNormalised(param(i).def), std::memory_order_relaxed);
        resetControllers();
        loadDefaultKit();
        prepare(44100.0);
    }

    // ----- knob sets (any thread) ---------------------------------------------------------
    float getNormalised(int set, int i) const { return sets_[set][i].load(std::memory_order_relaxed); }
    float get(int set, int i) const { return param(i).toPlain(getNormalised(set, i)); }
    void  setNormalised(int set, int i, float v)
    {
        if (std::isnan(v)) return;
        sets_[set][i].store(std::clamp(v, 0.0f, 1.0f), std::memory_order_relaxed);
    }
    void  set(int set, int i, float plain) { if (!std::isnan(plain)) setNormalised(set, i, param(i).toNormalised(plain)); }

    void setProgram(int set, int index)
    {
        if (index < 0 || index >= (int)programs().size()) return;
        program_[set].store(index, std::memory_order_relaxed);
        const Program& p = programs()[(size_t)index];
        for (int i = 0; i < kNumParams; ++i)
            if (programSets(i)) this->set(set, i, p.values[i]);
    }
    void setProgramIndex(int set, int index)
    {
        if (index >= 0 && index < (int)programs().size()) program_[set].store(index, std::memory_order_relaxed);
    }
    int program(int set) const { return program_[set].load(std::memory_order_relaxed); }

    void setMode(int mode)
    {
        if (mode == {{APP_UPPER}}_MODE_KEYBOARD || mode == {{APP_UPPER}}_MODE_PADS) mode_.store(mode, std::memory_order_relaxed);
    }
    int mode() const { return mode_.load(std::memory_order_relaxed); }

    int  padNote(int pad) const { return padNote_[pad].load(std::memory_order_relaxed); }
    void setPadNote(int pad, int note) { if (note >= 0 && note <= 127) padNote_[pad].store(note, std::memory_order_relaxed); }
    int  padHits(int pad) const { return padHits_[pad].load(std::memory_order_relaxed); }
    int  padGroup(int pad) const { return padGroup_[pad].load(std::memory_order_relaxed); }
    void setPadGroup(int pad, int group) { if (group >= 0 && group <= {{APP_UPPER}}_NUM_GROUPS) padGroup_[pad].store(group, std::memory_order_relaxed); }

    // Send to pad: the keyboard set and its program go to the pad's set, the last note played to
    // the pad's note. The group stays.
    void sendToPad(int pad)
    {
        const int set = padSet(pad);
        for (int i = 0; i < kNumParams; ++i) sets_[set][i].store(getNormalised({{APP_UPPER}}_KEYBOARD_SET, i), std::memory_order_relaxed);
        program_[set].store(program({{APP_UPPER}}_KEYBOARD_SET), std::memory_order_relaxed);
        const int last = lastNote();
        padNote_[pad].store(last >= 0 ? last : kSendNoteIfNone, std::memory_order_relaxed);
    }

    void loadDefaultKit()
    {
        for (int pad = 0; pad < {{APP_UPPER}}_NUM_PADS; ++pad)
        {
            const KitPad& k = kDefaultKit[pad];
            const int s = padSet(pad);
            setProgram(s, k.program);
            set(s, kOctave, param(kOctave).def);             // a program leaves the octave alone
            for (const Override& o : k.overrides) if (validParam(o.param)) set(s, o.param, o.value);
            setPadNote(pad, k.note);
            setPadGroup(pad, k.group);
        }
    }

    int lastNote() const { return lastNote_.load(std::memory_order_relaxed); }
    int soundingVoices() const { return sounding_.load(std::memory_order_relaxed); }
    int latency() const { return latency_.load(std::memory_order_relaxed); }

    void requestReset() { resetPending_.store(true, std::memory_order_release); }   // any thread

    // ----- MIDI controllers (any thread) --------------------------------------------------
    int controllerOf(int knob) const { return controller_[knob].load(std::memory_order_relaxed); }

    // A controller serves one knob: whoever had it before has none. A reserved one is not taken.
    void setController(int knob, int cc)
    {
        if (cc < 0) { controller_[knob].store(kNoController, std::memory_order_relaxed); return; }
        if (cc > 127 || controllerReserved(cc)) return;
        for (int i = 0; i < kNumKnobs; ++i)
            if (i != knob && controller_[i].load(std::memory_order_relaxed) == cc) controller_[i].store(kNoController, std::memory_order_relaxed);
        controller_[knob].store((int8_t)cc, std::memory_order_relaxed);
    }

    void resetControllers()
    {
        for (int i = 0; i < kNumKnobs; ++i) controller_[i].store((int8_t)standardController(i), std::memory_order_relaxed);
    }

    // The knob that takes the next controller that moves; -1 for none.
    void learn(int knob) { learning_.store(knob, std::memory_order_relaxed); }
    int  learning() const { return learning_.load(std::memory_order_relaxed); }

    // Counts what MIDI did behind a window's back: a knob moved by its controller, a controller learnt.
    // Released after the knob or controller it counts, acquired here: a reader that sees the new
    // count also sees what changed.
    unsigned changes() const { return changes_.load(std::memory_order_acquire); }

    // ----- MIDI ---------------------------------------------------------------------------
    void postMidi(uint8_t status, uint8_t d1, uint8_t d2, int offset) { posted_.post(status, d1, d2, offset); }   // any thread

    void midi(uint8_t status, uint8_t d1, uint8_t d2, int offset)   // audio thread
    {
        if (numEvents_ >= kMaxEvents) return;
        int i = numEvents_++;                                       // keep the list sorted by offset
        while (i > 0 && events_[i - 1].sampleOffset > offset) { events_[i] = events_[i - 1]; --i; }
        events_[i] = MidiEvent{ offset < 0 ? 0 : offset, status, d1, d2 };
    }

    // ----- lifecycle ----------------------------------------------------------------------
    void prepare(double sampleRate)
    {
        if (!(sampleRate > 0.0) || !std::isfinite(sampleRate)) return;
        oversampling_ = sampleRate < kOversampleBelow ? 2 : 1;
        internalRate_ = sampleRate * oversampling_;
        followMul_ = (float)std::exp(-1.0 / (kFollowSeconds * internalRate_));
        decimL_.design();
        decimR_.design();
        latency_.store(oversampling_ == 2 ? HalfBand::kLatency : 0, std::memory_order_relaxed);
        reset();
    }

    void reset()
    {
        for (Slot& s : slots_) s = Slot();
        lastNote_.store(-1, std::memory_order_relaxed);
        decimL_.reset();
        decimR_.reset();
        for (int k = 0; k < kNumLfos; ++k) freeLfo_[k].restart(kFreeSeed + (uint32_t)k);
        freeTick_ = 0;
        bend_ = modWheel_ = pressure_ = 0.0f;
        numHeld_ = 0;
        sustain_ = false;
        sounding_.store(0, std::memory_order_relaxed);
        publishProbe();
    }

    void process(float* left, float* right, int frames)
    {
        if (resetPending_.exchange(false, std::memory_order_acq_rel)) reset();

        // MIDI posted from other threads joins this block at its sample offset, as long as the
        // block has room for it; the rest stays in the queue and plays in the next block.
        posted_.drain([this](const MidiEvent& e) {
            if (numEvents_ >= kMaxEvents) return false;
            midi(e.status, e.data1, e.data2, e.sampleOffset);
            return true;
        });

        readKeyboardSet();

        // Sample-accurate MIDI: render up to each event, then apply it.
        int pos = 0;
        for (int e = 0; e < numEvents_; ++e)
        {
            const int offset = std::clamp(events_[e].sampleOffset, 0, frames);
            if (offset > pos) { render(left, right, pos, offset); pos = offset; }
            handleMidi(events_[e]);
        }
        render(left, right, pos, frames);
        numEvents_ = 0;

        int sounding = 0;
        for (const Slot& s : slots_) if (s.active && !s.choking) ++sounding;
        sounding_.store(sounding, std::memory_order_relaxed);
        publishProbe();
    }

    // ----- the probe (any thread) -----------------------------------------------------------
    void probe({{APP}}VoiceProbe& out) const
    {
        out.freshStarts = freshStarts_.load(std::memory_order_relaxed);
        out.continuingStarts = continuingStarts_.load(std::memory_order_relaxed);
        out.releases = releases_.load(std::memory_order_relaxed);
        out.keysUnreleased = keysUnreleased_.load(std::memory_order_relaxed);
        out.keysSustained = keysSustained_.load(std::memory_order_relaxed);
        out.keysHeld = keysHeld_.load(std::memory_order_relaxed);
        out.monoNote = monoNote_.load(std::memory_order_relaxed);
        out.monoGlide = monoGlide_.load(std::memory_order_relaxed);
    }

private:
    // What the probe shows of the voices as they stand now.
    void publishProbe()
    {
        int unreleased = 0, sustained = 0, monoNote = -1;
        float monoGlide = 0.0f;
        for (const Slot& s : slots_)
        {
            if (!s.active || s.choking) continue;
            if (s.fromKey && !s.released) ++unreleased;
            if (s.fromKey && s.sustained) ++sustained;
            if (s.key == kKeyMono) { monoNote = s.note; monoGlide = s.glide; }
        }
        keysUnreleased_.store(unreleased, std::memory_order_relaxed);
        keysSustained_.store(sustained, std::memory_order_relaxed);
        keysHeld_.store(numHeld_, std::memory_order_relaxed);
        monoNote_.store(monoNote, std::memory_order_relaxed);
        monoGlide_.store(monoGlide, std::memory_order_relaxed);
    }

    // At most {{APP_UPPER}}_MAX_VOICES sound; the other slots let the voices being choked fade out. 40
    // leave room for 16 voices choked at once while 16 new ones start (all pads hit together),
    // so that a choked voice is cut only when even that is not enough.
    static constexpr int kNumSlots = 40;
    static_assert(kNumSlots > {{APP_UPPER}}_MAX_VOICES, "room for the voices being choked");
    static constexpr int kMaxEvents = 256;

    // A stolen voice, and one a re-hit replaces, falls 40 dB in this long; All Sound Off and All
    // Notes Off take this long.
    static constexpr float kStealMs = 3.0f;
    static constexpr float kAllOffMs = 10.0f;

    // Below this host rate the voices run at twice it.
    static constexpr double kOversampleBelow = 88200.0;

    // How fast a voice's peak follower falls: what voice stealing hears as its loudness.
    static constexpr double kFollowSeconds = 0.02;

    // The keyboard set, normalised and as plain values, read once per block.
    void readKeyboardSet()
    {
        for (int i = 0; i < kNumParams; ++i)
        {
            keyNorm_[i] = getNormalised({{APP_UPPER}}_KEYBOARD_SET, i);
            keyPlain_[i] = param(i).toPlain(keyNorm_[i]);
        }
    }

    // Where every knob of `s` stands now. A knob a source moves stands at
    //   knob + sum of (LFO amount * LFO value) - VEL amount * (1 - velocity)  (+ the wheels),
    // in parts of its travel and no further than its ends; Volume's VEL amount is a gain
    // instead, and the pitch bend is a pitch in semitones. The one place that adds modulation:
    // with every amount and wheel at rest, the Knobs are the knob set itself, value for value.
    void viewFor(Slot& s) const
    {
        Knobs& out = s.knobs;
        const bool keyboard = s.fromKey;
        const float* set = keyboard ? keyNorm_ : s.setAtHit;
        const float* plain = keyboard ? keyPlain_ : s.plainAtHit;
        std::copy(plain, plain + kNumParams, out.v);

        float lfoValue[kNumLfos];
        for (int k = 0; k < kNumLfos; ++k)
            lfoValue[k] = s.lfo[k].value(std::clamp((int)std::lround(out.v[kLfo1Shape + 2 * k]), 0, (int)kNumLfoShapes - 1));
        const float soft = 1.0f - s.velocity;

        for (int n = 0; n < kMoves.numKnobs; ++n)
        {
            const int i = kMoves.knobs[n];
            float position = set[i];
            bool moved = false;
            for (int k = 0; k < kNumLfos; ++k)
            {
                const int slot = kMoves.lfo[i][k];
                const float amount = slot >= 0 ? out.v[slot] / 100.0f : 0.0f;
                if (amount != 0.0f) { position += amount * lfoValue[k]; moved = true; }
            }
            const float velAmount = kMoves.vel[i] >= 0 && i != kVolume ? out.v[kMoves.vel[i]] / 100.0f : 0.0f;
            if (velAmount != 0.0f) { position -= velAmount * soft; moved = true; }
            if (keyboard)
            {
                if (kMoves.modWheel[i] != 0.0f && modWheel_ != 0.0f) { position += kMoves.modWheel[i] * modWheel_; moved = true; }
                if (kMoves.pressure[i] != 0.0f && pressure_ != 0.0f) { position += kMoves.pressure[i] * pressure_; moved = true; }
            }
            if (moved) out.v[i] = param(i).toPlain(std::clamp(position, 0.0f, 1.0f));
        }

        s.velocityGain = std::max(0.0f, 1.0f - out.v[velAmountOf(kVolume)] / 100.0f * soft);
        out.bend = keyboard ? bend_ * (bend_ >= 0.0f ? out.v[kBendUp] : out.v[kBendDown]) : 0.0f;
        out.glide = s.glide;
        out.rate = internalRate_;
    }

    // A control tick of `s`: its Knobs as they stand now, its LFOs and its glide a tick on, and
    // its gains: Volume, VEL>Volume, Vel Sens and Pan.
    void control(Slot& s) const
    {
        viewFor(s);
        for (int k = 0; k < kNumLfos; ++k)
            s.lfo[k].advance(s.knobs[kLfo1Rate + 2 * k] * (float)kControlFrames / (float)internalRate_);
        if (s.glide != 0.0f)
        {
            const float next = s.glide - s.glideStep;
            s.glide = (next > 0.0f) == (s.glide > 0.0f) ? next : 0.0f;     // there once it would pass the note
        }
        const float sensitivity = 1.0f - s.knobs[kVelSens] / 100.0f * (1.0f - s.velocity);
        s.outGain = dbToGain(s.knobs[kVolume]) * s.velocityGain * sensitivity;
        const float pan = s.knobs[kPan] / 100.0f;
        s.panL = std::min(1.0f, 1.0f - pan);
        s.panR = std::min(1.0f, 1.0f + pan);
    }

    // A hit's LFOs: restarted (Hit), or where the engine's free-running ones stand (Free).
    void startLfos(Slot& s, int start) const
    {
        for (int k = 0; k < kNumLfos; ++k)
        {
            if (start == kLfoStartFree) s.lfo[k] = freeLfo_[k];
            else s.lfo[k].restart(kHitSeed + (uint32_t)k);
        }
    }

    // The free-running LFOs go round at the keyboard set's rates, one control tick at a time.
    void turnFreeLfos()
    {
        for (int k = 0; k < kNumLfos; ++k)
            freeLfo_[k].advance(keyPlain_[kLfo1Rate + 2 * k] * (float)kControlFrames / (float)internalRate_);
    }

    void handleMidi(const MidiEvent& ev)
    {
        if (ev.isNoteOn())
        {
            const float velocity = ev.data2 / 127.0f;
            if (mode() != {{APP_UPPER}}_MODE_KEYBOARD)
            {
                if (validPad(ev.data1 - {{APP_UPPER}}_FIRST_PAD_NOTE)) padHit(ev.data1 - {{APP_UPPER}}_FIRST_PAD_NOTE, ev.data1, velocity);
            }
            else if (voiceMode() == kVoicePoly) noteOn(ev.data1, velocity);
            else monoNoteOn(ev.data1, velocity, voiceMode() == kVoiceLegato);
        }
        else if (ev.isNoteOff()) noteOff(ev.data1);
        else if (ev.isAllNotesOff())
        {
            for (Slot& s : slots_) if (s.active) s.choke(kAllOffMs, internalRate_);
            forgetKeys();
        }
        else if (ev.isController() && ev.data1 == 121)      // Reset All Controllers
        {
            bend_ = modWheel_ = pressure_ = 0.0f;
            forgetKeys();
        }
        else if (ev.isController() && ev.data1 == 64)       // the sustain pedal
        {
            if (ev.data2 >= 64) sustain_ = true;
            else pedalUp();
        }
        else if (ev.isController() && ev.data1 == 1) modWheel_ = ev.data2 / 127.0f;
        else if (ev.isController() && !controllerReserved(ev.data1)) controllerMoved(ev.data1, ev.data2);
        else if (ev.isAftertouch()) pressure_ = ev.data1 / 127.0f;
        else if (ev.isPitchBend())          // -1 at the bottom, +1 at the top
        {
            const int bend = ev.pitchBend();
            bend_ = (float)bend / (bend >= 0 ? 8191.0f : 8192.0f);
        }
    }

    // A controller that is not one of MIDI's own: the knob that is learning takes it, and the
    // keyboard knob that listens to it goes where its value says. The block plays the new place
    // from here on, as the setters' next block would.
    void controllerMoved(int cc, int value)
    {
        bool changed = false;
        int learning = learning_.load(std::memory_order_relaxed);
        if (learning >= 0 && learning_.compare_exchange_strong(learning, -1, std::memory_order_relaxed))
        {
            setController(learning, cc);
            changed = true;
        }
        for (int i = 0; i < kNumKnobs; ++i)
            if (controller_[i].load(std::memory_order_relaxed) == cc)
            {
                // 64 is the middle of a controller's travel: a knob that has a middle of its own
                // (-100 ... 100 %) stands on it there, which 64 / 127 would miss.
                const Param& p = param(i);
                const bool onMiddle = value == 64 && p.max > 0.0f && p.min == -p.max;
                setNormalised({{APP_UPPER}}_KEYBOARD_SET, i, onMiddle ? 0.5f : (float)value / 127.0f);
                keyNorm_[i] = getNormalised({{APP_UPPER}}_KEYBOARD_SET, i);
                keyPlain_[i] = p.toPlain(keyNorm_[i]);
                changed = true;
            }
        if (changed) changes_.fetch_add(1, std::memory_order_release);
    }

    // Before a new voice: if {{APP_UPPER}}_MAX_VOICES voices sound, the quietest of them is choked,
    // in kStealMs.
    void makeRoom()
    {
        int sounding = 0;
        Slot* quietest = nullptr;
        for (Slot& s : slots_)
        {
            if (!s.active || s.choking) continue;
            ++sounding;
            if (!quietest || s.level < quietest->level) quietest = &s;
        }
        if (sounding >= {{APP_UPPER}}_MAX_VOICES) quietest->choke(kStealMs, internalRate_);
    }

    // The slot a new voice takes: a free one, or else the quietest of those being choked, which
    // is cut. After makeRoom at most {{APP_UPPER}}_MAX_VOICES - 1 voices sound, so one of the two is
    // there.
    Slot& freeSlot()
    {
        Slot* quietest = nullptr;
        for (Slot& s : slots_)
        {
            if (!s.active) return s;
            if (!s.choking) continue;
            if (!quietest || s.level * s.chokeGain < quietest->level * quietest->chokeGain) quietest = &s;
        }
        return quietest ? *quietest : slots_[0];
    }

    // The slot a note-on on `key` plays: the voice that sounds for it when the instrument
    // continues one (`continuing` is then true), else a fresh one. A voice being choked no longer
    // belongs to its key; one the instrument does not continue is choked now.
    Slot& slotFor(int key, bool& continuing)
    {
        continuing = false;
        for (Slot& s : slots_)
            if (s.active && !s.choking && s.key == key)
            {
                if (kRehitContinues) { continuing = true; return s; }
                s.choke(kStealMs, internalRate_);
                break;
            }
        return freshSlot(key);
    }

    // A slot for a fresh voice that belongs to `key`.
    Slot& freshSlot(int key)
    {
        makeRoom();
        Slot& slot = freeSlot();
        slot = Slot();
        slot.active = true;
        slot.key = key;
        return slot;
    }

    // A note-on on `s`: the LFOs start, the Knobs are worked out for the hit, and the voice starts.
    void start(Slot& s, bool continuing, int note, int pitch, float velocity, const float* plain)
    {
        s.note = note;
        s.velocity = velocity;
        startLfos(s, (int)std::lround(plain[kLfoStart]));
        viewFor(s);
        s.ctl = 0;
        startVoice(s, pitch, continuing);
    }

    // The instrument's start and release, counted for the probe.
    void startVoice(Slot& s, int pitch, bool continuing)
    {
        s.sustained = s.released = false;
        s.voice.start(s.knobs, pitch, s.velocity, continuing);
        (continuing ? continuingStarts_ : freshStarts_).fetch_add(1, std::memory_order_relaxed);
    }

    void releaseVoice(Slot& s)
    {
        s.sustained = false;
        s.released = true;
        s.voice.release();
        releases_.fetch_add(1, std::memory_order_relaxed);
    }

    int voiceMode() const { return std::clamp((int)std::lround(keyPlain_[kVoiceMode]), 0, (int)kNumVoiceModes - 1); }

    // Poly: a key plays the keyboard set at its own pitch.
    void noteOn(int note, float velocity)
    {
        hold(note);
        bool continuing = false;
        Slot& s = slotFor(kKeyFirstNote + note, continuing);
        s.fromKey = true;
        start(s, continuing, note, note, velocity, keyPlain_);
        lastNote_.store(note, std::memory_order_relaxed);
    }

    // Mono and Legato: the one voice plays the newest key. Legato takes the voice over while
    // another key is held; otherwise a fresh voice attacks, gliding (Mono) from where the voice
    // it replaces was.
    void monoNoteOn(int note, float velocity, bool legato)
    {
        hold(note);
        Slot* current = monoSlot();
        if (legato && current && numHeld_ > 1) moveTo(*current, note);
        else
        {
            const float from = current ? (float)current->note + current->glide : 0.0f;
            if (current) current->choke(kStealMs, internalRate_);
            Slot& s = freshSlot(kKeyMono);
            s.fromKey = true;
            if (current && !legato) glideFrom(s, from, note);
            start(s, false, note, note, velocity, keyPlain_);
        }
        lastNote_.store(note, std::memory_order_relaxed);
    }

    // The voice of Mono and Legato, if it sounds.
    Slot* monoSlot()
    {
        for (Slot& s : slots_) if (s.active && !s.choking && s.key == kKeyMono) return &s;
        return nullptr;
    }

    // The voice goes on at `note` without a new attack, gliding there from where it is, with the
    // velocity and LFOs it has.
    void moveTo(Slot& s, int note)
    {
        glideFrom(s, (float)s.note + s.glide, note);
        s.note = note;
        viewFor(s);
        s.ctl = 0;
        startVoice(s, note, true);
    }

    // The pitch of `s` starts at `from` (a fractional note) and reaches `note` in Glide ms, at an
    // even number of semitones per second, a control tick at a time.
    void glideFrom(Slot& s, float from, int note) const
    {
        const float distance = from - (float)note;
        const double ticks = (double)keyPlain_[kGlide] / 1000.0 * internalRate_ / (double)kControlFrames;
        if (distance == 0.0f || ticks < 1.0) { s.glide = s.glideStep = 0.0f; return; }
        s.glide = distance;
        s.glideStep = (float)((double)distance / ticks);
    }

    // The stack of keys held, newest last: a key pressed again moves to the top; with 16 held
    // the oldest falls out.
    void hold(int note)
    {
        unhold(note);
        if (numHeld_ == kMaxHeld)
        {
            std::copy(held_ + 1, held_ + kMaxHeld, held_);
            --numHeld_;
        }
        held_[numHeld_++] = note;
    }

    void unhold(int note)
    {
        int* end = std::remove(held_, held_ + numHeld_, note);
        numHeld_ = (int)(end - held_);
    }

    // The pedal up: the voices it held are released.
    void pedalUp()
    {
        sustain_ = false;
        for (Slot& s : slots_)
            if (s.active && s.sustained)
            {
                if (s.choking) s.sustained = false;
                else releaseVoice(s);
            }
    }

    // All Notes Off, All Sound Off, Reset All Controllers: no key is held, the pedal is up.
    void forgetKeys()
    {
        numHeld_ = 0;
        pedalUp();
    }

    // A pad hit plays its group's voice, or the pad's own with Group Off, with the pad's set
    // frozen at the hit and at the pad's note.
    void padHit(int pad, int note, float velocity)
    {
        const int group = padGroup(pad);
        bool continuing = false;
        Slot& s = slotFor(group != 0 ? kKeyFirstGroup + group - 1 : kKeyFirstPad + pad, continuing);
        s.fromKey = false;
        padHits_[pad].fetch_add(1, std::memory_order_relaxed);
        const int set = padSet(pad);
        for (int i = 0; i < kNumParams; ++i)        // the pad's set, frozen at the hit
        {
            s.setAtHit[i] = getNormalised(set, i);
            s.plainAtHit[i] = param(i).toPlain(s.setAtHit[i]);
        }
        start(s, continuing, note, padNote(pad), velocity, s.plainAtHit);
    }

    // A released key releases the voices it started, a key's or a pad's; the pedal holds a key's.
    // In Mono and Legato the voice of the newest key goes back to the newest key still held.
    void noteOff(int note)
    {
        unhold(note);
        const bool mono = voiceMode() != kVoicePoly;
        for (Slot& s : slots_)
        {
            if (!s.active || s.choking || s.released || s.note != note) continue;
            if (s.key == kKeyMono && mono && numHeld_ > 0) moveTo(s, held_[numHeld_ - 1]);
            else if (s.fromKey && sustain_) s.sustained = true;
            else releaseVoice(s);
        }
    }

    // The peaks are left alone up to 0.6 and bent towards 1 above it.
    static float limit(float y)
    {
        const float size = std::fabs(y);
        if (size <= 0.6f) return y;
        const float bent = 0.6f + 0.4f * fastTanh((size - 0.6f) * 2.5f);
        return y < 0.0f ? -bent : bent;
    }

    // The bus at the internal rate: the level.
    static float bus(float x) { return x * kOutputLevel; }

    // The bus at the host rate: the limiter. Its output is flushed to zero when it is too small
    // to hear, so that silence is exact and no denormal tail lingers.
    static float limited(float y)
    {
        const float out = limit(y);
        return std::fabs(out) < 1e-20f ? 0.0f : out;
    }

    // `n` internal samples of one voice, added into l and r. The voice renders up to the end of
    // its control tick at a time; it leaves the pool when it is finished or faded out.
    void renderSlot(Slot& s, float* l, float* r, int n)
    {
        float buffer[kControlFrames];
        int pos = 0;
        while (pos < n && s.active)
        {
            if (s.ctl <= 0) { control(s); s.ctl = kControlFrames; }
            const int m = std::min(s.ctl, n - pos);
            s.voice.render(buffer, m);
            for (int j = 0; j < m; ++j)
            {
                const float o = buffer[j] * s.outGain * s.chokeGain;
                l[pos + j] += o * s.panL;
                r[pos + j] += o * s.panR;
                s.level = std::max(std::fabs(o), s.level * followMul_);
                if (s.choking) s.chokeGain *= s.chokeMul;
            }
            s.ctl -= m;
            pos += m;
            if (s.voice.finished() || (s.choking && s.chokeGain < 1e-5f)) s.active = false;
        }
    }

    // `n` internal samples of every voice, summed into l and r (zeroed by the caller), with the
    // free-running LFOs a control tick on every 16 samples.
    void mix(float* l, float* r, int n)
    {
        int pos = 0;
        while (pos < n)
        {
            if (freeTick_ <= 0) { turnFreeLfos(); freeTick_ = kControlFrames; }
            const int m = std::min(freeTick_, n - pos);
            for (Slot& s : slots_) if (s.active) renderSlot(s, l + pos, r + pos, m);
            freeTick_ -= m;
            pos += m;
        }
    }

    // Host frames [from, to): one internal sample each, or two decimated into one.
    void render(float* outL, float* outR, int from, int to)
    {
        float l[kChunk], r[kChunk];
        int host = from;
        while (host < to)
        {
            const int frames = std::min(to - host, kChunk / oversampling_);
            const int n = frames * oversampling_;
            std::fill(l, l + n, 0.0f);
            std::fill(r, r + n, 0.0f);
            mix(l, r, n);
            for (int i = 0; i < frames; ++i)
            {
                float yl, yr;
                if (oversampling_ == 2)
                {
                    yl = decimL_.process(bus(l[2 * i]), bus(l[2 * i + 1]));
                    yr = decimR_.process(bus(r[2 * i]), bus(r[2 * i + 1]));
                }
                else
                {
                    yl = bus(l[i]);
                    yr = bus(r[i]);
                }
                outL[host + i] = limited(yl);
                if (outR) outR[host + i] = limited(yr);
            }
            host += frames;
        }
    }

    // --- knob sets and cross-thread state --------------------------------------------------
    std::atomic<float> sets_[{{APP_UPPER}}_NUM_SETS][kNumParams];   // normalised
    std::atomic<int>   program_[{{APP_UPPER}}_NUM_SETS] = {};
    std::atomic<int>   mode_{{{APP_UPPER}}_MODE_KEYBOARD};
    std::atomic<int>   padNote_[{{APP_UPPER}}_NUM_PADS];
    std::atomic<int>   padGroup_[{{APP_UPPER}}_NUM_PADS];
    std::atomic<int>   padHits_[{{APP_UPPER}}_NUM_PADS] = {};     // pad hits since creation; reset leaves them
    std::atomic<int>   lastNote_{-1};
    std::atomic<int>   sounding_{0};
    std::atomic<int>   freshStarts_{0}, continuingStarts_{0}, releases_{0};   // since creation; reset leaves them
    std::atomic<int>   keysUnreleased_{0}, keysSustained_{0}, keysHeld_{0}, monoNote_{-1};
    std::atomic<float> monoGlide_{0.0f};
    std::atomic<int>   latency_{0};
    std::atomic<bool>  resetPending_{false};
    std::atomic<int8_t>   controller_[kNumKnobs];        // the controller each knob listens to, kNoController for none
    std::atomic<int>      learning_{-1};                 // the knob that takes the next controller
    std::atomic<unsigned> changes_{0};

    MidiQueue posted_;
    MidiEvent events_[kMaxEvents];
    int       numEvents_ = 0;

    // --- audio thread ----------------------------------------------------------------------
    double internalRate_ = 88200.0;
    int    oversampling_ = 2;                                 // internal samples per host frame
    float  followMul_ = 1.0f;
    float  keyNorm_[kNumParams] = {};
    float  keyPlain_[kNumParams] = {};
    Lfo    freeLfo_[kNumLfos];
    int    freeTick_ = 0;
    float  bend_ = 0.0f, modWheel_ = 0.0f, pressure_ = 0.0f;   // -1..1, 0..1, 0..1
    int    held_[kMaxHeld] = {};                              // the keys held, newest last
    int    numHeld_ = 0;
    bool   sustain_ = false;                                  // the sustain pedal is down
    Slot   slots_[kNumSlots];
    HalfBand decimL_, decimR_;
};

// ---------------------------------------------------------------------------------------------
// C interface: the tables
// ---------------------------------------------------------------------------------------------
int {{APP_C}}_num_params(void) { return kNumParams; }

void {{APP_C}}_param_info(int index, {{APP}}ParamInfo* out)
{
    if (!out) return;
    *out = {{APP}}ParamInfo{};
    if (!validParam(index)) return;
    const Param& p = param(index);
    out->identifier = p.id; out->name = p.name; out->unit = p.unit; out->kind = p.kind;
    out->minValue = p.min; out->maxValue = p.max; out->defaultValue = p.def;
    out->logarithmic = p.logarithmic ? 1 : 0;
    out->numChoices = p.kind == {{APP_UPPER}}_KIND_CHOICE ? (int)p.max + 1 : 0;
    out->section = sectionOf(index);
}

int {{APP_C}}_param_id(int index) { return validParam(index) ? stableId(index) : -1; }
int {{APP_C}}_param_index(int id) { return paramOfStableId(id); }

const char* {{APP_C}}_param_choice(int index, int choice) { return validParam(index) ? choiceName(index, choice) : ""; }

float {{APP_C}}_param_to_plain(int index, float normalised) { return validParam(index) ? param(index).toPlain(normalised) : 0.0f; }
float {{APP_C}}_param_to_normalised(int index, float plain) { return validParam(index) ? param(index).toNormalised(plain) : 0.0f; }

const char* {{APP_C}}_param_display(int index, float plain, char* buffer, int bufferSize)
{
    if (!buffer || bufferSize <= 0) return "";
    buffer[0] = 0;
    if (!validParam(index)) return buffer;
    const Param& p = param(index);
    if (index == kOctave && plain >= 0.5f) std::snprintf(buffer, (size_t)bufferSize, "+%d", (int)std::lround(plain));
    else if (p.offAtMin && plain <= p.min) std::snprintf(buffer, (size_t)bufferSize, "Off");
    else if (p.kind == {{APP_UPPER}}_KIND_CHOICE) std::snprintf(buffer, (size_t)bufferSize, "%s", choiceName(index, (int)std::lround(plain)));
    else if (p.kind == {{APP_UPPER}}_KIND_INT) std::snprintf(buffer, (size_t)bufferSize, "%d", (int)std::lround(plain));
    else
    {
        // A frequency has two decimals only where it is small: "6.00 Hz", "800 Hz".
        const int decimals = p.decimals >= 0 ? p.decimals : (std::fabs(plain) < 10.0f ? 2 : 0);
        std::snprintf(buffer, (size_t)bufferSize, "%.*f", decimals, (double)plain);
        if (buffer[0] == '-')     // turn "-0.0" into "0.0"
        {
            bool allZero = true;
            for (const char* q = buffer + 1; *q; ++q) if (*q != '0' && *q != '.') { allZero = false; break; }
            if (allZero) std::memmove(buffer, buffer + 1, std::strlen(buffer));
        }
    }
    return buffer;
}

static bool validSection(int s) { return s >= 0 && s < (int)sections().size(); }

int {{APP_C}}_num_sections(void) { return (int)sections().size(); }
const char* {{APP_C}}_section_name(int s) { return validSection(s) ? sections()[(size_t)s].name : ""; }
int {{APP_C}}_section_size(int s) { return validSection(s) ? (int)sections()[(size_t)s].params.size() : 0; }
int {{APP_C}}_section_param(int s, int pos)
{
    return pos >= 0 && pos < {{APP_C}}_section_size(s) ? sections()[(size_t)s].params[(size_t)pos] : -1;
}

int {{APP_C}}_num_lfos(void) { return kNumLfos; }
int {{APP_C}}_lfo_amount(int lfo, int param) { return lfo >= 0 && lfo < kNumLfos && validParam(param) ? amountOf(lfo, param) : -1; }
int {{APP_C}}_vel_amount(int param) { return validParam(param) ? velAmountOf(param) : -1; }

int {{APP_C}}_standard_controller(int param) { return validParam(param) ? standardController(param) : kNoController; }
int {{APP_C}}_controller_reserved(int cc) { return cc < 0 || cc > 127 || controllerReserved(cc) ? 1 : 0; }

double {{APP_C}}_tail_time(void) { return kTailSeconds; }

int {{APP_C}}_num_programs(void) { return (int)programs().size(); }
const char* {{APP_C}}_program_name(int p) { return p >= 0 && p < {{APP_C}}_num_programs() ? programs()[(size_t)p].name : ""; }
int {{APP_C}}_program_sets(int param) { return validParam(param) && programSets(param) ? 1 : 0; }
float {{APP_C}}_program_value(int p, int param)
{
    return p >= 0 && p < {{APP_C}}_num_programs() && validParam(param) ? programs()[(size_t)p].values[param] : 0.0f;
}

int {{APP_C}}_num_platform_defaults(void) { return kNumPlatformDefaults; }
int {{APP_C}}_platform_default_param(int i) { return platformDefault(i).param; }
float {{APP_C}}_platform_default_value(int i) { return platformDefault(i).value; }

// ---------------------------------------------------------------------------------------------
// C interface: the engine. Every call tolerates a null engine and indices out of range.
// ---------------------------------------------------------------------------------------------
{{APP}}Engine* {{APP_C}}_create(void) { return new {{APP}}Engine(); }
void {{APP_C}}_destroy({{APP}}Engine* e) { delete e; }
void {{APP_C}}_prepare({{APP}}Engine* e, double sampleRate) { if (e) e->prepare(sampleRate); }
void {{APP_C}}_reset({{APP}}Engine* e) { if (e) e->reset(); }
void {{APP_C}}_request_reset({{APP}}Engine* e) { if (e) e->requestReset(); }
int  {{APP_C}}_latency(const {{APP}}Engine* e) { return e ? e->latency() : 0; }

float {{APP_C}}_get_plain(const {{APP}}Engine* e, int set, int index)
{
    return e && validSet(set) && validParam(index) ? e->get(set, index) : 0.0f;
}
float {{APP_C}}_get_normalised(const {{APP}}Engine* e, int set, int index)
{
    return e && validSet(set) && validParam(index) ? e->getNormalised(set, index) : 0.0f;
}
void {{APP_C}}_set_plain({{APP}}Engine* e, int set, int index, float plain)
{
    if (e && validSet(set) && validParam(index)) e->set(set, index, plain);
}
void {{APP_C}}_set_normalised({{APP}}Engine* e, int set, int index, float n)
{
    if (e && validSet(set) && validParam(index)) e->setNormalised(set, index, n);
}
void {{APP_C}}_set_program({{APP}}Engine* e, int set, int program) { if (e && validSet(set)) e->setProgram(set, program); }
int  {{APP_C}}_get_program(const {{APP}}Engine* e, int set) { return e && validSet(set) ? e->program(set) : 0; }
void {{APP_C}}_set_program_index({{APP}}Engine* e, int set, int program) { if (e && validSet(set)) e->setProgramIndex(set, program); }
void {{APP_C}}_set_mode({{APP}}Engine* e, int mode) { if (e) e->setMode(mode); }
int  {{APP_C}}_get_mode(const {{APP}}Engine* e) { return e ? e->mode() : {{APP_UPPER}}_MODE_KEYBOARD; }

int  {{APP_C}}_pad_note(const {{APP}}Engine* e, int pad) { return e && validPad(pad) ? e->padNote(pad) : -1; }
void {{APP_C}}_set_pad_note({{APP}}Engine* e, int pad, int note) { if (e && validPad(pad)) e->setPadNote(pad, note); }
int  {{APP_C}}_pad_group(const {{APP}}Engine* e, int pad) { return e && validPad(pad) ? e->padGroup(pad) : 0; }
void {{APP_C}}_set_pad_group({{APP}}Engine* e, int pad, int group) { if (e && validPad(pad)) e->setPadGroup(pad, group); }
int  {{APP_C}}_pad_hits(const {{APP}}Engine* e, int pad) { return e && validPad(pad) ? e->padHits(pad) : 0; }
int  {{APP_C}}_last_note(const {{APP}}Engine* e) { return e ? e->lastNote() : -1; }
void {{APP_C}}_send_to_pad({{APP}}Engine* e, int pad) { if (e && validPad(pad)) e->sendToPad(pad); }
void {{APP_C}}_load_default_kit({{APP}}Engine* e) { if (e) e->loadDefaultKit(); }
int  {{APP_C}}_sounding_voices(const {{APP}}Engine* e) { return e ? e->soundingVoices() : 0; }

void {{APP_C}}_voice_probe(const {{APP}}Engine* e, {{APP}}VoiceProbe* out)
{
    if (!out) return;
    *out = {{APP}}VoiceProbe{};
    out->monoNote = -1;
    if (e) e->probe(*out);
}

static bool validKnob(int param) { return param >= 0 && param < kNumKnobs; }

int  {{APP_C}}_get_controller(const {{APP}}Engine* e, int param) { return e && validKnob(param) ? e->controllerOf(param) : kNoController; }
void {{APP_C}}_set_controller({{APP}}Engine* e, int param, int cc) { if (e && validKnob(param)) e->setController(param, cc); }
void {{APP_C}}_reset_controllers({{APP}}Engine* e) { if (e) e->resetControllers(); }
void {{APP_C}}_learn({{APP}}Engine* e, int param) { if (e) e->learn(validKnob(param) ? param : -1); }
int  {{APP_C}}_learning(const {{APP}}Engine* e) { return e ? e->learning() : -1; }
unsigned {{APP_C}}_changes(const {{APP}}Engine* e) { return e ? e->changes() : 0; }

void {{APP_C}}_post_midi({{APP}}Engine* e, int status, int data1, int data2, int sampleOffset)
{
    if (e) e->postMidi((uint8_t)status, (uint8_t)(data1 & 0x7F), (uint8_t)(data2 & 0x7F), sampleOffset);
}

void {{APP_C}}_midi({{APP}}Engine* e, int status, int data1, int data2, int sampleOffset)
{
    if (e) e->midi((uint8_t)status, (uint8_t)(data1 & 0x7F), (uint8_t)(data2 & 0x7F), sampleOffset);
}

void {{APP_C}}_process({{APP}}Engine* e, float* left, float* right, int frames)
{
    if (!left || frames <= 0) return;
    if (e) { e->process(left, right, frames); return; }
    std::memset(left, 0, sizeof(float) * (size_t)frames);
    if (right) std::memset(right, 0, sizeof(float) * (size_t)frames);
}
