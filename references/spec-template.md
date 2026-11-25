# Instrument design spec (step 3.1)

Written right after the sound is approved, before phase 01, as
`.planning/specs/<YYYY-MM-DD>-instrument-design.md`. Approval of the spec is delegated by the
user's choice of this skill: nobody waits for it. It fixes, before the first build, everything
that is permanent: the identity, the parameter identifiers and their order, the programs' order.

Markers on every decision: **[user]** decided by the user; **[ear]** approved by the user's ear
on the prototype's renders; **[call]** a call made here, open to correction; **[builder]** left
to whoever builds, who records the choice in the phase's `VERIFICATION.md`.

## Template

```markdown
# <APP_NAME> — design of the instrument

Status: written <date> after the user's listening. The user approved the prototype's renders
("<verdict, verbatim>", <date>) [user]. The user started this run with the create-audio-plugin
skill, which builds and prepares the release autonomously: approval of this document is
delegated, and every [call] below is open to the user's correction at any point. Still to
come from the user: <in a "three concepts" run: the pick of the look, and> the push question at
the end.

Sources: `.planning/research/reports/<Title>.md` (and its notes), the listening prototype
`.planning/research/spike/<slug>_spike.cpp` with `LISTENING.md`. Platform: the create-audio-plugin
template (`<skill>/TEMPLATE_MANIFEST.md` describes its seam).

Marking: [user] the user; [ear] the user's ear on the renders; [call] a call made here, open to
correction; [builder] left to the builder, recorded in VERIFICATION.md.

## 1. Intent and the why
What the instrument is (the real one, its family), what the user asked for (verbatim), what it is
mainly for (melody, rhythm or drone) [user/call], what a synthesized version can do that samples
cannot.

## 2. Goals, non-goals, anti-goals
Goals: the platform's whole feature set (keyboard and 16 pads, groups, Send to pad, programs,
presets, kits, LFO and VEL amounts on knobs, MIDI CC per knob with learn, voice modes, glide,
sustain, the app's MIDI and audio settings, the app installing the plug-in, Sparkle, the website
and manual EN + CS, a signed and notarized DMG); the prototype's sounds are the bar [ear]: every
approved render can be made with the plug-in's knobs and programs.
Non-goals: samples shipped (references are for listening only); an internal sequencer; AUv3,
VST, Intel; <instrument-specific>.
Anti-goals: the plug-in sounds different from the approved renders; a pad that does not behave
exactly like a key press of its frozen sound; allocation, locks, logging or I/O on the audio
thread; changing an identifier, the parameter order, a program's index or the AU's codes after
the first release; words of another instrument in code, texts or the site.

## 3. Constraints
SwiftPM + build.sh, never an Xcode project; macOS 27, Swift 6.4 tools, Apple silicon; C++ engine
under `#pragma clang fp contract(off)`, `std::exp2`; zero build warnings; the suite green in debug
and release and under TSan.
The permanent identity [user at intake]:

