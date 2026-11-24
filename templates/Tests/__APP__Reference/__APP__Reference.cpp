// {{APP}}Reference.cpp - the listening prototype's voice and renderer, copied from
// .planning/research/spike/ as the reference the engine is tested against. Throwaway code: do
// not "fix" or tidy it.
//
// Amended where the engine must differ, each marked "amended":
//   * the rate is a variable, and an event names the parameter set of its note, so that the pads
//     can each have their own;
//   * a note-on on a key whose voice sounds fades that voice out by 40 dB in 3 ms and starts a
//     fresh one, as the engine does with a re-hit;
//   * the voices' sum can go through the engine's half-band decimator (HalfBand.h), as the
//     engine's does below 88.2 kHz.
//
// No fused multiply-add: the rendering must be the same in debug and release builds.
#pragma clang fp contract(off)

#include <algorithm>
#include <cmath>
#include <vector>

#include "../../Sources/{{APP}}DSP/HalfBand.h"
#include "{{APP}}Reference.h"

namespace {

constexpr double kPi = 3.14159265358979323846;

struct Voice
{
    int key = 0;
    double hz = 440.0, phase = 0.0, env = 0.0, gain = 1.0;
    int stage = 0;                  // 0 rising, 1 held, 2 released, 3 done
    {{APP}}RefParams p{};
    bool choking = false;           // amended: the fade of a re-hit voice
    double choke = 1.0, chokeMul = 1.0;

    double next(double rate)
    {
        const double dt = 1.0 / rate;
        switch (stage)
        {
            case 0: env += dt / (p.attack / 1000.0); if (env >= 1.0) { env = 1.0; stage = 1; } break;
            case 1: env *= std::exp(-6.907755278982137 * dt / p.decay); break;
            case 2: env *= std::exp(-6.907755278982137 * dt / p.release); break;
            default: env = 0.0; break;
        }
        if (stage != 0 && env < 1e-5) { env = 0.0; stage = 3; }
        const double x = 2.0 * kPi * phase;
        double y = env * (std::sin(x) + p.brightness * std::sin(2.0 * x)) * gain * choke;
        phase += hz * dt;
        if (phase >= 1.0) phase -= std::floor(phase);
        if (choking) choke *= chokeMul;
        return y;
    }

    bool done() const { return stage == 3 || (choking && choke < 1e-5); }
};

} // namespace

void {{APP_C}}_ref_default_params({{APP}}RefParams* out)
{
    *out = {{APP}}RefParams{ 5.0f, 2.0f, 0.30f, 0.30f, 0.70f };
}

void {{APP_C}}_ref_render(const {{APP}}RefEvent* events, int numEvents,
                          const {{APP}}RefParams* paramSets, int numParamSets,
                          double voiceRate, int decimate, float* out, int frames)
{
    const int factor = decimate ? 2 : 1;
    const double hostRate = voiceRate / factor;
    std::vector<{{APP}}RefEvent> sorted(events, events + numEvents);
    std::stable_sort(sorted.begin(), sorted.end(), [](const {{APP}}RefEvent& a, const {{APP}}RefEvent& b) { return a.time < b.time; });
    std::vector<Voice> voices;
    {{APP_LOWER}}::HalfBand decimator;
    decimator.design();
    decimator.reset();

    size_t next = 0;
    std::vector<double> sum((size_t)frames * factor, 0.0);
    for (size_t i = 0; i < sum.size(); ++i)
    {
        while (next < sorted.size() && (size_t)std::llround(sorted[next].time * hostRate) * factor <= i)
        {
            const {{APP}}RefEvent& e = sorted[next++];
            if (e.noteOff)
            {
                for (Voice& v : voices) if (v.key == e.key && !v.choking && v.stage != 3) v.stage = 2;
                continue;
            }
            for (Voice& v : voices)
                if (v.key == e.key && !v.choking && !v.done())
                {
                    v.choking = true;
                    v.chokeMul = std::exp(-1.0 / (0.003 / 4.6 * voiceRate));
                }
            Voice v;
            v.key = e.key;
            v.hz = e.hz;
            v.p = paramSets[std::clamp(e.params, 0, numParamSets - 1)];
            v.gain = 1.0 - v.p.velsens * (1.0 - e.velocity);
            voices.push_back(v);
        }
        double y = 0.0;
        for (Voice& v : voices) if (!v.done()) y += v.next(voiceRate);
        voices.erase(std::remove_if(voices.begin(), voices.end(), [](const Voice& v) { return v.done(); }), voices.end());
        sum[i] = y;
    }
    for (int f = 0; f < frames; ++f)
        out[f] = decimate ? decimator.process((float)sum[2 * (size_t)f], (float)sum[2 * (size_t)f + 1]) : (float)sum[(size_t)f];
}
