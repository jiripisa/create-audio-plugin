# Design: the `create-audio-plugin` skill

Date: 2026-11-24. Author of the request: the user (Czech conversation). Sources:
`~/Development/Claude/SHARED/{Brumle,Didgeridoo,Fanfrnoch}-build-process.md` (the three build
reports, written to be the input of this skill) and the projects themselves in
`~/Development/Claude/{Brumle,Didgeridoo,Fanfrnoch}`.

Decision markers: **[user]** decided by the user in the conversation, **[call]** my design call
(open to correction), **[builder]** left to whoever implements this design.

## 1. Intent and why

The user has built three synthesized real instruments as AUv2 plug-ins plus standalone macOS
apps (Didgeridoo, Brumle, Fanfrnoch). Each took 5–19 hours and most of the work was the same
platform rebuilt or copied. The user wants to say only "I want an audio plug-in for an electric
guitar" and get, as fast as possible, a released app downloadable from a GitHub Pages site.
**[user]**

The user's involvement in a run is limited to **[user]**:

1. **Start:** confirm the name, which is the name of the directory the skill is run in, and
   answer one question about the look: "three concepts to pick from" or "leave it to you".
2. **The sound:** listen to the prototype's renders and approve them (or say what to change;
   the loop repeats until approved). This is the only gate on the sound.
3. **The look** (only if they chose three concepts): pick one.
4. **The end:** one question, "push to GitHub?". Everything is prepared locally before it.

Everything else (the spec, the engine, art, panel, presets, manual, icon, website, signed and
notarized DMG) the skill does autonomously, deciding by itself what of the earlier projects
to reuse. **[user]**

## 2. Goals, non-goals, anti-goals

Goals:
- One invocation → a public GitHub repo, a GitHub Release with a notarized DMG, a bilingual
  website with manual and download button, Sparkle updates, a catalog entry.
- As fast as possible per instrument: target a few hours of wall-clock time after the sound is
  approved, most of it unattended.
- Every lesson in the "what went wrong" sections of the three reports becomes a guard in the
  skill.

Non-goals:
- Sample-based instruments, AUv3, VST/CLAP, Windows, Intel, App Store, the MPC plug-in.
- Effects plug-ins (the skill builds instruments, `aumu`).
- Updating instruments that already exist (later releases use each project's own `release`
  skill).

Anti-goals (a failure even if it builds):
- The plug-in sounds different from the renders the user approved.
- Product code written before the sound is approved (the Didgeridoo detour).
- Anything pushed, any repo created or Pages turned on before the final "yes".
- The skill disturbs the user's machine: whole-screen captures, keystrokes into other apps,
  streams opened on the user's audio interface, settings files left in `~/Library`.
- Words of a previous instrument left in code, texts or the website.

## 3. Constraints

- Global `~/.claude/CLAUDE.md` rules apply and are not overridden: push only after an explicit
  question; no AI attribution trailers; launch the build by path, capture only a window of the
  PID the skill launched; actool for the icon; clean up helper programs' settings; a
  subagent's "could not run the tests" is not a pass; never write to connected hardware.
