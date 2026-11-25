// Params.h - the instrument's part of the parameter table: its knobs, what the LFOs, the velocity
// and the wheels may move, its sections, its programs, its default kit and its test sound (the
// shapes are in PlatformParams.h, the whole table is put together in ParamTable.h).
//
// The placeholder instrument "Tone": a sine with one harmonic (its second), an envelope of
// Attack, Decay (while the key is held) and Release, and Brightness, the harmonic's level.
//
// The identifiers and the order are permanent from a first release on: only ever append.

#pragma once

#include "PlatformParams.h"

namespace {{APP_LOWER}} {

// ---------------------------------------------------------------------------------------------
// The knobs, after the platform block.
// ---------------------------------------------------------------------------------------------
enum InstrumentKnob
{
    kAttack = kNumPlatformKnobs,    // ms    how long the tone takes to rise
    kDecay,                         // s     how long it takes to die away while the key is held (T60)
    kRelease,                       // s     how long it takes to die away once the key is let go (T60)
    kBrightness,                    // %     the level of the second harmonic
    kNumKnobs
};

constexpr int kNumInstrumentKnobs = kNumKnobs - kNumPlatformKnobs;

constexpr Param kInstrumentKnobs[kNumInstrumentKnobs] = {
    logKnob  ("attack",     "Attack",     1.0f, 2000.0f, 5.0f, "ms", 0, 73),     // 73: Attack Time
    logKnob  ("decay",      "Decay",      0.05f, 20.0f, 2.0f, "s", 2, 75),      // 75: Decay Time
    logKnob  ("release",    "Release",    0.01f, 5.0f, 0.30f, "s", 2, 72),      // 72: Release Time
    floatKnob("brightness", "Brightness", 0.0f, 100.0f, 30.0f, "%", 0, 74),     // 74: Brightness
};

// The knobs an LFO can move (Volume, Pan and Tune always among them).
constexpr int kLfoTargets[] = { kVolume, kPan, kTune, kBrightness };

// The knobs the velocity can move: every continuous knob of the sound, Volume, Pan, Tune and the
// LFOs' rates.
constexpr int kVelTargets[] = { kAttack, kDecay, kRelease, kBrightness, kVolume, kPan, kTune, kLfo1Rate, kLfo2Rate };

// What the mod wheel (CC 1) and the aftertouch move on a keyboard voice, and how far at the top.
constexpr Target kModWheelTargets[] = { { kBrightness, 0.5f } };
constexpr Target kAftertouchTargets[] = { { kBrightness, 0.25f } };

// The platform knobs whose default the instrument changes, as plain values: its playing style
// (a flute: { { kVoiceMode, kVoiceLegato }, { kGlide, 60.0f } }; a guitar keeps Poly and Bend 2).
// The only way an instrument changes a platform default: the table, a fresh engine, the Audio
// Unit, the programs and the panel all take these. Tone plays as the platform does.
constexpr PlatformDefault kPlatformDefaults[] = { { kNoTarget, 0.0f } };

// The sections the instrument's knobs are shown in, in order; the platform's Master comes last.
constexpr SectionDef kSections[] = {
    { "Tone", { kAttack, kDecay, kRelease, kBrightness } },
};

// ---------------------------------------------------------------------------------------------
// Programs and the default kit.
// ---------------------------------------------------------------------------------------------
enum ProgramIndex { kProgramTone, kProgramSoftTone, kNumPrograms };

constexpr ProgramDef kPrograms[kNumPrograms] = {
    { "Tone", {} },
    { "Soft Tone", { { kAttack, 40.0f }, { kDecay, 4.0f }, { kRelease, 0.8f }, { kBrightness, 5.0f } } },
};

// Every pad plays Tone, at notes 36 ... 51, on its own (Group Off).
constexpr KitPad kDefaultKit[{{APP_UPPER}}_NUM_PADS] = {
    { kProgramTone, 36, 0, {} }, { kProgramTone, 37, 0, {} }, { kProgramTone, 38, 0, {} }, { kProgramTone, 39, 0, {} },
    { kProgramTone, 40, 0, {} }, { kProgramTone, 41, 0, {} }, { kProgramTone, 42, 0, {} }, { kProgramTone, 43, 0, {} },
    { kProgramTone, 44, 0, {} }, { kProgramTone, 45, 0, {} }, { kProgramTone, 46, 0, {} }, { kProgramTone, 47, 0, {} },
    { kProgramTone, 48, 0, {} }, { kProgramTone, 49, 0, {} }, { kProgramTone, 50, 0, {} }, { kProgramTone, 51, 0, {} },
};

// ---------------------------------------------------------------------------------------------
// The test sound.
// ---------------------------------------------------------------------------------------------
// The instrument's own knobs as the platform's tests play it: plain values over the defaults,
// { knob, value }. Those tests (EngineTests, VoiceModeTests, ModulationTests, PadTests, ...) know
// no knob of the instrument: they measure pitches, compare renders and wait for silence. With
// these values in a set the voice must
//   * sound at Knobs::hz(note), steadily: no vibrato, pitch envelope, drift or detune. Whatever
//     moves the pitch by itself has a knob, and that knob is turned to nothing here;
//   * sound for at least half a second while its key is held;
//   * be over (finished()) within 1.5 s of its note-off: a longer release is turned down here.
// Only the instrument's own knobs (the platform's go back to the platform's own in the tests),
// each once, in its range. { kNoTarget, 0 } when the default sound is like that already, as
// Tone's is. ParameterTableTests.testSound checks the table; nothing but tests reads it.
constexpr Override kTestSound[] = { { kNoTarget, 0.0f } };

// ---------------------------------------------------------------------------------------------
// How the instrument plays.
// ---------------------------------------------------------------------------------------------
// A note-on on a voice that sounds (the same key, or a pad of the same group): true continues it
// (Voice::start with continuing = true), false fades it out in 3 ms and starts a fresh voice.
constexpr bool kRehitContinues = false;

// The output scale: the voice's units to the engine's, set so that the fullest gesture of the
// playing style at full velocity and Volume 0 dB peaks under the knee of the output stage (0.6:
// the limiter bends what is above). Tone is played in chords: four notes at once (each
// sin + 0.3 sin 2x, peaking at 1.14) stay under 4 x 1.14 x 0.125 = 0.57; one note peaks at 0.14,
// -17 dBFS. InstrumentTableTests.fullestGesture measures it.
constexpr float kOutputLevel = 0.125f;

// The longest a voice can sound once its key is let go, in seconds: the top of Release (a T60)
// takes the tone the 100 dB down where Voice::finished says it is over in 100/60 of it. The Audio
// Unit's tail.
constexpr double kTailSeconds = (double)kInstrumentKnobs[kRelease - kNumPlatformKnobs].max * 100.0 / 60.0;

} // namespace {{APP_LOWER}}
