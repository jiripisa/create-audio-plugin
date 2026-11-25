// {{APP}}Reference.cpp - the listening prototype as the reference the engine is tested against:
// the prototype's voice (from .planning/research/spike/), played by the prototype's own harness
// (spike_harness.h beside this file, the copy the approved renders were made with: its play is
// what the user heard). Throwaway code: do not "fix" or tidy it.
//
// Amended where the engine must differ, each marked "amended":
//   * the parameters arrive with the render (a set per voice prototype), so that a test can turn
//     the knobs and the pads can each have their own;
//   * the events are placed on whole frames of the host's rate, as MIDI is in the engine;
//   * the voices can run at twice the host's rate, their sum going through the engine's
//     half-band decimator (HalfBand.h), as the engine's does below 88.2 kHz.
//
// No fused multiply-add: the rendering must be the same in debug and release builds.
#pragma clang fp contract(off)

#include <algorithm>
#include <cmath>
#include <vector>

#include "../../Sources/{{APP}}DSP/HalfBand.h"
#include "{{APP}}Reference.h"
#include "spike_harness.h"

namespace {

constexpr double kPi = 3.14159265358979323846;

// The prototype's voice, as the harness plays it and as the engine will: start, release, render,
// finished, the pitch from Knobs::hz. Its level is free of the velocity (Vel Sens is the pool's).
struct Voice
{
    const {{APP}}RefParams* p = nullptr;    // amended: the parameters of this render
    const spike::Knobs* knobs = nullptr;
    int note = 60;
    double phase = 0.0, env = 0.0;
    int stage = 3;                  // 0 rising, 1 held, 2 released, 3 done

    explicit Voice(const {{APP}}RefParams& params) : p(&params) {}

    void start(const spike::Knobs& k, int n, float, bool continuing)
    {
        knobs = &k;
        note = n;
        if (!continuing) { phase = 0.0; env = 0.0; stage = 0; }
        else if (stage != 0) stage = 1;
    }

    void release() { if (stage != 3) stage = 2; }

    void render(float* out, int frames)
    {
        const double dt = 1.0 / knobs->rate;
        const double hz = knobs->hz(note);
        for (int i = 0; i < frames; ++i)
        {
            switch (stage)
            {
                case 0: env += dt / (p->attack / 1000.0); if (env >= 1.0) { env = 1.0; stage = 1; } break;
                case 1: env *= std::exp(-6.907755278982137 * dt / p->decay); break;
                case 2: env *= std::exp(-6.907755278982137 * dt / p->release); break;
                default: env = 0.0; break;
            }
            if (stage != 0 && env < 1e-5) { env = 0.0; stage = 3; }
            const double x = 2.0 * kPi * phase;
            out[i] = (float)(env * (std::sin(x) + p->brightness * std::sin(2.0 * x)));
            phase += hz * dt;
            if (phase >= 1.0) phase -= std::floor(phase);
        }
    }

    bool finished() const { return stage == 3; }
};

} // namespace

void {{APP_C}}_ref_default_params({{APP}}RefParams* out)
{
    *out = {{APP}}RefParams{ 5.0f, 2.0f, 0.30f, 0.30f, 0.70f };
}

// The prototype's playing style: the platform's own (Poly, no glide, Bend 2).
void {{APP_C}}_ref_default_playing({{APP}}RefPlaying* out)
{
    *out = {{APP}}RefPlaying{ 0, 0.0f, 2, 2, 0 };
}

void {{APP_C}}_ref_render(const {{APP}}RefEvent* events, int numEvents,
                          const {{APP}}RefParams* paramSets, int numParamSets,
                          const {{APP}}RefPlaying* playing,
                          double voiceRate, int decimate, float* out, int frames)
{
    const int factor = decimate ? 2 : 1;
    const double hostRate = voiceRate / factor;
    auto setOf = [&](const {{APP}}RefEvent& e) { return std::clamp(e.params, 0, numParamSets - 1); };

    spike::Playing how;
    how.mode = playing->mode == 1 ? spike::Mode::Mono : playing->mode == 2 ? spike::Mode::Legato : spike::Mode::Poly;
    how.glideMs = playing->glideMs;
    how.bendUp = playing->bendUp;
    how.bendDown = playing->bendDown;
    how.pads = playing->pads != 0;
    how.velSens = paramSets[0].velsens;
    how.rehitContinues = false;     // Tone starts a re-hit key anew (kRehitContinues)

    // amended: a voice prototype per parameter set; on the pads one per pad, with the set its hits name.
    constexpr int kPads = 16;
    std::vector<Voice> parts;
    if (how.pads)
    {
        int setOfPad[kPads] = {};
        for (int i = 0; i < numEvents; ++i)
            if (events[i].kind == {{APP_UPPER}}_REF_NOTE_ON && events[i].key >= 0 && events[i].key < kPads) setOfPad[events[i].key] = setOf(events[i]);
        for (int pad = 0; pad < kPads; ++pad) parts.push_back(Voice(paramSets[setOfPad[pad]]));
    }
    else
        for (int set = 0; set < numParamSets; ++set) parts.push_back(Voice(paramSets[set]));

    std::vector<spike::Message> messages;
    for (int i = 0; i < numEvents; ++i)
    {
        const {{APP}}RefEvent& e = events[i];
        const double time = (double)std::llround(e.time * hostRate) / hostRate;     // amended: on a whole host frame
        switch (e.kind)
        {
            case {{APP_UPPER}}_REF_NOTE_ON:
                messages.push_back({ time, spike::Message::NoteOn, e.pitch, e.value, how.pads ? e.key : setOf(e), -1 });
                break;
            case {{APP_UPPER}}_REF_NOTE_OFF:
                messages.push_back({ time, spike::Message::NoteOff, e.key, 0.0f, how.pads ? e.key : 0, -1 });
                break;
            case {{APP_UPPER}}_REF_PEDAL:
                messages.push_back({ time, spike::Message::Pedal, 0, e.value, 0, -1 });
                break;
            case {{APP_UPPER}}_REF_BEND:
                messages.push_back({ time, spike::Message::Bend, 0, e.value, 0, -1 });
                break;
            default: break;
        }
    }

    // amended: the voices at voiceRate, which may be twice the host's.
    const spike::Samples sum = spike::perform(messages, parts, how, voiceRate, (double)frames / hostRate);
    {{APP_LOWER}}::HalfBand decimator;
    decimator.design();
    decimator.reset();
    for (int f = 0; f < frames; ++f)
    {
        const size_t i = (size_t)f * (size_t)factor;
        if (decimate) out[f] = decimator.process(i < sum.size() ? sum[i] : 0.0f, i + 1 < sum.size() ? sum[i + 1] : 0.0f);
        else out[f] = i < sum.size() ? sum[i] : 0.0f;
    }
}
