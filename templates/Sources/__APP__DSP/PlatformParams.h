// PlatformParams.h - the platform's part of the parameter table: what every knob is, the knobs
// every instrument has (the platform block), and the shapes of the instrument's tables (Params.h).
//
// The table is, in this order, for every instrument and for good:
//   1. the platform block below, IDs 0 ... kNumPlatformKnobs - 1;
//   2. the instrument's knobs (Params.h, kInstrumentKnobs);
//   3. the LFO amounts: LFO 1 on each of kLfoTargets, then LFO 2 on each;
//   4. the VEL amounts: one on each of kVelTargets.
// The identifiers and the order are permanent from a first release on: only ever append.

#pragma once

#include "{{APP}}DSP.h"

#include <algorithm>
#include <cmath>

namespace {{APP_LOWER}} {

// One parameter of the table: a knob, a switch (a choice) or an amount.
struct Param
{
    const char* id;
    const char* name;
    const char* unit;
    int   kind;                 // {{APP_UPPER}}_KIND_*
    float min, max, def;
    bool  logarithmic;
    int   decimals;             // for the text of a float; -1 = by size, as a frequency is written
    bool  offAtMin = false;     // the bottom of the travel is Off (a level that is not there)
    int   controller = -1;      // the MIDI controller the knob comes with; -1 for an amount
    const char* const* choices = nullptr;   // the names of a choice's steps

    // A logarithmic knob whose bottom is 0 (a time that can be none) travels as log(1 + x / knee):
    // logarithmic over most of its travel, and 0 at its bottom.
    float knee() const { return max / 1000.0f; }

    float toPlain(float norm) const
    {
        norm = std::clamp(norm, 0.0f, 1.0f);
        if (kind == {{APP_UPPER}}_KIND_CHOICE)
        {
            const int n = (int)max + 1;
            return n < 2 ? 0.0f : (float)std::clamp((int)std::lround(norm * (float)(n - 1)), 0, n - 1);
        }
        if (kind == {{APP_UPPER}}_KIND_INT) return std::round(min + norm * (max - min));
        if (logarithmic && min > 0.0f && max > 0.0f) return min * std::pow(max / min, norm);
        if (logarithmic && min == 0.0f && max > 0.0f) return knee() * (std::pow(1.0f + max / knee(), norm) - 1.0f);
        return min + (max - min) * norm;
    }

