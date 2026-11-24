// The listening prototype (.planning/research/spike/{{APP_C}}_spike.cpp) as a test reference.
// Units are the prototype's own: fractions, not percent, and its "off" levels are -200 dB.
#ifndef {{APP_UPPER}}_REFERENCE_H
#define {{APP_UPPER}}_REFERENCE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {{APP}}RefParams {
    float attack, length, release, damp; int keyupStop;
    float alternate, alttune, vary, velsens;
    float scoop, scooptime, drift, drop, wobble, jump, jumpratio, veltune;
    float stick, stickvel, split, creak, creakrate, creakring;
    float pot, potq, potlevel, skin, skinq, skinlevel, track;
    float rub, scrape, shimmer;
} {{APP}}RefParams;

// A stroke on `drum` at `hz` with `params` (an index into the parameter sets), or with `noteOff`
// the moment the key of the drum's stroke is let go (the prototype's `hold`).
typedef struct {{APP}}RefEvent { double time; int drum; double hz; float velocity; int params; int noteOff; } {{APP}}RefEvent;

void {{APP_C}}_ref_default_params({{APP}}RefParams* out);

// Renders `frames` mono samples: the drums' voices at `voiceRate`, events in the order given
// (sorted by time). A drum sounds with one voice; a stroke on a silent drum starts a fresh one,
// whose generator is seeded 1, 2, 3, ... in the order the voices start. With `decimate` the
// voices' sum goes through the engine's half-band decimator and `frames` are at half the rate.
void {{APP_C}}_ref_render(const {{APP}}RefEvent* events, int numEvents,
                          const {{APP}}RefParams* paramSets, int numParamSets, int numDrums,
                          double voiceRate, int decimate, float* out, int frames);

#ifdef __cplusplus
}
#endif

#endif
