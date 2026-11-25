# Listening prototype (step 2, the sound gate)

No product code exists until the user has approved these renders. Names: `<skill>`, `<scratch>`,
`<proj>`, `<slug>` (`APP_LOWER`) as in the intake.

## Files

```
.planning/research/spike/
  <slug>_spike.cpp      the prototype (main session writes it from the report)
  spike_harness.h       copied from <skill>/scripts/ (the spike folder builds on its own)
  LISTENING.md          the listening guide (template below)
  renders/              the WAV files; gitignored by the template's .gitignore (phase 01)
  renders/references/   recordings to compare with; never committed, never shipped
<scratch>/<slug>_spike  the binary: built into the scratchpad, never beside the source
```

There is no git repo yet; phase 01 renders `.gitignore` with `.planning/research/spike/renders/`
before the first commit. Check `git status` there that no WAV and no binary is staged: the spike
folder is committed as it is, so nothing is ever built into it.

## Writing the spike

Follow `<skill>/scripts/spike_example.cpp`. Only the instrument is new:

- `struct Params`: the report's starting numbers as defaults ("Recommendation for the engine").
  Only instrument knobs: Volume, Pan, Tune, Octave, Bend, Voice Mode, Glide, the LFOs and Vel
  Sens are the platform's.
- `struct Voice`, with the four calls of the engine's `Voice.h`:
  `void start(const spike::Knobs&, int note, float velocity, bool continuing)`, `void release()`,
  `void render(float* out, int frames)` (1 to 16 samples), `bool finished() const`. It holds a
  pointer to its `Params` and can be copied: every fresh note starts on a copy.
- `spike::Playing`: how the instrument is played, the report's "Playing style": Voice Mode
  (`Mode::Poly`, `Mono`, `Legato`), `glideMs`, the bend range, and `rehitContinues` (what a
  note-on on a sounding key does: continue the voice, or fade it out in 3 ms and start a fresh
  one). It becomes the spec's `kPlatformDefaults` and `kRehitContinues`.
- One function per program returning `Params`; `renders()`; `references()`;
  `int main(int argc, char** argv) { return spike::run(argc, argv, renders(), references()); }`.

