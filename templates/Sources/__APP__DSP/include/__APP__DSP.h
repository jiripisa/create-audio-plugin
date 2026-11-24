// {{APP}}DSP.h - C interface to the {{APP}} sound engine.
//
// One engine = the instrument's voices, sixteen at most, that the keyboard or the sixteen pads of
// a kit play. The Audio Unit (C++) and the standalone app (Swift, through {{APP}}Core) both drive
// it through these functions.
//
// Threads:
//   * {{APP_C}}_process() and {{APP_C}}_midi() belong to the audio thread.
//   * {{APP_C}}_post_midi(), the parameter setters/getters, {{APP_C}}_set_program(), the mode and
//     pad calls and {{APP_C}}_request_reset() may be called from any thread while audio runs,
//     the audio thread included: none of them locks or allocates.
//   * {{APP_C}}_prepare() and {{APP_C}}_reset() must not run concurrently with {{APP_C}}_process().
//
// Parameter values come in two forms: "plain" (the real value: s, Hz, dB, %, an index) and
// "normalised" (0..1, what a knob position is). The engine stores normalised values.
//
// Sets: the sound is a set of knobs (the parameters below). The keyboard has one set; each of
// the 16 pads has a set of its own, so that every pad can sound different. A set is addressed by
// an index: {{APP_UPPER}}_KEYBOARD_SET (0), or 1...16 for a pad.

#ifndef {{APP_UPPER}}_DSP_H
#define {{APP_UPPER}}_DSP_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {{APP}}Engine {{APP}}Engine;

enum { {{APP_UPPER}}_KIND_FLOAT = 0, {{APP_UPPER}}_KIND_INT = 1, {{APP_UPPER}}_KIND_CHOICE = 2 };
enum { {{APP_UPPER}}_MODE_KEYBOARD = 0, {{APP_UPPER}}_MODE_PADS = 1 };
enum { {{APP_UPPER}}_KEYBOARD_SET = 0, {{APP_UPPER}}_NUM_PADS = 16, {{APP_UPPER}}_NUM_SETS = 17,
       {{APP_UPPER}}_FIRST_PAD_NOTE = 36, {{APP_UPPER}}_NUM_GROUPS = 16, {{APP_UPPER}}_MAX_VOICES = 16 };

typedef struct {{APP}}ParamInfo
{
    const char* identifier;   // stable name used in saved state; never changes
    const char* name;         // shown to the user
    const char* unit;         // "s", "Hz", "ms", "dB", "%", "st", "ct" or ""
    int   kind;               // {{APP_UPPER}}_KIND_*
    float minValue, maxValue, defaultValue;   // plain values
    int   logarithmic;        // 1 = the knob travels logarithmically (times, frequencies)
    int   numChoices;         // > 0 only for {{APP_UPPER}}_KIND_CHOICE
    int   section;            // the section it is shown in (see {{APP_C}}_num_sections), -1 if none
} {{APP}}ParamInfo;

// ----- parameter, section and program tables (the same for every engine) --------------------
int         {{APP_C}}_num_params(void);
void        {{APP_C}}_param_info(int index, {{APP}}ParamInfo* out);
const char* {{APP_C}}_param_choice(int index, int choice);
float       {{APP_C}}_param_to_plain(int index, float normalised);
float       {{APP_C}}_param_to_normalised(int index, float plain);
// Text for a plain value, without the unit ("4.00", "-24.0", "Legato", "+1"). Returns buffer.
const char* {{APP_C}}_param_display(int index, float plain, char* buffer, int bufferSize);

// The Audio Unit's parameter ID of a parameter, and the parameter of an ID (-1 for none). An ID
// names a knob, or a source's amount on a knob, and never changes: knob k (its index, the knobs
// only grow at their end) is k, LFO l's amount on knob k is 1000 * (l + 1) + k, the velocity's
// 3000 + k. A parameter's index can move in a later version (an appended knob moves the amounts
// after it), its ID cannot. Saved state names parameters by ID or identifier, never by index.
int         {{APP_C}}_param_id(int index);
int         {{APP_C}}_param_index(int id);

// The sections the knobs are shown in (the instrument's, then "Master", the platform's knobs) and
// the knobs of each in the order they are shown: the app's panels and the Audio Unit's parameter
// groups. The amounts below are in no section.
int         {{APP_C}}_num_sections(void);
const char* {{APP_C}}_section_name(int s);
int         {{APP_C}}_section_size(int s);
int         {{APP_C}}_section_param(int s, int pos);   // a parameter index, -1 if none

