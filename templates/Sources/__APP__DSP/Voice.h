// Voice.h - one voice of the instrument: the placeholder "Tone", a sine and its second harmonic
// (Brightness) under an envelope of Attack, Decay and Release.
//
// The seam: the engine ({{APP}}Engine.cpp) owns the voice pool, the knob sets, the LFOs, the
// velocity's and the wheels' modulation, Volume, Pan, Vel Sens, the fade of a stolen voice, the
// 2x stage and the limiter. It calls nothing of a voice but these four:
//   * start(knobs, note, velocity, continuing): a note-on. `knobs` stays valid while the voice
//     sounds and is updated before every render() (ParamTable.h, Knobs). `note` is the MIDI
//     note, before Octave, Tune and the bend (Knobs::hz adds them); `velocity` 0...1 (the engine
//     applies Vel Sens to the level; the voice may use it for more). `continuing` is true when
//     the note-on takes over this voice while it sounds (kRehitContinues; in Legato a note
//     played while another key is held; in Mono and Legato the return to a key still held):
//     go on from where it is, at the new note, with no new attack. A fresh voice
//     (default-constructed) gets false. While the pitch glides, Knobs::glide holds how far it
//     still is from the note; Knobs::hz adds it.
//   * release(): the note-off of its key (or pad).
//   * render(out, frames): writes the next `frames` mono samples (1 ... 16) at Knobs::rate.
//   * finished(): true once the voice is silent for good; the engine then frees it.
// No allocation, no lock, no I/O in any of them: they run on the audio thread.
//
// Random numbers (Tone draws none): a voice that needs them owns its generator, a std::mt19937
// member, seeds it with kVoiceSeed in every fresh start (`continuing` false) and draws through
// uniform() and white() (VoiceRandom.h). A continuing start goes on in the same stream. Nothing
// else is random: the engine gives a fresh voice no seed, and two equal notes must render equal
// samples (ModulationTests.lfoHitRepeats). The listening prototype's harness seeds its voices
// the same way with the same constant, so a prototype's voice is ported draw for draw.
//
// 2 to a power is std::exp2, not std::pow(2.0, x): an optimised build turns the one into the
// other, and the two differ in a last bit now and then, so a debug build would render other
// samples than a release build.

#pragma once

#include "ParamTable.h"

#include <cmath>

namespace {{APP_LOWER}} {

struct Voice
{
    void start(const Knobs& k, int n, float velocity, bool continuing)
    {
        knobs = &k;
        note = n;
        (void)velocity;                         // Tone's timbre does not follow the velocity
        if (!continuing)
        {
            phase = 0.0;
            env = 0.0;
            stage = kRising;
        }
        else if (stage != kRising) stage = kHeld;
    }

    void release()
    {
        if (stage != kDone) stage = kReleased;
    }

    void render(float* out, int frames)
    {
        const Knobs& k = *knobs;
        const double dt = 1.0 / k.rate;
        const double increment = k.hz((double)note) * dt;
        const double rise = dt / ((double)k[kAttack] / 1000.0);
        const double decay = std::exp(-6.907755278982137 * dt / (double)k[kDecay]);       // 60 dB in Decay
        const double fall = std::exp(-6.907755278982137 * dt / (double)k[kRelease]);      // 60 dB in Release
        const double harmonic = (double)k[kBrightness] / 100.0;
        for (int i = 0; i < frames; ++i)
        {
            switch (stage)
            {
                case kRising:   env += rise; if (env >= 1.0) { env = 1.0; stage = kHeld; } break;
                case kHeld:     env *= decay; break;
                case kReleased: env *= fall; break;
                case kDone:     env = 0.0; break;
            }
            if (stage != kRising && env < kSilent) { env = 0.0; stage = kDone; }
            const double x = 2.0 * kPi * phase;
            out[i] = (float)(env * (std::sin(x) + harmonic * std::sin(2.0 * x)));
            phase += increment;
            if (phase >= 1.0) phase -= std::floor(phase);
        }
    }

    bool finished() const { return stage == kDone; }

private:
    static constexpr double kPi = 3.14159265358979323846;
    static constexpr double kSilent = 1e-5;     // -100 dB: where the tone is over

    enum Stage { kRising, kHeld, kReleased, kDone };

    const Knobs* knobs = nullptr;
    int note = 60;
    double phase = 0.0, env = 0.0;
    Stage stage = kRising;
};

} // namespace {{APP_LOWER}}