- Toolchain on this Mac: SwiftPM + `build.sh`, no Xcode project; full Xcode for actool;
  Developer ID certificate and the `notary` keychain profile; the shared Sparkle EdDSA key in
  the login Keychain (one key for all of the user's apps); `gh` logged in as `jiripisa`;
  Codex CLI (`codex-cli 0.153.4`) installed; no numpy/scipy/ffmpeg/sox (audio analysis is
  Swift + Accelerate, conversion is `afconvert`).
- Platform: **macOS 27 minimum, always, using the newest libraries and UI elements** **[user]**
  (the SDK on this Mac; `swift-tools-version` 6.4 per `new-macos-app`'s `TOOLS_FOR_MACOS`;
  the newest Sparkle; current SwiftUI/Liquid Glass APIs instead of the macOS 26 ones Fanfrnoch
  uses where the SDK offers a newer one). Apple silicon only **[call]**. The template is moved
  from Fanfrnoch's macOS 26 to 27 once, during extraction, and is kept current in the skill.
- Runs happen in Claude Code's **auto mode** **[user]**, with no extra allowlist. The skill
  does not change permission settings. Steps that may need the sandbox off (window capture,
  installing the component for `auval`, Codex, headless Chrome) are written so that a refusal
  is reported in `VERIFICATION.md` and the run goes on, instead of waiting.
- Permanent identity per instrument (AU type `aumu`, a 4-char subtype, manufacturer `JPis`,
  bundle id `io.jp4.<slug>`, factory and view class names, parameter IDs) is fixed in the spec
  before the first build and never changes.

## 4. Approaches

Considered:

- **A. Copy the newest released sibling at run time** (how Fanfrnoch was made, ~5 h). Fast,
  but depends on a sibling repo being present and in good shape, leaks the old instrument's
  words, bakes in the rhythmic pad model (a melodic instrument would be reworked every run),
  and does not really use `new-macos-app`.
- **B. `new-macos-app` skeleton, then rebuild the platform from the siblings' code** (how Brumle
  was made, ~19 h). Every run rebuilds the same platform; against "as fast as possible".
- **C. A platform template inside the skill.** Extract once, now, a neutral instrument platform
  from Fanfrnoch 1.0.0 into the skill's `templates/`, extended once with melodic playing, with
  a placeholder engine in place of the instrument. Each run renders it with the
  `new-macos-app` renderer and plugs in a new engine, art and texts.

**Chosen: C** **[user]** (I recommended it; the user answered "c"). Fastest and cleanest per
run, independent of any sibling, melodic support built once, and `new-macos-app` is really
reused. Cost: building the skill now takes longer.

## 5. What a run looks like

The user creates a directory, e.g. `~/Development/Claude/Strunobijec`, starts Claude Code in
it and says "chci audio plugin pro elektrickou kytaru".

### Step 0 — Intake (the only questions before the sound)

1. Derive the identity from the directory name **[user]**: `APP_NAME` (the directory name as
   written), `APP` (PascalCase), `APP_LOWER` (slug), `BUNDLE_ID` `io.jp4.<slug>`, the AU
   subtype (4 chars, first letter capital, e.g. `Strn`), manufacturer `JPis`.
2. **One message** with the playback (instrument as understood, its family/variants as known so
   far, the derived identity) and **one AskUserQuestion** with two questions:
   - "Is the name and identity right?" (they can correct it here; it becomes permanent);
   - "The look: three concepts to pick from / leave it to me".
   The directory must be empty (apart from dotfiles the session itself creates); if not, stop
   and ask. **[call]**
3. Fixed defaults, not asked **[call]**: public repo `jiripisa/<slug>`, MIT, website with manual,
   EN + CS, Sparkle on, first release `1.0.0`, catalog entry. They match all three siblings.
4. Preflight (read-only, as `new-macos-app` §2): `gh` login and repo name free, `swift`,
   `xcrun actool`, Developer ID identity, `notary` profile, Sparkle public key
   (`generate_keys -p`), `codex --version`. A missing signing piece does not stop the sound
   work; it is reported and must be solved before the release step. A missing Codex switches
   the look to "native SwiftUI, no raster art" and is said in the intake message.

### Step 1 — Research (unattended)

Five parallel `general-purpose` subagents, briefs taken from Fanfrnoch §3 and kept as
reference files in the skill **[call]**:

| Topic | Must bring |
|---|---|
| Sound production (physics) | excitation, modes, damping, what sets pitch, loudness, timbre; numbers |
| Instrument types and construction | variants, registers, regional relatives (for programs) |
| Playing | how it is played: strokes or notes, articulations, ranges, polyphony, tempi |
| Measured recordings | CC0 / CC BY recordings, **measured by the subagent** with the skill's analysis tool: f0, harmonics, envelope, release, HNR, noise floor |
| Synthesis prior art | physical and cheap models, CPU cost, products, licences |

