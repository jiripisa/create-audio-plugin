// ParamTable.h - the whole parameter table, put together from the platform block
// (PlatformParams.h) and the instrument's tables (Params.h): the knobs, the amounts, the
// sections and the programs, and what the instrument's voice reads (Knobs).
//
// The seam: the platform (this file, PlatformParams.h, {{APP}}Engine.cpp) knows no knob of the
// instrument by name. The instrument is Params.h (its knobs and tables) and Voice.h (its voice);
// the static_asserts below hold it to what the platform relies on:
//   * its knobs follow the platform block, each with a lowercase ASCII identifier and a MIDI
//     controller of its own that MIDI does not reserve;
//   * the LFOs move Volume, Pan and Tune and the velocity Volume, Pan, Tune and both LFO rates,
//     among the continuous knobs the instrument adds; Vel Sens moves no further;
//   * each wheel target is a continuous knob with a depth in (0, 1];
//   * each instrument knob is in exactly one section;
//   * the programs and the default kit name valid programs, notes, groups and parameters.

#pragma once

#include "Params.h"

#include <cmath>
#include <vector>

namespace {{APP_LOWER}} {

constexpr int kNumLfoTargets = (int)(sizeof(kLfoTargets) / sizeof(kLfoTargets[0]));
constexpr int kNumVelTargets = (int)(sizeof(kVelTargets) / sizeof(kVelTargets[0]));
constexpr int kNumLfoAmounts = kNumLfos * kNumLfoTargets;
constexpr int kNumVelAmounts = kNumVelTargets;
constexpr int kNumParams = kNumKnobs + kNumLfoAmounts + kNumVelAmounts;
constexpr int kNumModWheelTargets = (int)(sizeof(kModWheelTargets) / sizeof(kModWheelTargets[0]));
constexpr int kNumAftertouchTargets = (int)(sizeof(kAftertouchTargets) / sizeof(kAftertouchTargets[0]));
constexpr int kNumSections = (int)(sizeof(kSections) / sizeof(kSections[0]));

// A knob of the table: the platform block's or the instrument's.
constexpr const Param& knob(int i) { return i < kNumPlatformKnobs ? kPlatformKnobs[i] : kInstrumentKnobs[i - kNumPlatformKnobs]; }
constexpr bool isKnob(int i) { return i >= 0 && i < kNumKnobs; }

// The parameter that says how far LFO `lfo` moves `param`; -1 when it cannot move it.
constexpr int amountOf(int lfo, int param)
{
    for (int t = 0; t < kNumLfoTargets; ++t) if (kLfoTargets[t] == param) return kNumKnobs + lfo * kNumLfoTargets + t;
    return -1;
}

// The parameter that says how far the velocity moves `param`; -1 when it cannot move it.
constexpr int velAmountOf(int param)
{
    for (int t = 0; t < kNumVelTargets; ++t) if (kVelTargets[t] == param) return kNumKnobs + kNumLfoAmounts + t;
    return -1;
}

constexpr int standardController(int param) { return isKnob(param) ? knob(param).controller : kNoController; }

// ----- stable parameter IDs ------------------------------------------------------------------
// The Audio Unit's parameter IDs, which hosts save automation and projects by. A parameter's
// place in the table moves when a later version appends an instrument knob (the amounts after
// it move on) or gives an LFO or the velocity another target; its ID does not, since it names
// the knob and the source, not the place:
//   knob k (its place in the knobs, which only ever grow at their end)   -> k
//   LFO l's amount on knob k                                              -> 1000 * (l + 1) + k
//   the velocity's amount on knob k                                       -> 3000 + k
constexpr int kLfoIdBase = 1000, kVelIdBase = 3000;
static_assert(kNumKnobs < 1000 && kNumLfos <= 2, "the stable IDs leave room for 999 knobs and two LFOs");

constexpr int stableId(int param)
{
    if (isKnob(param)) return param;
    const int amount = param - kNumKnobs;
    if (amount >= 0 && amount < kNumLfoAmounts)
        return kLfoIdBase * (amount / kNumLfoTargets + 1) + kLfoTargets[amount % kNumLfoTargets];
    const int vel = amount - kNumLfoAmounts;
    if (vel >= 0 && vel < kNumVelAmounts) return kVelIdBase + kVelTargets[vel];
    return -1;
}

// The parameter a stable ID names; -1 for an ID no parameter of this table has.
constexpr int paramOfStableId(int id)
{
    if (id >= 0 && id < kNumKnobs) return id;
    if (id >= kVelIdBase && id < kVelIdBase + 1000) return velAmountOf(id - kVelIdBase);
    for (int lfo = 0; lfo < kNumLfos; ++lfo)
        if (id >= kLfoIdBase * (lfo + 1) && id < kLfoIdBase * (lfo + 2)) return amountOf(lfo, id - kLfoIdBase * (lfo + 1));
    return -1;
}

namespace check {
constexpr bool stableIdsRoundTrip()
{
    for (int i = 0; i < kNumKnobs + kNumLfoAmounts + kNumVelAmounts; ++i)
        if (paramOfStableId(stableId(i)) != i) return false;
    return true;
}
} // namespace check
static_assert(check::stableIdsRoundTrip(), "a stable ID names another parameter");

// ----- the contract ------------------------------------------------------------------------
namespace check {

constexpr bool listed(const int* list, int n, int param)
{
    for (int i = 0; i < n; ++i) if (list[i] == param) return true;
    return false;
}

// Each entry a knob, a continuous one (a switch has no travel to move along), and none twice.
constexpr bool continuousKnobsOnce(const int* list, int n)
{
    for (int i = 0; i < n; ++i)
    {
        if (!isKnob(list[i]) || knob(list[i]).kind == {{APP_UPPER}}_KIND_CHOICE) return false;
        for (int j = 0; j < i; ++j) if (list[j] == list[i]) return false;
    }
    return true;
}

constexpr bool wheelTargets(const Target* targets, int n)
{
    for (int i = 0; i < n; ++i)
    {
        if (targets[i].param == kNoTarget) continue;
        if (!isKnob(targets[i].param) || knob(targets[i].param).kind == {{APP_UPPER}}_KIND_CHOICE) return false;
        if (!(targets[i].depth > 0.0f && targets[i].depth <= 1.0f)) return false;
    }
    return true;
}

constexpr bool controllersAreSound()
{
    for (int i = 0; i < kNumKnobs; ++i)
    {
        const int cc = knob(i).controller;
        if (cc < 0 || cc > 127 || controllerReserved(cc)) return false;
        for (int j = 0; j < i; ++j) if (knob(j).controller == cc) return false;
    }
    return true;
}

constexpr bool identifiersAreSound()
{
    for (int i = 0; i < kNumKnobs; ++i)
    {
        const char* id = knob(i).id;
        if (!id || !*id) return false;
        for (const char* c = id; *c; ++c) if (!((*c >= 'a' && *c <= 'z') || (*c >= '0' && *c <= '9'))) return false;
    }
    return true;
}

// Every instrument knob in exactly one section, and nothing else in any.
constexpr bool sectionsAreSound()
{
    for (int k = kNumPlatformKnobs; k < kNumKnobs; ++k)
    {
        int seen = 0;
        for (int s = 0; s < kNumSections; ++s)
            for (int p : kSections[s].knobs)
            {
                if (p < kNumPlatformKnobs) break;
                if (p == k) ++seen;
            }
        if (seen != 1) return false;
    }
    for (int s = 0; s < kNumSections; ++s)
        for (int p : kSections[s].knobs)
        {
            if (p < kNumPlatformKnobs) break;
            if (p >= kNumKnobs) return false;
        }
    return true;
}

constexpr bool overridesAreSound(const Override* overrides, int n)
{
    for (int i = 0; i < n; ++i) if (overrides[i].param < -1 || overrides[i].param >= kNumKnobs + kNumLfoAmounts + kNumVelAmounts) return false;
    return true;
}

constexpr bool programsAndKitAreSound()
{
    for (const ProgramDef& p : kPrograms) if (!p.name || !overridesAreSound(p.overrides, kMaxProgramOverrides)) return false;
    for (const KitPad& pad : kDefaultKit)
    {
        if (pad.program < 0 || pad.program >= kNumPrograms) return false;
        if (pad.note < 0 || pad.note > 127 || pad.group < 0 || pad.group > {{APP_UPPER}}_NUM_GROUPS) return false;
        if (!overridesAreSound(pad.overrides, kMaxKitOverrides)) return false;
    }
    return true;
}

} // namespace check

static_assert(sizeof(kInstrumentKnobs) / sizeof(kInstrumentKnobs[0]) == (size_t)kNumInstrumentKnobs,
              "kInstrumentKnobs holds every instrument knob of the enum");
static_assert(check::identifiersAreSound(), "a knob's identifier is empty or not lowercase ASCII letters and digits");
static_assert(check::continuousKnobsOnce(kLfoTargets, kNumLfoTargets), "an LFO target is no continuous knob, or twice");
static_assert(check::continuousKnobsOnce(kVelTargets, kNumVelTargets), "a VEL target is no continuous knob, or twice");
static_assert(check::listed(kLfoTargets, kNumLfoTargets, kVolume) && check::listed(kLfoTargets, kNumLfoTargets, kPan)
              && check::listed(kLfoTargets, kNumLfoTargets, kTune), "the LFOs move Volume, Pan and Tune");
static_assert(check::listed(kVelTargets, kNumVelTargets, kVolume) && check::listed(kVelTargets, kNumVelTargets, kPan)
              && check::listed(kVelTargets, kNumVelTargets, kTune) && check::listed(kVelTargets, kNumVelTargets, kLfo1Rate)
              && check::listed(kVelTargets, kNumVelTargets, kLfo2Rate), "the velocity moves Volume, Pan, Tune and the LFOs' rates");
static_assert(!check::listed(kVelTargets, kNumVelTargets, kVelSens), "Vel Sens is the velocity's own: it moves no further");
static_assert(check::wheelTargets(kModWheelTargets, kNumModWheelTargets), "a mod wheel target is no continuous knob, or its depth is not in (0, 1]");
static_assert(check::wheelTargets(kAftertouchTargets, kNumAftertouchTargets), "an aftertouch target is no continuous knob, or its depth is not in (0, 1]");
static_assert(check::controllersAreSound(), "a knob's standard controller is missing, reserved or shared");
static_assert(check::sectionsAreSound(), "an instrument knob is in no section or in two, or a section holds no knob");
static_assert(kNumPrograms >= 1 && check::programsAndKitAreSound(), "a program or a pad of the default kit is out of range");

// ----- the table -----------------------------------------------------------------------------
// The whole table: the knobs, the LFO amounts ("lfo1tune", "LFO 1>Tune"), then the velocity
// amounts ("velattack", "VEL>Attack"). Every amount is -100 ... 100 %, 0 at rest.
const Param& param(int index);
inline bool validParam(int i) { return i >= 0 && i < kNumParams; }

const char* choiceName(int index, int choice);

struct Section { const char* name; std::vector<int> params; };
// The instrument's sections, then "Master": the platform block, in table order.
const std::vector<Section>& sections();
int sectionOf(int param);

// Built-in programs: the defaults with the program's values over them.
struct Program { const char* name; float values[kNumParams]; };
const std::vector<Program>& programs();
bool programSets(int param);     // false for Octave, which belongs to the player's hands

// ----- what a voice reads --------------------------------------------------------------------
// The engine hands a voice its Knobs at the start (Voice::start). The reference stays valid for
// as long as the voice sounds, and the engine updates it before each Voice::render call: the
// knob set (the keyboard's as it is now, or a pad's as it was at the hit), moved by the voice's
// LFOs, the hit's velocity and, on a keyboard voice, the wheels.
struct Knobs
{
    float v[kNumParams] = {};       // plain values, in table order
    float bend = 0.0f;              // the pitch bend, in semitones
    double rate = 48000.0;          // the voice's sample rate: the host's, or twice it below 88.2 kHz

    float operator[](int i) const { return v[i]; }

    // A note's frequency with the set's Octave and Tune and the bend. Fractional notes are fine.
    double hz(double note) const
    {
        return 440.0 * std::exp2((note + 12.0 * (double)v[kOctave] + (double)v[kTune] / 100.0 + (double)bend - 69.0) / 12.0);
    }
};

} // namespace {{APP_LOWER}}