**The harness plays the score as the plug-in will** (`spike::play`: the engine's voice pool, rule
for rule): the re-hit rule, Poly / Mono / Legato with the engine's glide, the sustain pedal
(`Score::pedal`), the pitch bend (`Score::bend`, `bendSlide`), Vel Sens on the level, sixteen
voices with the quietest stolen, pads and groups (`Playing::pads`). So a phrase on one key does
not ring over itself unless the instrument continues, and a melody of a Legato instrument glides
in the render exactly as it will in a host. Never render for the ear with `Playing::layered` (the
example's `00_check_*` test signals only).

Write the voice as the engine will run it, so phase 02 can port it line by line:
- the pitch is `knobs.hz(note)`, read in `render()`, so that it bends and glides; every
  coefficient is computed from `knobs.rate` (the engine runs voices at twice the host's rate
  below 88.2 kHz, at the host's rate above);
- the level is free of the velocity: the harness applies the platform's Vel Sens
  (`1 - 0.7 (1 - velocity)`); anything else velocity does (colour, attack) belongs to the voice;
- `continuing` (a re-hit the instrument continues, a legato note, a return to a key still
  held): go on at the new note with no new attack; what that sounds like is the instrument's;
- **randomness**: the voice owns a `std::mt19937`, seeds it with `spike::kVoiceSeed` in every
  fresh start (`continuing` false, never elsewhere) and draws through `uniform()` / `white()`.
  Nothing else is random (no shared generator, no clock, no count of hits): two equal notes are
  equal samples, here and in the engine, which seeds the same way (`Voice.h`), so the port is
  draw for draw. Hit-to-hit variation is the player's (velocity, a VEL amount, an LFO with
  Start = Free) or a continuing voice's (its stream goes on);
- `std::exp2` for powers of two (the harness turns fused multiply-adds off for the whole file);
- no allocation in `render()`; a strum or any multi-note gesture on one key lives in the voice;
- **whatever the voice does to its pitch by itself has a knob**: a vibrato's depth, a pitch
  envelope's amount, drift or detune, each a field of `Params` that 0 turns off; a release
  longer than about 1.5 s is a field too. The platform's tests play the instrument with those
  turned off or down (`kTestSound`, spec §6); an effect that no knob reaches cannot ship.

Build and write, the binary into the scratchpad:
`clang++ -std=c++17 -O2 <slug>_spike.cpp -o <scratch>/<slug>_spike && <scratch>/<slug>_spike renders`
(run in the spike folder). `<scratch>/<slug>_spike --analyze <prefix>` is the quick check while
tuning; `analyze.swift` gives the numbers that are reported. `00_check_*` renders belong to
`spike_example.cpp` only; the run's spike has none.

## Naming renders by question

- `NN_<topic>_<variant>`: one group per "Question for the user's ear", in the report's order;
  variants lettered with the value in the name and the default marked: `02_ring_A_0.6s`,
  `02_ring_B_1.8s_default`, `02_ring_C_4s`.
- `01_default` answers the decisive question ("a real <instrument> or a synthesizer?"). Give it
  several takes when one is not enough (`01a` one note, `01b` a phrase, `01c` the instrument's
  typical pattern).
- `P01_<program>` … one per planned program; `K01_kit` a groove over the planned default kit when
  the instrument is played on pads (`Playing::pads`: each pad a part with its own `Params`, the
  event's key the pitch it sounds at, `groups` for pads that share a voice).
- Every group plays the instrument's typical material (strokes and a phrase, or a melody, or
  chords), at the register the report names. Include long tails, a quiet passage, a soft note
  with its full release, and a held note.
- **How it plays**, one group, for every instrument: a re-hit of a sounding key (the rule chosen:
  `rehitContinues`), and the fullest gesture of the playing style at full velocity (a full chord
  or strum, the kit's busiest bar: the level is set by it, spec §8). For a melodic instrument
  also: a legato phrase and the same phrase detached, in the Voice Mode and Glide the report
  recommends, a glide over a wide interval with a return to a key still held, a bend if the
  instrument is bent, held notes under the sustain pedal if it is played with one. These are
  approved like the sound: the plug-in will play exactly this from the same notes.
- `S01_silence_<case>` …: one render per way a voice ends (a note-off, a choke by a re-hit, a stroke
  ringing out), rendered until the voice is over for good (`finished()`) and half a second
  more: `Score::untilOver()`. Never guess the tail from the T60 alone: a voice that ends at
  -80 dB needs 1.4 x T60 after its last event (80 / 60, and a margin), one that ends at -100 dB
  1.7 x, and the harness's default `kTail` is only 2 s; where a tail is given in seconds
  (`withTail`), it is at least 1.4 x the case's longest T60. These are the renders the silence
  bar below applies to; LISTENING.md lists them as measurement renders (the user may skip them).
- Peak-normalise each render to -1 dBFS (`normalize()`), so files differ in colour, not level.
- Later rounds: A/B on the same score, level-matched: `R2_<topic>_A_before`, `R2_<topic>_B_after`.

References: copy the report's recommended recordings from the research's download folders into
`renders/references/` as `R<n>_<what>_<register>.wav` (`afconvert -f WAVE -d LEI24 <in> <out>`), and
list each in `references()` with URL, author, licence and the renders it answers. The spike
prints `present` or `MISSING` for each after rendering.

## Measuring before showing

Every file is measured before the user hears anything:

```
swiftc -O <skill>/scripts/analyze.swift -o <scratch>/analyze
<scratch>/analyze renders/*.wav --json > <scratch>/measure-renders.json
<scratch>/analyze renders/01a_default.wav --ref renders/references/R1_<…>.wav
<scratch>/analyze renders/<file>.wav --tail <a-b>     # seconds from the file's START
```

`--tail a-b` counts from the start of the file; for windows near the end compute them from the
file's length (`durationS` in the JSON): the last 0.5 s is `--tail <d-0.5>-<d>`, an earlier one
`--tail <d-1.5>-<d-1>`.

Check and write down:
- against the recordings (same register): H2…H8 within about 3 dB of the recording's, HNR and
  centroid inside the recordings' ranges, attack, decay/T60 and release against the measured
  ones, f0 found where it should be (the tool finds the pitch first; a "too good" match is
  re-checked by hand);
- **the tails** (Brumle's hiss was found only by the ear):
  - every render: the level falls between an earlier and a later window near the end (above),
    never flat while the note should be dying; a flat floor is noise left in the voice, and
    `tail.centroidHz` says hiss (high) or hum (low). A ringing instrument may still be loud at the
    file's end (a pluck at -40…-50 dBFS 2 s on): that is fine as long as it falls at the rate its
    T60 says;
  - the `S…_silence_*` renders, where the voice is over: `tail.floorDb` of the last 0.5 s at or
    below -80 dBFS; -200 (digital silence) is a pass;
  - fix a flaw in the spike before sending;
- for phrases and grooves of **one note at a time** (a melody, a groove on one pad or key at a
  time): `strokes.count` equals the notes of the score, `strokeRate` against the research's;
  `strokesSuspect` true means the count is not to be trusted (re-measure one stroke with
  `--window`). Do not count where notes sound together: the analyser splits a low chord into
  several strokes and misses a high stroke over a ringing low note, so chords, strums and
  layered kits are checked by level and by ear only;
- no file clipped (the writer warns), none silent.

## LISTENING.md

```markdown
# <APP_NAME> listening prototype: what to listen to

Throwaway prototype `<slug>_spike.cpp`: the research report's <model>
(`../reports/<Title>.md`, "Recommendation for the engine"). Renders in `renders/` (48 kHz,
24 bit, mono, each peak-normalised to -1 dBFS). Reference recordings (CC0 / CC BY, for listening
only, never committed or shipped) in `renders/references/`.

Rebuild (the binary goes to a temporary folder, never beside the source):
`clang++ -std=c++17 -O2 <slug>_spike.cpp -o "$TMPDIR/<slug>_spike" && "$TMPDIR/<slug>_spike" renders`

Measured, not heard: <the numbers against the recordings: harmonics, HNR, centroid, envelope,
tail floors, stroke counts>.

Listen first: `01…` against `references/R1…`. **Does it sound like a real <instrument>, or like a
synthesizer?** If it sounds like a synthesizer, the fallback is <the report's named fallback
model, its cost>.

| # | Question (report "Questions for the user's ear") | Files | Compare with |
|---|---|---|---|
| 1 | A real <instrument> or a synthesizer? | `01a`, `01b`, `01c` | `references/R1` |
| 2 | … | `02_…_A/B/C` | |
| n | Does it play right: the re-hit, legato and glide, the bend, the pedal? | `0n_…` | |
| Programs | Does each sound like its name? | `P01…` | `R…` |

Answer briefly, only where you are sure: "01 ok / no + why, 02 B, 03 A …".

## Rounds
- Round 1 (<date>): sent. Verdict: …
```

## Presenting

In the user's language, one message:
1. **"Measured, not heard"**: I cannot hear the files; what was checked and the key numbers.
2. The decisive question first, then the listening order (the table), the fallback named.
3. How to answer (short codes; only where sure).
4. `open .planning/research/spike/renders` and the Quick Look tip: select a file, press Space,
   step with the arrow keys; the references are in `references/`.

Then wait. Nothing is built meanwhile (research reading and the spec draft are allowed; no
template render, no product code).

## The loop

- Not approved: change the spike, re-render, measure, add a round to `LISTENING.md`, send the
  changed files (A/B against the previous version on the same score) with the same message form.
- **The same aspect rejected twice: stop tuning it.** Ask for a reference recording the user
  finds right, or offer to drop the feature, knob or program. No third attempt by measurement
  (Didgeridoo's overblown note failed three times and was removed).
- Approved: write the verdict verbatim and the date into `LISTENING.md` (it goes into the spec's
  status and `STATE.md`). The approval message may rename programs or correct the identity once
  more; apply that before the spec (a corrected name: `identity.py` and the name-free check
  again, SKILL.md step 0.6).
