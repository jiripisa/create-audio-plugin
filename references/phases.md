# Phases (step 3)

Names: `<skill>`, `<scratch>`, `<proj>`, and the identity's `<APP>`, `<APP_NAME>`, `<slug>`,
`<SUB>`, `<APP_UPPER>`, `<BUNDLE_ID>`. Phase folders and branches as the template's
`.planning/ROADMAP.md` names them: `01-skeleton`, `02-engine`, `03-panel-design`,
`04-app-and-audiounit`, `05-icon-website`, `06-v1.0.0-release` (`release.md`).

## Every phase

1. `git switch -c feature/NN-slug` from an up-to-date `main` (phase 01 works on `main`).
2. `.planning/phases/NN-slug/PLAN.md` first: goal, tasks, checks, what is out of scope.
3. The work; each [builder] choice written down as it is made.
4. `.planning/phases/NN-slug/VERIFICATION.md`: every check with its real output (test counts,
   residuals, `auval` result, image paths), every choice made (marker, one line each), the
   harnesses used (`verification-kit.md`) and a closing **"Not verified"** section.
5. Before the merge, the main session itself (a subagent's report is not evidence):
   - `swift build 2>&1 | tee <scratch>/build.log | grep -c 'warning:'` → `0`;
   - `swift test > <scratch>/test.log 2>&1` and `swift test -c release > <scratch>/test-release.log 2>&1`,
     then `grep -E 'Test run with [0-9]+ tests' <scratch>/test*.log` (both pass, same count);
     phase 02 and 04 also `swift test --sanitize=thread`;
   - `<skill>/scripts/check_leftovers.sh --skip-dir .planning <proj> <words>` → `no leftovers`
     (`<words>`: below);
   - the clean-up check of `verification-kit.md`;
   - `git status`: only what was checked is in the commit.
6. `git switch main && git merge --no-ff feature/NN-slug -m "feat: merge NN-slug — <what>"`,
   delete the branch, update `ROADMAP.md` (✅, " — <date>", what was made, its FILL) and
   `STATE.md` (an entry, newest first). Commits never carry AI attribution trailers.

A subagent that reports "could not run the tests" (Docker, network, a tool) has not passed: the
main session fixes the environment and runs them before the phase goes on.

**The words file.** `<words>` is `<skill>/scripts/leftover-words.txt`, unless the new
instrument's own vocabulary is in it (a drum would hit `drum`, `skin`, `stick`): then copy it to
`.planning/leftover-words.txt`, delete only the instrument's own words with a comment saying why
[call], and use that copy. The list does not hold the placeholder engine's words; check those
separately after phase 02: `grep -rn 'kProgramTone\|"Soft Tone"\|placeholder instrument' Sources/<APP>DSP Tests/<APP>Reference docs`
→ nothing ("Soft Tone" stays as example text in platform comments and tests).

## Global constraints (paste into every subagent brief)

```
GLOBAL CONSTRAINTS (binding).
- Work on branch feature/<NN-slug> in <proj>. Never push, never create a remote or a GitHub repo.
  `git status` before every commit; commit messages in Conventional Commits, no AI attribution
  trailers (no Co-Authored-By, no session links).
- SwiftPM + build.sh, never an Xcode project. macOS 27. Zero build warnings.
- Engine code under `#pragma clang fp contract(off)`, `std::exp2` for powers of two. Nothing on the
  audio thread allocates, locks, logs or does I/O.
- The suite must pass in `swift test` AND `swift test -c release`; TSan
  (`swift test --sanitize=thread`) where the phase touches threads. Redirect test output to a file
  and read the summary line. If a test run cannot be executed, say exactly why; that is not a pass.
- Vendored code (ThirdParty/AudioUnitSDK) is never edited: a fix goes in front of it.
- The platform tests stay as they are and stay green. A run changes only the instrument's files
  (TEMPLATE_MANIFEST.md); anything else is named in VERIFICATION.md with why.
- Parameter identifiers and their order are the spec's §6 and are permanent; the AU's codes are
  the spec's §3.
- Measure, then decide: a number in the plan or the spec that measurement shows wrong is changed,
  and the deviation is written in VERIFICATION.md with the measurement.
- Machine safety: launch the app or any helper by its full path, never by name and never with
  `open -a`. Capture only one window of a process you started:
  `<skill>/scripts/capture_window.swift <pid> <out.png>` (never screencapture without -l). Never
  bring an app to the front, never send keystrokes or clicks through System Events; drive only
  through AX actions on your own PID. Never open an audio stream unless the default output's
  transport is Built-in (system_profiler SPAudioDataType); never change the default output.
  Copy the AU component to ~/Library/Audio/Plug-Ins/Components only for an auval run and remove
  it right after. Never write to connected hardware.
- Clean up what you start or write outside <proj>: quit the processes, `defaults delete` the
  domains your runs created (the app's, stand-ins', helpers'), remove their plists, Application
  Support, Caches, Saved Application State and HTTPStorages entries; list them in VERIFICATION.md.
- A step refused by the sandbox or a permission: do not retry it in a loop, do not change any
  permission setting; record it under "Not verified" (the command and what it would have shown)
  and go on.
- Do not stop to ask questions. Record every choice you make in VERIFICATION.md with [builder].
- Hand back: what was done, every check with its result, what is not verified, the choices made.
```

## Phase 01 — skeleton (main session, about 10 minutes)

The config (`<scratch>/app.json`): the intake's `identity.py` JSON plus

```
jq --arg a "$(git config user.name)" '. + {AUTHOR: $a, TAGLINE: "<EN>", TAGLINE_CS: "<CS>",
  LICENSE_KEY: "mit", LICENSE_LABEL: "MIT License", MIN_MACOS: "27.0",
  PUBLIC: true, WEBSITE: true, MANUAL: true, CS: true, SPARKLE: true, PLANNING: true}' \
  <scratch>/identity.json > <scratch>/app.json
```

Taglines: one sentence each, what the instrument is; `printf '%s\n' "<EN>" "<CS>" | grep -nE '["\\$`]|: '`
must print nothing.

1. Render into the scratchpad (scaffold refuses a non-empty target, and `<proj>` already holds
   `.planning/research` and `.planning/specs`):
   `python3 -I ~/.claude/skills/new-macos-app/scripts/scaffold.py --config <scratch>/app.json --out <scratch>/render/<APP> --templates <skill>/templates`
2. No collision: `(cd <scratch>/render/<APP> && find . -type f) | while read -r f; do [ -e "<proj>/$f" ] && echo "$f"; done`
   prints nothing; then `rsync -a <scratch>/render/<APP>/ <proj>/`.
3. `grep -rIn -E '\{\{[#^/]?[A-Z_]+\}\}|__APP__' <proj> --exclude-dir=.planning` → nothing;
   leftovers check as above.
4. `git init -b main`; `swift build` (fetches Sparkle; zero warnings); the Sparkle key:
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` equals
   `/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info.plist`. A mismatch or no key
   does not stop the sound work; it must be solved before phase 06 (ask the user then, never
   run `generate_keys` without `-p`).
5. `swift test`, `swift test -c release` (logs, summary lines), `./build.sh release`.
6. If the capture rule allows (`verification-kit.md`): launch `build/release/<APP>.app` by path,
   capture its window by PID to `<scratch>/codex-concepts/reference/skeleton-keyboard.png` (the
   structure reference for the concepts), quit, clean up.
7. `git status` (no file under `.planning/research/spike/renders/`), two commits:
   `feat: skeleton from the create-audio-plugin template` (everything rendered) and
   `docs: research, listening prototype and instrument design` (`.planning/research`, the spec).
8. `ROADMAP.md`: phase 01 ✅ with the date; the research and spec file names (their FILL).
   `STATE.md`: phase 01 entry rewritten with the test count; the research entry's FILL (dates,
   file names, the approval date).

