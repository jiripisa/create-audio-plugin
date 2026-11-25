// The listening prototype (.planning/research/spike/) as a test reference: the placeholder
// instrument "Tone", a sine and its second harmonic under an Attack / Decay / Release envelope,
// played by the prototype's own harness (spike_harness.h, beside {{APP}}Reference.cpp).
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
    float velsens;      // 0..1, how much a softer note is quieter (the platform's Vel Sens)
} {{APP}}RefParams;

// How the prototype is played: the harness's Playing, in the engine's terms.
typedef struct {{APP}}RefPlaying {
    int   mode;         // the engine's Voice Mode: 0 Poly, 1 Mono, 2 Legato
    float glideMs;      // Glide
    int   bendUp;       // Bend Up, semitones
    int   bendDown;     // Bend Down, semitones
    int   pads;         // 1: the events are pad hits (each pad a voice of its own)
} {{APP}}RefPlaying;

enum { {{APP_UPPER}}_REF_NOTE_ON = 0, {{APP_UPPER}}_REF_NOTE_OFF = 1, {{APP_UPPER}}_REF_PEDAL = 2, {{APP_UPPER}}_REF_BEND = 3 };

// One thing played, as MIDI tells the engine.
typedef struct {{APP}}RefEvent {
    double time;        // s
    int    kind;        // {{APP_UPPER}}_REF_*
    int    key;         // a note-on or note-off: the MIDI note on the keyboard, the pad (0 ... 15) on the pads
    int    pitch;       // a note-on: the note it sounds at (the key on the keyboard, the pad's note on the pads)
    float  value;       // a note-on: velocity 0..1; the pedal: 1 down, 0 up; the bend: -1 ... +1
    int    params;      // a note-on: its parameter set (an index into the sets)
} {{APP}}RefEvent;

void {{APP_C}}_ref_default_params({{APP}}RefParams* out);
void {{APP_C}}_ref_default_playing({{APP}}RefPlaying* out);

// Renders `frames` mono samples: the voices at `voiceRate`, the events played by the harness in
// the order given (sorted by time). With `decimate` the voices' sum goes through the engine's
// half-band decimator and `frames` are at half the rate.
void {{APP_C}}_ref_render(const {{APP}}RefEvent* events, int numEvents,
                          const {{APP}}RefParams* paramSets, int numParamSets,
                          const {{APP}}RefPlaying* playing,
                          double voiceRate, int decimate, float* out, int frames);

#ifdef __cplusplus
}
#endif

#endif