    float toNormalised(float plain) const
    {
        if (kind == {{APP_UPPER}}_KIND_CHOICE)
        {
            const int n = (int)max + 1;
            return n < 2 ? 0.0f : std::clamp(plain / (float)(n - 1), 0.0f, 1.0f);
        }
        if (max == min) return 0.0f;
        plain = std::clamp(plain, std::fmin(min, max), std::fmax(min, max));
        if (kind == {{APP_UPPER}}_KIND_FLOAT && logarithmic && min > 0.0f && max > 0.0f)
            return std::clamp(std::log(plain / min) / std::log(max / min), 0.0f, 1.0f);
        if (kind == {{APP_UPPER}}_KIND_FLOAT && logarithmic && min == 0.0f && max > 0.0f)
            return std::clamp(std::log(1.0f + plain / knee()) / std::log(1.0f + max / knee()), 0.0f, 1.0f);
        return std::clamp((plain - min) / (max - min), 0.0f, 1.0f);
    }
};

// ----- the kinds of knob, as the tables write them -------------------------------------------
// `cc` is the MIDI controller the knob comes with: the one General MIDI names for the thing where
// there is one (73 Attack Time, 72 Release Time, 75 Decay Time, 74 Brightness, 71 Timbre, 2
// Breath, ...), else one MIDI leaves undefined (14-31, 85-90, 113-119 are the instrument's; the
// platform block takes 5, 7, 10 and 102-112). Every knob has one, no two share one, and none is
// reserved (controllerReserved).
constexpr Param floatKnob(const char* id, const char* name, float min, float max, float def, const char* unit,
                          int decimals, int cc)
{
    return Param{ id, name, unit, {{APP_UPPER}}_KIND_FLOAT, min, max, def, false, decimals, false, cc };
}
// A knob that travels logarithmically (times, frequencies): min above 0, or 0 for a time that
// can be none (see Param::knee).
constexpr Param logKnob(const char* id, const char* name, float min, float max, float def, const char* unit,
                        int decimals, int cc)
{
    return Param{ id, name, unit, {{APP_UPPER}}_KIND_FLOAT, min, max, def, true, decimals, false, cc };
}
// A level in dB whose bottom is Off.
constexpr Param levelKnob(const char* id, const char* name, float min, float max, float def, int cc)
{
    return Param{ id, name, "dB", {{APP_UPPER}}_KIND_FLOAT, min, max, def, false, 1, true, cc };
}
constexpr Param intKnob(const char* id, const char* name, int min, int max, int def, const char* unit, int cc)
{
    return Param{ id, name, unit, {{APP_UPPER}}_KIND_INT, (float)min, (float)max, (float)def, false, 0, false, cc };
}
// A switch: one of `numChoices` named steps.
constexpr Param choiceKnob(const char* id, const char* name, const char* const* names, int numChoices, int def, int cc)
{
    return Param{ id, name, "", {{APP_UPPER}}_KIND_CHOICE, 0.0f, (float)(numChoices - 1), (float)def, false, 0, false, cc,
                  names };
}

// ----- MIDI controllers --------------------------------------------------------------------
constexpr int kNoController = -1;

// Controllers no knob can have: those MIDI gives a meaning of its own (bank select, data entry,
// the sustain pedal, parameter numbers, channel mode: 120 All Sound Off, 121 Reset All
// Controllers, 123 All Notes Off) and the mod wheel, which the instrument maps (kModWheelTargets).
constexpr bool controllerReserved(int cc)
{
    return cc <= 1 || cc == 6 || cc == 32 || cc == 38 || cc == 64 || (cc >= 96 && cc <= 101) || cc >= 120;
}

// ----- the platform block ------------------------------------------------------------------
enum PlatformKnob
{
    kVolume,        // dB
    kPan,           // %
    kTune,          // ct    fine tuning
    kOctave,        // -     the octave of the keyboard
    kBendUp,        // st    how far the pitch bend bends up
    kBendDown,      // st    how far the pitch bend bends down
    kVoiceMode,     // -     Poly, Mono or Legato
    kGlide,         // ms    how long the pitch takes to glide to a new note
    kLfoStart,      // -     whether an LFO restarts with every note or runs free
    kLfo1Rate,      // Hz
    kLfo1Shape,     // -
    kLfo2Rate,      // Hz
    kLfo2Shape,     // -
    kVelSens,       // %     how much the velocity changes the loudness
    kNumPlatformKnobs
};

constexpr int kNumLfos = 2;

// The shapes of an LFO's cycle. Steps takes a new random level each cycle and holds it; Wander
// takes one and moves there smoothly.
enum LfoShape { kLfoSine, kLfoTriangle, kLfoRampUp, kLfoRampDown, kLfoSquare, kLfoSteps, kLfoWander, kNumLfoShapes };
enum LfoStart { kLfoStartHit, kLfoStartFree, kNumLfoStarts };
enum VoiceMode { kVoicePoly, kVoiceMono, kVoiceLegato, kNumVoiceModes };

constexpr const char* kLfoShapeNames[kNumLfoShapes] = { "Sine", "Triangle", "Ramp Up", "Ramp Down", "Square", "Steps", "Wander" };
constexpr const char* kLfoStartNames[kNumLfoStarts] = { "Hit", "Free" };
constexpr const char* kVoiceModeNames[kNumVoiceModes] = { "Poly", "Mono", "Legato" };

constexpr Param kPlatformKnobs[kNumPlatformKnobs] = {
    floatKnob ("volume",    "Volume",      -40.0f, 6.0f, 0.0f, "dB", 1, 7),
    floatKnob ("pan",       "Pan",         -100.0f, 100.0f, 0.0f, "%", 0, 10),
    floatKnob ("tune",      "Tune",        -100.0f, 100.0f, 0.0f, "ct", 0, 102),
    intKnob   ("octave",    "Octave",      -2, 2, 0, "", 103),
    intKnob   ("bendup",    "Bend Up",     0, 24, 2, "st", 104),
    intKnob   ("benddown",  "Bend Down",   0, 24, 2, "st", 105),
    choiceKnob("voicemode", "Voice Mode",  kVoiceModeNames, kNumVoiceModes, kVoicePoly, 106),
    logKnob   ("glide",     "Glide",       0.0f, 2000.0f, 0.0f, "ms", 0, 5),         // 5: Portamento Time
    choiceKnob("lfostart",  "LFO Start",   kLfoStartNames, kNumLfoStarts, kLfoStartHit, 107),
    logKnob   ("lfo1rate",  "LFO 1 Rate",  0.02f, 20.0f, 6.0f, "Hz", -1, 108),
    choiceKnob("lfo1shape", "LFO 1 Shape", kLfoShapeNames, kNumLfoShapes, kLfoSine, 109),
    logKnob   ("lfo2rate",  "LFO 2 Rate",  0.02f, 20.0f, 2.0f, "Hz", -1, 110),
    choiceKnob("lfo2shape", "LFO 2 Shape", kLfoShapeNames, kNumLfoShapes, kLfoSine, 111),
    floatKnob ("velsens",   "Vel Sens",    0.0f, 100.0f, 70.0f, "%", 0, 112),
};

static_assert(kLfo2Rate == kLfo1Rate + 2 && kLfo2Shape == kLfo1Shape + 2, "an LFO's knobs are two apart");

// ----- the shapes of the instrument's tables (Params.h) -------------------------------------
// A wheel's target: the knob it moves, and how far at the top, as a part of the knob's travel.
// A table that would be empty holds { kNoTarget, 0 }.
constexpr int kNoTarget = -1;
struct Target { int param; float depth; };

// One knob set to a plain value; param -1 is no override. A program's and a kit pad's overrides,
// and the entries of the instrument's test sound (kTestSound).
struct Override { int param = -1; float value = 0.0f; };

// The instrument's own default for a knob of the platform block (its playing style: Voice Mode,
// Glide, the bend range, ...), a plain value. A table that would be empty holds { kNoTarget, 0 }.
struct PlatformDefault { int param; float value; };

// A built-in program: the defaults with a few values overridden.
constexpr int kMaxProgramOverrides = 16;
struct ProgramDef { const char* name; Override overrides[kMaxProgramOverrides]; };

// What a pad holds when the engine is created or the default kit is loaded: a program with a few
// overrides and Octave at its default, at a note, in a group (0 = Off).
constexpr int kMaxKitOverrides = 4;
struct KitPad { int program; int note; int group; Override overrides[kMaxKitOverrides]; };

// A section of the panel (and an Audio Unit parameter group): its name and its knobs, in the
// order they are shown. The list ends at the first slot that holds no instrument knob: the slots
// left out are 0, a platform knob.
constexpr int kMaxSectionKnobs = 16;
struct SectionDef { const char* name; int knobs[kMaxSectionKnobs]; };

} // namespace {{APP_LOWER}}