Phase 02 (subagent) and the Codex jobs of phase 03 (main session, `codex.md`) then run at the
same time. Codex works only in `<scratch>/codex-*`; nothing touches `<proj>` while the phase 02
subagent works there.

## Phase 02 — engine (background subagent)

```
PHASE 02 — ENGINE of <APP_NAME>, a synthesized <instrument>, in <proj> on branch feature/02-engine.

READ FIRST (binding): CLAUDE.md; development_workflow.md; <skill>/TEMPLATE_MANIFEST.md, all of
"The instrument seam" and "Stable IDs"; the spec .planning/specs/<file> §5-§9;
.planning/research/spike/<slug>_spike.cpp and LISTENING.md (the approved sound); the report's
"Recommendation for the engine" in .planning/research/reports/<Title>.md; the template's
placeholder instrument as the pattern: Sources/<APP>DSP/Params.h, Voice.h,
Tests/<APP>Reference/*, Tests/<APP>CoreTests/{PrototypeScores,PrototypeEquivalenceTests,
SoundRegressionTests,ListeningRenders,Grooves,ReferenceTests,InstrumentTableTests}.swift.

<GLOBAL CONSTRAINTS>

THE BAR. The user approved the prototype's renders, not a description. The engine must reproduce
them: residual below -60 dB on every prototype score (aim far lower; the siblings reached
-114 to -149 dB).

TASKS (write PLAN.md first; test-first where a test can say it):
1. Tests/<APP>Reference: the spike's Params and Voice copied behind a C interface (the pattern of
   the template's reference). Every amendment the product needs (rate as a variable, coefficients
   independent of the rate, a parameter set per event, the decimator) is marked in the file with
   a comment saying why. Check outside the suite: a scratch program in <scratch> renders the
   spike's scores with the copy at the spike's rate; `cmp` against renders/*.wav (re-render the
   spike first); every file that differs is listed with the reason.
2. Sources/<APP>DSP/Params.h from spec §6-§8: InstrumentKnob, kInstrumentKnobs (identifiers,
   names, ranges, defaults, units, CCs exactly as the spec), kLfoTargets, kVelTargets (every
   continuous instrument knob plus volume, pan, tune, lfo1rate, lfo2rate), kModWheelTargets,
   kAftertouchTargets, kSections, kPrograms (kPrograms[0] with no overrides), kDefaultKit,
   kRehitContinues, kOutputLevel, kTailSeconds. The static_asserts of ParamTable.h must hold.
3. Sources/<APP>DSP/Voice.h: the spike's voice behind start(knobs, note, velocity, continuing),
   release(), render(out, frames), finished(); pitch from knobs.hz(note) (bend, glide); level
   free of velocity (the platform applies Vel Sens and VEL>Volume); random generators ported draw
   for draw (same std::mt19937 seeds and order, the harness's uniform()/white()).
4. The instrument tests: PrototypeScores (every spike score), PrototypeEquivalenceTests
   (< -60 dB at 96 kHz and through the decimator at 48 kHz), SoundRegressionTests (references
   taken from the new engine, in debug and release alike), Grooves, ReferenceTests,
   InstrumentTableTests (knobs, controllers, targets, wheels, sections, programs, kit, tail,
   level). ListeningRenders: the engine's versions of the spike's renders plus what the code
   cannot judge (the default kit groove, LFO and VEL on the main knobs, the wheels, bend, a
   re-hit, 44.1 against 96 kHz), long tails included.
5. Measure and record: the default note at full velocity peaks near -6 dBFS (calibrate
   kOutputLevel; level the programs); aliasing on the highest notes (the platform's 2x half-band
   stays; record alias products against -60 dB); CPU per voice and for 16 voices in release (% of
   one core); kTailSeconds against InstrumentTableTests.tail.
6. Listening renders measured: <APP_UPPER>_LISTEN_DIR=<proj>/.planning/research/spike/renders/engine
   swift test --filter ListeningRenders, then <scratch>/analyze <those files> --json (compile it
   from <skill>/scripts/analyze.swift): tail floors at or below -80 dBFS and falling, stroke
   counts, levels. Name in VERIFICATION.md every render that is "measured, not heard".
7. Any change to the approved sound found necessary (a flaw found by measurement) goes into the
   spike, the reference copy and the engine alike; the approved renders stay identical up to
   where the flaw starts; amend the spec with a date. List it as "measured, not heard".

CHECKS: swift build (0 warnings); swift test; swift test -c release; swift test --sanitize=thread;
./build.sh release; auval: copy build/release/<APP>.app/Contents/PlugIns/<APP>.component to
~/Library/Audio/Plug-Ins/Components/ (if one is there already, move it to <scratch> first and put
it back after), wait until `auval -a | grep "aumu <SUB> JPis"`, then `auval -v aumu <SUB> JPis`
must end with AU VALIDATION SUCCEEDED; remove the copy. `nm -gU` of the component's binary shows
only _<APP>AUFactory. The placeholder grep: grep -rn 'kProgramTone\|"Soft Tone"' Sources/<APP>DSP
Tests/<APP>Reference → nothing.

REVIEW FOCUS for VERIFICATION.md: equivalence numbers per score; debug = release; generator
order; every spec number the measurements moved.
```