// The modulation slots. Each of the two LFOs has an amount on every knob it can move, and the
// hit's velocity has one on every knob it can move: parameters of their own, shown in no
// section. The call gives the amount's index, or -1 for a knob that cannot be moved so.
int         {{APP_C}}_num_lfos(void);
int         {{APP_C}}_lfo_amount(int lfo, int param);
int         {{APP_C}}_vel_amount(int param);

int         {{APP_C}}_num_programs(void);
const char* {{APP_C}}_program_name(int p);
float       {{APP_C}}_program_value(int p, int param);   // plain
int         {{APP_C}}_program_sets(int param);           // 0 for "octave", which programs leave alone

// ----- one engine ---------------------------------------------------------------------------
{{APP}}Engine* {{APP_C}}_create(void);
void          {{APP_C}}_destroy({{APP}}Engine*);
// Sets the host sample rate and then resets the engine as {{APP_C}}_reset() does. A rate that is not
// positive and finite is ignored, and nothing is reset.
void          {{APP_C}}_prepare({{APP}}Engine*, double sampleRate);
// Silences every voice, puts the wheels at rest and the sustain pedal up, and forgets the keys
// held and the last note. The knob sets, the
// pads (notes, groups) and the mode stay as they are.
void          {{APP_C}}_reset({{APP}}Engine*);
// The same reset, done by the audio thread at the start of its next {{APP_C}}_process() call.
void          {{APP_C}}_request_reset({{APP}}Engine*);
// Host frames the output lags the MIDI: the decimator's delay below 88.2 kHz, where the voices run
// at twice the rate, and 0 from 88.2 kHz up.
int           {{APP_C}}_latency(const {{APP}}Engine*);
// The longest a voice can sound once its key is let go, in seconds: the Audio Unit's tail.
double        {{APP_C}}_tail_time(void);

float {{APP_C}}_get_plain(const {{APP}}Engine*, int set, int index);
float {{APP_C}}_get_normalised(const {{APP}}Engine*, int set, int index);
void  {{APP_C}}_set_plain({{APP}}Engine*, int set, int index, float plain);
void  {{APP_C}}_set_normalised({{APP}}Engine*, int set, int index, float n);

// Loads a built-in program into a set: every parameter but "octave" is overwritten. The octave
// belongs to the player's hands, not to the sound.
void  {{APP_C}}_set_program({{APP}}Engine*, int set, int program);
int   {{APP_C}}_get_program(const {{APP}}Engine*, int set);
// Records which program a set last loaded without loading it: no knob changes. For restoring saved
// state whose knob values come from elsewhere. A bad set or program is ignored.
void  {{APP_C}}_set_program_index({{APP}}Engine*, int set, int program);

// The mode: the keyboard plays the keyboard set at the pitch of each key, as the set's Voice Mode
// says (Poly: a voice per key; Mono: one voice, the last key held, each new note attacked anew,
// letting it go returns to the newest key still held; Legato: as Mono, but a note played while
// another key is held goes on without a new attack), gliding from note to note in Mono and
// Legato over the set's Glide; the pads play their own sets at the pitch of each pad, hit by
// notes 36-51 (other notes are ignored), whatever the voice mode. A voice already sounding when
// the mode or the voice mode changes sounds on as it was, until its note-off.
void  {{APP_C}}_set_mode({{APP}}Engine*, int mode);
int   {{APP_C}}_get_mode(const {{APP}}Engine*);