| | |
|---|---|
| Display name (`APP_NAME`) | <…> |
| Code name (`APP`), slug (`APP_LOWER`), C prefix (`APP_C`) | <…> |
| Bundle ids | `io.jp4.<slug>`, `io.jp4.<slug>.audiounit` |
| AU | type `aumu`, subtype `<SUB>`, manufacturer `JPis`, name `Jiri Pisa: <APP_NAME>` |
| Factory, view class | `<APP>AUFactory`, `<APP>AUViewFactory` |
| Files | presets `*.<slug>`, kits `*.<slug>kit`, `~/Library/Application Support/<APP>/{Presets,Kits}` |
| Repo, site, feed | `jiripisa/<slug>` (public, MIT), `https://jiripisa.github.io/<slug>/`, `…/appcast.xml` |
| Sparkle key | the shared `SUPublicEDKey` of the template |
| Taglines | EN "<…>", CS "<…>" (no `"`, `\`, `$`, backtick or ": ") |

## 4. Approaches
Product: the platform template (fixed by the skill). Sound: the report's candidate models with
their costs, the one chosen [ear] and the named fallback.

## 5. The sound: what one voice does [ear]
The signal path as pseudo-code with the prototype's formulas, block by block, in the
prototype's units. What start (note-on), continuing, release and finished mean for this voice.
What velocity does inside the voice (colour, never level: the platform applies Vel Sens).

## 6. Parameters
The table in its permanent order; identifiers lowercase ASCII letters and digits, unique.
1. The platform block, IDs 0-13, as the template has it (not changed, not repeated per
   instrument): volume, pan, tune, octave, bendup, benddown, voicemode, glide, lfostart,
   lfo1rate, lfo1shape, lfo2rate, lfo2shape, velsens.
2. The instrument's knobs from ID 14:

| ID | Section | Identifier | Name | Range (scale) | Default | Unit | CC | LFO? |
|---|---|---|---|---|---|---|---|---|

   Defaults are the prototype's `Params` [ear for knobs the renders exercised, call for the
   rest]. CC: the General MIDI controller for the thing where there is one, else 14-31, 85-90,
   113-119; never 5, 7, 10, 102-112 (the platform's) or a reserved one.
3. LFO amounts: LFO 1 on each `kLfoTargets` knob (`lfo1<id>`), then LFO 2 (`lfo2<id>`).
   `kLfoTargets` holds volume, pan, tune and <…>.
4. VEL amounts (`vel<id>`) on every continuous instrument knob and volume, pan, tune, lfo1rate,
   lfo2rate; never velsens. All amounts -100 … 100 %, 0.
Mod wheel and aftertouch: `{ knob, depth }` pairs <…>. Total: <n> parameters.
Audio Unit IDs (`TEMPLATE_MANIFEST.md` "Stable IDs"): knob k → k; LFO l's amount on knob k →
1000·(l + 1) + k; VEL amount on knob k → 3000 + k. After the first release knobs are only
appended; nothing is renamed, removed or reordered.

## 7. Modes and voices
Keyboard mode: the playing style [call from the report's "Playing style"]: the Voice Mode, Glide
and bend range the instrument wants. The platform block's defaults are fixed (Poly, Glide 0, Bend
2/2, `ParameterTableTests`) and a fresh instance starts on the table's defaults, not on a
program's overrides, so `kPrograms[0]` (the default sound) has no overrides; the programs that
need another playing style set Voice Mode, Glide and Bend Up/Down as overrides. `kRehitContinues` (true: a re-hit continues the
sounding voice; false: it fades out in 3 ms and a fresh voice starts). Sustain pedal as the
platform does it. What the voice does with `continuing`.
Pads: 16 pads, each one frozen key press (one program and knob set, one note, a group); every
pad's set has its own VEL amounts; groups are one voice each (Off or 1-16). No chord or strum
pads; a gesture on one key is inside the voice. The default kit (`kDefaultKit`): per pad the
program, the note, the group, overrides.

## 8. Programs [ear]
In their permanent order (`kPrograms`, index kept by presets and projects): name, the overrides
of the defaults, which render they come from. At least two; none sets Octave.
Acceptance bar: the engine renders every prototype score with a residual below -60 dB against
the reference copy of the prototype, at 96 kHz and through the decimator at 48 kHz; debug and
release render the same samples; the default note at full velocity peaks near -6 dBFS.

## 9. Architecture
The template's targets, unchanged. The instrument's files: `Sources/<APP>DSP/Params.h`,
`Voice.h`, `Tests/<APP>Reference/*` and the instrument tests (`PrototypeScores`,
`PrototypeEquivalenceTests`, `SoundRegressionTests`, `ListeningRenders`, `Grooves`,
`ReferenceTests`, `InstrumentTableTests`), `SectionLayout` plans, `Artwork.swift`,
`Resources/Art/*`, `Resources/AppIcon.png`, the site's and manual's bodies. `kOutputLevel`,
`kTailSeconds`. Anything else that would change is named here with why [call].

## 10. The panel, the art and the website
Sections in order (`kSections`; Master last) and how the cards are laid out. The look: "three
concepts, the user picks" or "two concepts, the main session picks and writes why" [user at
intake], or native SwiftUI without raster art (no Codex) [call]; the direction of each concept
and what must not be copied (a living tradition's designs). Assets: `background`, `figure`,
`logo`, `knob`, `ornament`. Website and manual EN + CS, tag for tag.

## 11. Phases and the version [call]
| Phase | Goal |
|---|---|
| 01-skeleton | the template rendered, identity, green on the placeholder engine |
| 02-engine | `Params.h`, `Voice.h`, reference, equivalence, regression, `auval` |
| 03-panel-design | Codex concepts, pick, assets (or the native look) |
| 04-app-and-audiounit | panel, presets, kits, MIDI learn, AU in a host, manual EN + CS |
| 05-icon-website | icon (actool), website texts and look |
| 06-v1.0.0-release | DMG, appcast, tag; publishing only after the user's yes |
The first public release is 1.0.0 [user, fixed default].
```

## After writing

- **Builder check**: a fresh `general-purpose` subagent reads the spec (and nothing of this
  conversation) as the person who must plan phase 02 from it, and lists only the questions where
  a wrong guess would matter. The main session answers each in the spec as a [call] (the user is
  not asked) and dates the amendment. Brumle's check found a render the knobs could not make.
- Check every approved render can be made with §6 and §8; a render that cannot is a missing knob
  or a missing program, fixed here, not in phase 02.
- A knob or feature no approved render exercises is marked [call] and listed in the final report;
  one the user rejected at the gate is not in the table, the programs or the panel.
- The spec is committed with the research in phase 01. Later changes are amendments with a date
  and a marker, never silent edits.