Before merging, a fresh review subagent reads the branch diff against spec §5-§8 (correctness of
the port, audio-thread rules, the seam's contract); the main session checks each finding against
the code before fixing it.

## Phase 03 — panel art (main session)

Codex jobs as in `codex.md`, started right after phase 01. After phase 02 is merged, on
`feature/03-panel-design`: the five assets into `Resources/Art/` (`background.png`, `figure.png`,
`logo.png`, `knob.png`, `ornament.png`); briefs, prompts, `concepts.md`, the mockups, the choice
and its reasons, `assets.md` and the composite into `.planning/design/{concepts,assets}/`. No
Codex: the native look (`codex.md`), no `Resources/Art/`. Checks: sizes and alpha with
`sips -g pixelWidth -g pixelHeight -g hasAlpha`; `./build.sh release` copies `Art/` into the app
and the component.

## Phase 04 — panel, app, Audio Unit, presets, kits, MIDI learn, manual (background subagent)

```
PHASE 04 — PANEL, APP, AUDIO UNIT, MANUAL of <APP_NAME> in <proj> on branch feature/04-app-and-audiounit.

READ FIRST (binding): CLAUDE.md; development_workflow.md; <skill>/TEMPLATE_MANIFEST.md (files,
"Texts: FILL markers"); the spec §6, §7, §10; .planning/design/concepts/ (the approved mockups:
look at them), concepts.md (palette, materials, typography); .planning/design/assets/assets.md;
<skill>/references/verification-kit.md (binding: how to see the app without disturbing the Mac);
Sources/<APP>Core/SectionLayout.swift, Sources/<APP>UI/Artwork.swift; docs/manual.html and
docs/cs/manual.html with their FILL comments.

<GLOBAL CONSTRAINTS>

TASKS (PLAN.md first):
1. Artwork.swift: the approved palette (hex from concepts.md); figureBounds and logoBounds = the
   images' alpha bounds (measured, not guessed); LFO 1, LFO 2 and VEL colours that read on the
   ground and differ from the value arc's accent. Decorative art never takes a click
   (allowsHitTesting(false)). No Codex art: system colours stay, the panel must still look
   intentional.
2. SectionLayout.plans and PanelLayout.plannedRows from the mockup, test-first (every parameter
   laid out exactly once). The window fits a 1440 x 900 screen; its size measured from the content.
3. The real app (release build, launched by path, only when the capture rule allows; otherwise a
   stand-in per verification-kit.md, labelled as such): both modes, LFO/VEL/MIDI modes, the
   Program, Preset and Kit menus, Save as, Send to pad, the pad inspector, MIDI learn; presets and
   kits saved and loaded through AX actions on your own PID. Every control the phase made is seen
   in a capture before the merge. Hit-test every control (AX element at its position on your
   PID): the art must not take it. After any hit-testing fix, test the whole control again, spot
   by spot, for what each spot does (a fix that lets clicks through lets them through to whatever
   lies there).
4. The plug-in's window in a scratch AU host (verification-kit.md): both modes, before and after
   a parameter change; the unit disposed only after its window closed.
5. The manual, EN and CS: every FILL of docs/manual.html and docs/cs/manual.html, numbers from
   Params.h, every control described; screenshots of the real app into docs/assets/manual/ (the
   ten names the pages link, each under 1 MB); the marks measured on the screenshots. Same tags in
   the same order:
   diff <(grep -o '<[/a-zA-Z][a-zA-Z0-9]*' docs/manual.html) <(grep -o '<[/a-zA-Z][a-zA-Z0-9]*' docs/cs/manual.html)
   prints nothing.
6. Damaged or later files: presets and kits with missing fields, unknown fields, out-of-range
   numbers and non-JSON load without a crash (the platform's tests hold; add any the instrument's
   values need).

CHECKS: swift build (0 warnings); swift test; swift test -c release; swift test --sanitize=thread;
./build.sh release; auval as in phase 02; the clean-up list of verification-kit.md done and
listed; leftovers check.

REVIEW FOCUS: any new AU custom property or state shared between the host's thread and the window
(a lock or an atomic); hit-testing; the stand-ins' LC_BUILD_VERSION; which picture is real.
```

Before merging, a fresh review subagent reviews the branch diff with the review focus above.

## Phase 05 — icon and website (background subagent; Codex jobs by the main session)

The main session starts the Codex icon job (`codex.md`) during phase 04, and the site job when
this subagent has handed back the texts and screenshots.

```
PHASE 05 — ICON AND WEBSITE of <APP_NAME> in <proj> on branch feature/05-icon-website.

READ FIRST (binding): CLAUDE.md; development_workflow.md §2.1.1 (the icon); the spec §10;
docs/index.html and docs/cs/index.html with their FILL comments; the finished manual;
CHANGELOG.md; <skill>/references/verification-kit.md.

<GLOBAL CONSTRAINTS>

TASKS:
1. The icon: <scratch>/codex-icon/AppIcon.png → Resources/AppIcon.png; `sips -g pixelWidth
   -g pixelHeight -g hasAlpha` gives 1024, 1024, no. The fill colour in
   Resources/AppIcon.icon/icon.json may follow the art. ./build.sh release (actool). Render
   NSWorkspace.shared.icon(forFile:) of the built app, by its ABSOLUTE path, into a 256 px PNG:
   it fills the shape, no light tile. That PNG is docs/assets/icon.png. Prompt, notes and previews
   into .planning/design/icon/.
2. The website texts, EN and CS tag for tag: every FILL of docs/index.html and docs/cs/index.html,
   written by you from the manual, the CHANGELOG and the code, in the template's plain tone. Leave
   the version and download links as they are (the release replaces them).
3. docs/assets/<slug>-window.png: a capture of the real release app by PID (capture rule), else a
   stand-in picture, labelled in VERIFICATION.md.
4. Hand back after 1-3. The main session runs the Codex site job, then continues you to apply and
   review it.
5. Review: headless Chromium through Playwright (or the webapp-testing skill) at 1440 and 400 px,
   all four pages: `npx -y playwright@1.65.1 screenshot --viewport-size "400,900" --full-page
   file://<proj>/docs/index.html <scratch>/site/en-400.png`; the PNG is as wide as the viewport
   (no horizontal overflow); no failed image; contrast of text, links and the button checked; the
   manual's marks still on their controls; EN and CS tag for tag (the diff above for both pages).
6. `grep -rn "FILL:" docs .planning/ROADMAP.md .planning/STATE.md` → nothing in docs; in
   ROADMAP.md only phase 05's own row, which the main session fills at the merge.

CHECKS: swift build (0 warnings); swift test; ./build.sh release; leftovers check; clean-up.
```
