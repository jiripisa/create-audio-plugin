// The listening prototype (.planning/research/spike/) as a test reference: the placeholder
// instrument "Tone", a sine and its second harmonic under an Attack / Decay / Release envelope.
// Units are the prototype's own: ms and s, and fractions where the engine has percent.
#ifndef {{APP_UPPER}}_REFERENCE_H
#define {{APP_UPPER}}_REFERENCE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {{APP}}RefParams {
    float attack;       // ms, the linear rise from silence to full
    float decay;        // s, T60 while the key is held
    float release;      // s, T60 once it is let go
    float brightness;   // 0..1, the second harmonic's level
    float velsens;      // 0..1, how much a softer note is quieter
} {{APP}}RefParams;

// A note-on on `key` at `hz` with `params` (an index into the parameter sets), or with `noteOff`
// the release of the voice that `key` sounds.
typedef struct {{APP}}RefEvent { double time; int key; double hz; float velocity; int params; int noteOff; } {{APP}}RefEvent;

void {{APP_C}}_ref_default_params({{APP}}RefParams* out);

// Renders `frames` mono samples: the voices at `voiceRate`, events in the order given (sorted by
// time). A note-on on a key whose voice sounds fades that voice out in 3 ms and starts a fresh
// one. With `decimate` the voices' sum goes through the engine's half-band decimator and `frames`
// are at half the rate.
void {{APP_C}}_ref_render(const {{APP}}RefEvent* events, int numEvents,
                          const {{APP}}RefParams* paramSets, int numParamSets,
                          double voiceRate, int decimate, float* out, int frames);

#ifdef __cplusplus
}
#endif

#endif