// Pads: each has a pitch (a MIDI note) and a group. The pads of one group share one voice: a hit
// on it while it sounds continues it, or fades it out for a fresh one, as the instrument does
// with a re-hit of a key, with the new pad's set and pitch. A pad whose group is 0 (Off) has a
// voice of its own. Like the pitch, the group belongs to the pad, not to its set. A pad's voice
// copies the pad's set at the hit and does not follow later changes to it, nor the wheels.
int   {{APP_C}}_pad_note(const {{APP}}Engine*, int pad);
void  {{APP_C}}_set_pad_note({{APP}}Engine*, int pad, int note);
int   {{APP_C}}_pad_group(const {{APP}}Engine*, int pad);
void  {{APP_C}}_set_pad_group({{APP}}Engine*, int pad, int group);   // 0 = Off
// How many times a pad has been hit since the engine was created: the panel flashes a pad when it
// changes. Counted on the audio thread; a reset leaves it alone. 0 for a bad pad.
int   {{APP_C}}_pad_hits(const {{APP}}Engine*, int pad);
int   {{APP_C}}_last_note(const {{APP}}Engine*);          // last keyboard-mode note-on since the last reset, -1 if none
// Copies the keyboard set (and its program) and the pitch of the last note (36 if none) to a
// pad; its group is kept. The copy goes value by value with relaxed atomics, not as a whole: a pad
// hit landing mid-copy freezes a mix of old and new values for that one hit.
void  {{APP_C}}_send_to_pad({{APP}}Engine*, int pad);
// The instrument's kit, built from its programs, so that pad mode sounds at once: what the pads
// hold when the engine is created. Overwrites every pad's set, note and group, value by value
// with relaxed atomics like {{APP_C}}_send_to_pad: a pad hit landing mid-load freezes a mix of old and
// new values for that one hit.
void  {{APP_C}}_load_default_kit({{APP}}Engine*);
int   {{APP_C}}_sounding_voices(const {{APP}}Engine*);    // voices playing and not being faded out

// MIDI from any thread; played in the next {{APP_C}}_process() call, sampleOffset frames into it
// (0 = at its start).
void  {{APP_C}}_post_midi({{APP}}Engine*, int status, int data1, int data2, int sampleOffset);
// MIDI from the audio thread with a sample offset into the next {{APP_C}}_process() call.
void  {{APP_C}}_midi({{APP}}Engine*, int status, int data1, int data2, int sampleOffset);
// One {{APP_C}}_process() call plays at most 256 events. Those from {{APP_C}}_midi() take that room
// first, and any beyond it are dropped. Posted events beyond it stay queued and play in the next
// call, in the order posted, at their sample offset into that call. The queue holds 512 posted
// events; an event posted while it is full is dropped.

// MIDI controllers on the keyboard set's knobs. Every knob comes with a controller (a control
// change number) and can be given another; a control change on any channel then puts the knob
// of the keyboard set where its value says: 0 the bottom of its travel, 127 the top, and 64 the
// middle of a knob that has one (-100 ... 100 %). A choice takes the choice nearest to the value.
// The pads' sets are never moved, not in pad mode either. A controller serves one knob, and the
// amounts have none. The control change is applied at its sample offset, in the order of the
// block's MIDI. Controllers 1 (the mod wheel, which moves what the instrument maps it to), 64
// (the sustain pedal: from 64 up it holds the keys' voices their note-offs release, in every voice
// mode, until it comes up; it holds no pad), 120 and 123 (every voice fades out, the pedal goes
// up, the keys held are forgotten) and 121 (the wheels at rest, the pedal up, which releases
// what it held, the keys held forgotten) keep their meanings. All of these may be called from any thread while audio runs.
int  {{APP_C}}_standard_controller(int param);               // what a knob comes with; -1 for none
int  {{APP_C}}_controller_reserved(int cc);                  // 1 for one MIDI or the engine keeps for itself
int  {{APP_C}}_get_controller(const {{APP}}Engine*, int param);          // -1 for none
// -1 takes the knob's controller away. A reserved controller is not taken; one another knob has
// moves to this one.
void {{APP_C}}_set_controller({{APP}}Engine*, int param, int cc);
void {{APP_C}}_reset_controllers({{APP}}Engine*);             // every knob back to its standard controller
// Learn: the knob takes the next controller that moves, not a reserved one, and goes where it
// says. -1 (or a parameter that is not a knob) calls it off.
void {{APP_C}}_learn({{APP}}Engine*, int param);
int  {{APP_C}}_learning(const {{APP}}Engine*);               // the knob that is learning, -1 for none
// Counts what MIDI changed without the caller: a knob moved by its controller, a controller
// learnt. A window compares it with what it saw last to know when to read the engine again: the
// count is raised after the change (release) and read with acquire, so a window that sees it rise
// reads the new values.
unsigned {{APP_C}}_changes(const {{APP}}Engine*);

// Renders `frames` samples. `right` may be NULL: left then gets the left channel.
void  {{APP_C}}_process({{APP}}Engine*, float* left, float* right, int frames);

#ifdef __cplusplus
}
#endif

#endif // {{APP_UPPER}}_DSP_H