Every brief carries the product context (synthesized, AUv2 + app, real-time C++, a CPU budget
of tens to a few hundred ops per voice and sample), evidence labels on every claim, and the
download safety rules (empty scratch dir per download batch, scripts elsewhere, `python3 -I`,
files passed as arguments). A report-writer subagent then writes
`.planning/research/reports/<title>.md` in the siblings' form, ending with **"Recommendation for
the engine"** (model, starting numbers, cost), **the playing style** (see §6), and **"Questions
for the user's ear"**.

### Step 2 — Listening prototype (gate: the sound) **[user]**

- One throwaway C++17 file, `.planning/research/spike/<slug>_spike.cpp`, written by the main
  session from the report. The skill provides a **spike harness** (WAV writer, score helpers for
  notes, strokes, chords, held notes and phrases, a `Params` struct pattern, `--analyze`) so only
  the instrument is new. **[call]**
- Renders answer the report's questions one by one, then one render per planned program.
  Reference recordings beside them (`renders/references/`, gitignored, never committed).
  Long tails and quiet passages are included.
- **Measured before shown**: the analysis tool compares renders with the recordings, and the
  tail noise floor is checked (Brumle's hiss). The user is told plainly "measured, not heard".
- `LISTENING.md`: question → files → what to compare with, the decisive question first ("a
  real <instrument> or a synthesizer?"), a named fallback model if it fails.
- Open the folder for the user (`open <renders>`, Quick Look tips). Then wait.
- Not approved → change the spike, re-render, measure, send again. If the same aspect is
  rejected twice, stop tuning: ask for a reference the user likes or offer to drop it
  (Didgeridoo's overblown note).
- The approval message may also rename programs or correct the identity one last time.

### Step 3 — Autonomous build

After approval nothing waits for the user except, in the "three concepts" case, the pick of the
look (it does not block the engine).

1. **Spec** (`.planning/specs/<date>-instrument-design.md`) with Fanfrnoch's 11 sections and the
   decision markers; the user's delegation is stated at its top. Fixes the permanent identity,
   the parameter table and order, the playing style, programs, default kit, acceptance bar.
2. **Phase 01 — skeleton:** render the platform template (§7) into the current directory,
   `git init -b main`, `swift build`, `swift test` (debug and release) green on the placeholder
   engine before anything else changes.
3. **Phase 02 — engine** (background subagent, "read first (binding)" brief): the prototype
   becomes the test-only `<APP>Reference` target; engine equivalence < −60 dB on every spike
   score; debug = release; TSan; parameter-ID uniqueness test; regression references;
   `ListeningRenders`; aliasing and CPU measured; `auval`.
4. **Phase 03 — art (Codex), in parallel with 02:** concepts brief from the spec's controls.
   "Three concepts" → three concepts, the user picks. "Leave it to me" → two concepts, the main
   session picks and writes why. Then the assets prompt with exact sizes and alpha, no text baked
   in. Codex guards: `< /dev/null`, `--add-dir ~/.codex/generated_images`, "do not stop for
   questions", wait on `-o last-message.txt`, watch the log, kill leftover wrappers.
5. **Phase 04 — panel, app, AU, presets, kits, MIDI learn, manual EN + CS** (background
   subagent): layout in the core and tested; real-app screenshots by PID; scratch AU host; manual
   tag for tag in both languages.
6. **Phase 05 — icon (actool) and website** (subagent + Codex): our texts, Codex look,
   headless-Chrome review at 1440 and 400 px (Playwright viewport).
7. **Phase 06 — release, local part:** version 1.0.0, CHANGELOG, `./build.sh dist` (signed,
   notarized twice, stapled, appcast), `spctl`, `auval` on the distributed component, merge,
   tag. Then the catalog entry is written into `projects.json` in a local clone of
   `jiripisa/jiripisa.github.io` (a text edit, never a JSON rewrite). The `update-catalog`
   skill's build check and push need the public repo and Pages, so they run after publishing.
8. Each phase: branch, `PLAN.md`, `VERIFICATION.md` with "Not verified", `--no-ff` merge,
   `ROADMAP.md`/`STATE.md`. **The main session re-runs the tests itself before every merge.**
   The old-words grep is replaced by a check that no template placeholder or placeholder-engine
   word is left (`grep` list shipped with the skill).

### Step 4 — The push question (gate) **[user]**

One bold question naming every outward action: create `jiripisa/<slug>` (public), push the tag,
create the GitHub Release with the DMG, curl the DMG for 200, push `main`, turn on Pages, push
the catalog. After "yes", publish in that order and run the live checks (Pages run, both
language pages show the version, DMG and appcast downloaded, `sign_update --verify`, catalog
live).

### Step 5 — Report

Site URL, download URL, what was verified, what was not ("Not verified": real host, real MIDI
hardware, sound through a device, Safari/phone), the calls made, where the renders are.

## 6. Melodic and rhythmic instruments

All three siblings are rhythmic or drone instruments with 16 pads. A flute or an electric
guitar is played melodically. The platform supports both in one code base, not behind
build-time flags **[call]**:

- **Kept from the siblings for every instrument:** keyboard mode and 16-pad mode with groups,
  kits, Send to pad, presets, LFO and VEL amounts on knobs, MIDI CC per knob with learn.
- **A pad stays one frozen key press** (one note, one knob set, a group), exactly as in the
  siblings; the kit format, AU state and pad tests keep that model. No chord or strum pads in
  the platform **[call]**: adding them after a first release would break saved kits. A
  polyphonic instrument plays chords from the keyboard. An instrument that needs a strum or
  another multi-note gesture on one key does it inside its engine.
- **Velocity is a modulation source on pads exactly as on the keyboard** **[user]**: every pad's
  knob set carries its own VEL amounts, so on each pad the user chooses what velocity moves
  (a filter, the LFOs, the envelope, …), not only the loudness. The VEL targets are every
  continuous knob of the sound plus the LFOs' rates, as in Fanfrnoch **[call]**; a platform
  test checks that a pad hit applies its own set's VEL amounts.
- **Added once to the platform:** sustain pedal (CC 64) and a voice mode parameter: *Poly*,
  *Mono* (last-note priority), *Legato* (mono, no re-attack on overlapping notes) with *Glide*
  time. Fanfrnoch already has Bend Up/Down, mod wheel and aftertouch, but the mod wheel and
  aftertouch are wired to instrument knobs (Rub, Stick); the template untangles them into
  modulation sources the instrument's spec maps to its own knobs.
- **The spec of each instrument chooses** the defaults (a guitar: Poly, bend ±2; a flute:
  Legato with glide; a drum: as the siblings) and the programs. The research report states the
  playing style it recommends.

What a "voice" is and how a re-hit continues or chokes it stays instrument-specific, inside the
engine (Brumle chokes the reed; Fanfrnoch continues the drum's phase).

## 7. The platform template

Extracted from Fanfrnoch 1.0.0 (tag `v1.0.0`), the newest and cleanest sibling (actool icon,
in-PID screenshots, release skill), into `templates/` of the skill **[call]**:

- SwiftPM targets: `__APP__DSP` (C++ behind a C header), vendored `AudioUnitSDK`, `__APP__AU`,
  `__APP__AUView`, `__APP__AUExports`, `__APP__Core`, `__APP__UI`, `__APP__`, test-only
  `__APP__Reference`; `build.sh`, `run.sh`, `development_workflow.md`, `CLAUDE.md`, the project
  `release` skill, `.planning` skeleton, `docs/` (site, manual, CS), `Resources/` (Info.plists,
  entitlements, an `AppIcon.icon` document).
- **The instrument's parameters are individual to each instrument** **[user]**: the run's agent
  decides from the research and the approved prototype which knobs the instrument has (names,
  ranges, defaults, sections, which ones LFO and VEL may move) and fixes them in the spec. The
  template prescribes none of them; only the small platform block (volume, pan, tune, octave,
  bend, voice mode, glide, LFO rates/shapes, velocity sensitivity) is common, because presets,
  pads, MIDI learn and the AU depend on it.
- **The seam between platform and instrument** is the engine's parameter table, its sections,
  programs, default kit, and the `Voice` (strike/note-on, process, release). The template ships
  a **placeholder engine** (a simple decaying oscillator, a handful of parameters, two programs)
  so the skeleton builds, tests pass, the app runs and `auval` passes before phase 02.
- **Tests split** into platform tests that do not depend on the parameter table (MIDI, voice
  pool, pads, presets, kits, controllers, AU in-process, window model, thread tests) and
  instrument tests generated per run (equivalence, regression, layout).
- **Placeholders**: `{{VAR}}`, `{{#FLAG}}`, `__APP__` in paths, as `new-macos-app` uses. The
  C prefix (`fanfrnoch_`, `FANFRNOCH_`) becomes `{{APP_C}}_` / `{{APP_UPPER}}_`.
- **Rendering**: reuse `new-macos-app/scripts/scaffold.py` by adding a `--templates <dir>` option
  (default unchanged) and the extra variables (AU subtype, C prefix) **[call]**. This is a small,
  backward-compatible change to the other skill; if the user objects, the skill carries a copy.
- Art, panel layout (`SectionLayout`, `Artwork.swift`), manual body and website texts are
  instrument content: the template carries their structure with `FILL` markers.

## 8. Skill layout

Source in `~/Development/Claude/skills/audio-plugin/`, installed as
`~/.claude/skills/create-audio-plugin` → symlink to it **[call]**.

```
SKILL.md                    the run procedure (§5), short, pointing at references
references/
  research-briefs.md        the five briefs, evidence labels, safety rules, report form
  prototype.md              spike harness use, render naming, LISTENING.md, measuring
  spec-template.md          the 11 sections with markers
  phases.md                 phase briefs for subagents ("read first (binding)")
  codex.md                  invocation, guards, concept/asset/icon/site prompts
  verification-kit.md       Didgeridoo's harness kit, screenshot protocol, clean-up
  release.md                local release, the push question, publish order, live checks
  pitfalls.md               every "what went wrong" item as a guard
templates/                  the platform (§7)
scripts/
  spike_harness.h           WAV writer, score helpers, analysis entry
  analyze.swift             recording/render analysis (Swift + vDSP)
  capture_window.swift      window id by own PID → screencapture -l
  check_leftovers.sh        placeholder / old-word grep
```

## 9. How the skill itself is verified [builder details]

- Render the template for a dummy instrument into the scratchpad: `swift build`, `swift test`
  and `swift test -c release`, `./build.sh release`, `auval -v aumu <sub> JPis` (component
  installed only for the run, removed after), the app launched by path, its window captured by
  PID, then clean-up.
- `check_leftovers.sh` finds no `fanfrnoch`, `friction`, `drum`, … in the rendered output.
- The spike harness compiles and writes a WAV; `analyze.swift` reads it.
- `./build.sh dist` is not run during skill verification (it would notarize a dummy app).
- The first real run (e.g. the electric guitar) is the end-to-end test; the skill is corrected
  from what it finds.

## 10. Left to the builder

- Exactly which Fanfrnoch files are platform vs instrument, and how the tests are split.
- The placeholder engine's design, as long as it is small and passes `auval`.
- How the melodic additions (bend, sustain, voice modes, glide) are implemented in the voice
  pool and which parameters they add at the fixed start of every table.
- The analysis tool's feature set (start from Fanfrnoch §3's description and Brumle's
  `--analyze`).
- Wording and size of SKILL.md and the references (follow the `writing-skills` skill).
