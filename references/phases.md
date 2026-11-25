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

**The words file.** `<words>` is `<skill>/scripts/leftover-words.txt`: the template source's
identity (`fanfrnoch`, …) and the template's test render (`Zkusebnik`, `Zkušebník`). It holds no
instrument vocabulary, so a new instrument's own words (a drum, a skin, a stick) never trip it;
the source instrument's words and its siblings' are `<skill>/scripts/template-words.txt`, which
only `verify_template.sh` checks the template with, never a run. Should the new instrument's name
or words still be in `leftover-words.txt`, copy it to `.planning/leftover-words.txt`, delete only
those words with a comment saying why [call], and use that copy. The list cannot hold the
placeholder engine's words (the template and phase 01 are made of them); check those separately
after phase 02, with **the placeholder grep**, the same command wherever this skill names it:
`grep -rn 'kProgramTone\|"Soft Tone"\|placeholder instrument' Sources/<APP>DSP Tests/<APP>Reference docs`
→ nothing ("Soft Tone" stays as example text in platform comments and tests), and `FILL:` as its
phase and the release say.

**Outside the sandbox.** A window capture, an AX drive, the component's copy for `auval` or the
scratch AU host, `codex exec`, headless Chrome, and everything that reads the login Keychain or
signs (`security find-identity`, `notarytool`, `codesign`, `generate_keys -p`, `sign_update`,
`./build.sh dist`) run with the Bash sandbox disabled from the start (`dangerouslyDisableSandbox`
on that call; SKILL.md "Outside the sandbox"). Inside the sandbox they fail in ways that read as
something else. Only a refusal of that request is final: "Not verified".

**Captures are the main session's.** No subagent starts the real app, captures a window or
drives the app through AX. A subagent that needs pictures or a control seen hands back a
**capture list**, one line each: the picture's file (`docs/assets/manual/pads.png`), the state
it shows (mode, menu open, values set, the control highlighted), how to get there through AX
actions, and what must be visible. The main session takes them (`verification-kit.md`), looks
at each, and continues the subagent with the files. A capture that cannot be taken now (a
locked screen, a refusal) goes to the queue (`verification-kit.md` "Queued captures") and the
phase is merged with it named under "Not verified"; nothing is drawn in its place.

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
- Machine safety: you do not start the real app, capture windows or drive the app through AX:
  hand back a capture list (the picture's file, the state it shows, the AX actions that reach it,
  what must be visible) and the main session takes the pictures. Launch any helper by its full
  path, never by name and never with `open -a`. Never bring an app to the front, never send
  keystrokes or clicks through System Events. Never open an audio stream unless the default
  output's transport is Built-in (system_profiler SPAudioDataType); never change the default
  output. Copy the AU component to ~/Library/Audio/Plug-Ins/Components only for an auval run, and
  remove it right after. Never write to connected hardware.
- Outside the sandbox: the component's copy for auval and the auval run, headless Chrome, and
  anything that reads the login Keychain run with the Bash sandbox disabled from the start
  (dangerouslyDisableSandbox on that call). Only a refusal of that request is final.
- Clean up what you start or write outside <proj>: quit the processes, `defaults delete` the
  domains your runs created (the app's, stand-ins', helpers'), remove their plists, Application
  Support, Caches, Saved Application State and HTTPStorages entries; list them in VERIFICATION.md.
- A step refused (the request to disable the sandbox, or a permission): do not retry it in a
  loop, do not work around it, do not change any permission setting; record it under "Not
  verified" (the command and what it would have shown) and go on.
- Do not stop to ask questions. Record every choice you make in VERIFICATION.md with [builder].
- Hand back: what was done, every check with its result, what is not verified, the choices made.
```

## Phase 01 — skeleton (main session, about 10 minutes)

The config (`<scratch>/app.json`): the intake's `identity.py` JSON plus the fixed values. The
taglines never pass through the shell (one may hold an apostrophe): write each with the Write tool
into `<scratch>/tagline-en.txt` and `<scratch>/tagline-cs.txt`, one line, then

```
jq --arg a "$(git config user.name)" --rawfile en <scratch>/tagline-en.txt --rawfile cs <scratch>/tagline-cs.txt \
  '. + {AUTHOR: $a, TAGLINE: ($en | rtrimstr("\n")), TAGLINE_CS: ($cs | rtrimstr("\n")),
  LICENSE_KEY: "mit", LICENSE_LABEL: "MIT License", MIN_MACOS: "27.0",
  PUBLIC: true, WEBSITE: true, MANUAL: true, CS: true, SPARKLE: true, PLANNING: true}' \
  <scratch>/identity.json > <scratch>/app.json
```

Taglines: one sentence each, what the instrument is. Check them from the file:

```
jq -r '.TAGLINE, .TAGLINE_CS' <scratch>/app.json | grep -nE '["\\$`]|: '
```

must print nothing, and `jq -r .AUTHOR <scratch>/app.json` a name.

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
   structure reference for the concepts), quit, clean up. No picture (a locked screen, a
   refusal): the concepts are made without it; this one is not queued.
7. `git status` (no file under `.planning/research/spike/renders/`, and no spike binary: it was
   built into `<scratch>`, never beside the source), two commits:
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
"The instrument seam" (with "What the platform's tests assume": the test sound, kTestSound, and
a voice's random numbers) and "Stable IDs"; the spec .planning/specs/<file> §5-§9;
.planning/research/spike/<slug>_spike.cpp, spike_harness.h and LISTENING.md (the approved sound
and what played it); the report's "Recommendation for the engine" in
.planning/research/reports/<Title>.md; the template's placeholder instrument as the pattern:
Sources/<APP>DSP/Params.h, Voice.h, VoiceRandom.h, Tests/<APP>Reference/*,
Tests/<APP>CoreTests/{PrototypeScores,PrototypeEquivalenceTests,SoundRegressionTests,
ListeningRenders,Grooves,ReferenceTests,InstrumentTableTests}.swift.

<GLOBAL CONSTRAINTS>

THE BAR. The user approved the prototype's renders, not a description. The engine must reproduce
them: residual below -60 dB on every prototype score (aim far lower; the siblings reached
-114 to -149 dB).

TASKS (write PLAN.md first; test-first where a test can say it):
1. Tests/<APP>Reference: the spike's Params and Voice, and the spike folder's own
   spike_harness.h copied beside them unchanged (the copy the approved renders were played with;
   its play is the reference's renderer), behind a C interface, as the template's reference does
   for Tone. Every amendment the product needs (the parameters arriving with the render, a set
   per part or pad; events placed on whole host frames; the voices at the engine's rate with the
   decimator; coefficients independent of the rate) is marked in the file with a comment saying
   why. Nothing of the harness is re-written. Check outside the suite: a scratch program in
   <scratch> renders the spike's scores with the copy at the spike's rate; `cmp` against
   renders/*.wav (re-render the spike first); every file that differs is listed with the reason.
2. Sources/<APP>DSP/Params.h from spec §6-§8: InstrumentKnob, kInstrumentKnobs (identifiers,
   names, ranges, defaults, units, CCs exactly as the spec), kLfoTargets, kVelTargets (every
   continuous instrument knob plus volume, pan, tune, lfo1rate, lfo2rate), kModWheelTargets,
   kAftertouchTargets, kPlatformDefaults (the spec §7 playing style: each platform knob whose
   default the instrument changes, e.g. { kVoiceMode, kVoiceLegato }, { kGlide, 80.0f }; only
   { kNoTarget, 0 } when it plays as the platform does), kSections (at most 16 knobs each),
   kPrograms (kPrograms[0] with no overrides; at most 16 each), kDefaultKit (at most 4 overrides
   a pad, none of a kPlatformDefaults knob), kTestSound (spec §6: the instrument's own knobs
   turned so that the voice holds its pitch by itself and is over within 1.5 s of its note-off;
   the platform's tests play it), kRehitContinues, kOutputLevel, kTailSeconds. The static_asserts
   of ParamTable.h must hold.
3. Sources/<APP>DSP/Voice.h: the spike's voice, call for call (the harness's Voice has the
   engine's four: start(knobs, note, velocity, continuing), release(), render(out, frames),
   finished()), its Params read from knobs[...] instead; pitch from knobs.hz(note) (bend, glide);
   level free of velocity (the platform applies Vel Sens and VEL>Volume). Random numbers as the
   spike draws them, draw for draw: the voice's own std::mt19937, seeded with kVoiceSeed in
   every fresh start (continuing false) and never elsewhere, through uniform() and white() of
   VoiceRandom.h (the harness's, with the same constant). No other source of randomness: two
   equal notes render equal samples.
4. The instrument tests: PrototypeScores (every spike score, with its playing style, pedal and
   bend), PrototypeEquivalenceTests (< -60 dB at 96 kHz and through the decimator at 48 kHz),
   SoundRegressionTests (references taken from the new engine, in debug and release alike),
   Grooves, ReferenceTests, InstrumentTableTests (knobs, controllers, targets, wheels, sections,
   programs, kit, tail, the fullest gesture under the knee, the level of one note).
   ListeningRenders: the engine's versions of the spike's renders plus what the code cannot
   judge (the default kit groove, LFO and VEL on the main knobs, the wheels, bend, a re-hit,
   44.1 against 96 kHz), long tails included.
5. Measure and record: the level. kOutputLevel is set so that the fullest gesture of the spec's
   playing style (§8: a strum of every string or a full chord for a polyphonic instrument, one
   note for a mono one, the busiest bar of the default kit's groove for a rhythmic one), at
   full velocity and Volume at its default, peaks just under the knee of the output stage (0.6,
   -4.4 dBFS: above it the limiter bends the peaks), on every program; write the gesture and its
   peak, and the peak of one default note, into VERIFICATION.md, and into
   InstrumentTableTests.fullestGesture and .level. Level the programs against each other.
   Aliasing on the highest notes (the platform's 2x half-band stays; record alias products
   against -60 dB); CPU per voice and for 16 voices in release (% of one core); kTailSeconds
   against InstrumentTableTests.tail.
6. Listening renders measured: <APP_UPPER>_LISTEN_DIR=<proj>/.planning/research/spike/renders/engine
   swift test --filter ListeningRenders, then <scratch>/analyze <those files> --json (compile it
   from <skill>/scripts/analyze.swift), with the tail rules of prototype.md ("Measuring"): every
   tail falling, not flat, except a render that has reached digital silence (-200 dBFS, which
   cannot fall further) (`tail.centroidHz` for hiss or hum), windows computed from each file's
   `durationS` (`--tail` counts from the start); -80 dBFS or below (-200 passes) only where the
   voice is over, so render the prototype's `S…_silence_*` scores until the voice is over
   (`finished()`) and half a second more; stroke counts where the score is one note at a time;
   levels. Name in VERIFICATION.md every render that is "measured, not heard".
7. Any change to the approved sound found necessary (a flaw found by measurement) goes into the
   spike, the reference copy and the engine alike; the approved renders stay identical up to
   where the flaw starts; amend the spec with a date. List it as "measured, not heard".

CHECKS: swift build (0 warnings); swift test; swift test -c release; swift test --sanitize=thread
(the platform's tests stay untouched and green: if one fails, the instrument breaks what they
assume, usually its test sound; fix the instrument, never the test); ./build.sh release; auval,
with the sandbox disabled: copy build/release/<APP>.app/Contents/PlugIns/<APP>.component to
~/Library/Audio/Plug-Ins/Components/ (if one is there already, move it to <scratch> first and put
it back after), wait until `auval -a | grep "aumu <SUB> JPis"`, then `auval -v aumu <SUB> JPis`
must end with AU VALIDATION SUCCEEDED; remove the copy. `nm -gU` of the component's binary shows
only _<APP>AUFactory. The placeholder grep:
grep -rn 'kProgramTone\|"Soft Tone"\|placeholder instrument' Sources/<APP>DSP Tests/<APP>Reference docs
→ nothing.

REVIEW FOCUS for VERIFICATION.md: equivalence numbers per score; debug = release; the order of
the random draws; kTestSound against what the voice does by itself; the fullest gesture's peak;
every spec number the measurements moved.
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

## Phase 04 — panel, app, Audio Unit, presets, kits, MIDI learn, manual (background subagent; captures by the main session)

The subagent builds and tests; it sees the app only through tests and the hidden-window
harnesses. What needs the screen is the main session's: after the hand-back the main session
takes the capture list (below), drives the controls through AX, shows the plug-in's window in the
scratch AU host, and continues the subagent with the pictures for the marks.

```
PHASE 04 — PANEL, APP, AUDIO UNIT, MANUAL of <APP_NAME> in <proj> on branch feature/04-app-and-audiounit.

READ FIRST (binding): CLAUDE.md; development_workflow.md; <skill>/TEMPLATE_MANIFEST.md (files,
"Texts: FILL markers"); the spec §6, §7, §10; .planning/design/concepts/ (the approved mockups:
look at them), concepts.md (palette, materials, typography); .planning/design/assets/assets.md;
<skill>/references/verification-kit.md (binding: what you may run and what you hand over);
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
3. The manual, EN and CS: every FILL of docs/manual.html and docs/cs/manual.html, numbers from
   Params.h, every control described. Same tags in the same order:
   diff <(grep -o '<[/a-zA-Z][a-zA-Z0-9]*' docs/manual.html) <(grep -o '<[/a-zA-Z][a-zA-Z0-9]*' docs/cs/manual.html)
   prints nothing. The figures keep their placeholder marks until the pictures exist.
4. Damaged or later files: presets and kits with missing fields, unknown fields, out-of-range
   numbers and non-JSON load without a crash (the platform's tests hold; add any the instrument's
   values need).
5. THE CAPTURE LIST, in VERIFICATION.md and in your hand-back. You do not start the app. One
   line for each picture and each check the main session must make on the real app (release
   build):
   - the ten manual screenshots docs/assets/manual/<name>.png the pages link (each under 1 MB):
     the file, the state it shows (mode, which menu or popover is open, which knob values, which
     pad is selected), the AX actions that reach that state, what must be visible in it;
   - every control this phase made, seen once: both modes, LFO / VEL / MIDI modes, the Program,
     Preset and Kit menus, Save as, Send to pad, the pad inspector, MIDI learn; presets and kits
     saved and loaded;
   - the hit test: every control whose spot the art overlaps (the AX element at its position must
     be the control);
   - the plug-in's window in the scratch AU host: both modes, before and after a parameter change.
6. When the main session continues you with the pictures: measure the marks on the screenshots
   and write them into both manuals; check each picture against its line of the list. A picture
   that is missing stays in the list as "queued" (the main session takes it at the push
   question); never draw or render one in its place.

CHECKS: swift build (0 warnings); swift test; swift test -c release; swift test --sanitize=thread;
./build.sh release; auval as in phase 02; leftovers check.

REVIEW FOCUS: any new AU custom property or state shared between the host's thread and the window
(a lock or an atomic); hit-testing; the capture list (is every control of the phase on it).
```

The main session, after the hand-back (`verification-kit.md`; sandbox disabled for the captures,
the component's copy and the host):
1. The real app only when the capture rule allows; otherwise a stand-in (labelled as such) or the
   queue. Each line of the capture list: reach the state through AX actions on the own PID,
   capture by PID, look at the picture.
2. Hit-test every control (AX element at its position on the own PID): the art must not take
   it. After any hit-testing fix, test the whole control again, spot by spot, for what each spot
   does (a fix that lets clicks through lets them through to whatever lies there).
3. The plug-in's window in a scratch AU host (`verification-kit.md`): both modes, before and
   after a parameter change; the unit disposed only after its window closed.
4. Clean up (`verification-kit.md` "Clean-up"), list it in `VERIFICATION.md`, then continue the
   subagent (task 6) with the pictures in place.

Before merging, a fresh review subagent reviews the branch diff with the review focus above.

## Phase 05 — icon and website (background subagent; Codex jobs by the main session)

The main session starts the Codex icon job (`codex.md`) during phase 04, and the site job when
this subagent has handed back the texts and screenshots.

```
PHASE 05 — ICON AND WEBSITE of <APP_NAME> in <proj> on branch feature/05-icon-website.

READ FIRST (binding): CLAUDE.md; development_workflow.md §2.1.1 (the icon); the spec §10;
docs/index.html and docs/cs/index.html with their FILL comments; the finished manual;
CHANGELOG.md; <skill>/references/verification-kit.md (what you may run and what you hand over).

<GLOBAL CONSTRAINTS>

TASKS:
1. The icon: <scratch>/codex-icon/AppIcon.png (no Codex: <scratch>/icon/AppIcon.png, the main
   session's opaque full-bleed icon, codex.md "No Codex") → Resources/AppIcon.png; `sips -g pixelWidth
   -g pixelHeight -g hasAlpha` gives 1024, 1024, no. The fill colour in
   Resources/AppIcon.icon/icon.json may follow the art. ./build.sh release (actool). Render
   NSWorkspace.shared.icon(forFile:) of the built app, by its ABSOLUTE path, into a 256 px PNG:
   it fills the shape, no light tile. That PNG is docs/assets/icon.png. Prompt, notes and previews
   into .planning/design/icon/.
2. The website texts, EN and CS tag for tag: every FILL of docs/index.html and docs/cs/index.html,
   written by you from the manual, the CHANGELOG and the code, in the template's plain tone. Leave
   the version and download links as they are (the release replaces them).
3. docs/assets/<slug>-window.png is the main session's: put it on your capture list (the real
   release app's window in keyboard mode with the default sound, by PID; the main session takes
   it under the capture rule, else a stand-in picture, labelled in VERIFICATION.md, or the
   queue). No Codex: that capture is also the hero,
   `sips -s format jpeg docs/assets/<slug>-window.png --out docs/assets/hero-<slug>.jpg`, and the
   ornament's uses are replaced by a CSS rule, tag for tag in EN and CS (codex.md "No Codex").
4. Hand back after 1-3, with the capture list. The main session takes the capture, runs the
   Codex site job, then continues you to apply and review it.
5. Review: headless Chromium through Playwright (or the webapp-testing skill), with the sandbox
   disabled, at 1440 and 400 px, all four pages: `npx -y playwright@1.65.1 screenshot
   --viewport-size "400,900" --full-page file://<proj>/docs/index.html <scratch>/site/en-400.png`;
   the PNG is as wide as the viewport (no horizontal overflow); no failed image; contrast of
   text, links and the button checked; the manual's marks still on their controls; EN and CS tag
   for tag (the diff above for both pages). The run never installs a browser: when Playwright has
   no Chromium (or the request to run it outside the sandbox is refused), the site review is
   "Not verified" (say which checks), and the tag-for-tag diff is still run.
6. `grep -rn "FILL:" docs .planning/ROADMAP.md .planning/STATE.md` → nothing in docs; in
   ROADMAP.md only phase 05's own row, which the main session fills at the merge.
   `scripts/check_site_links.sh` → `site links ok`, or only pictures that are on the queue (name
   them in VERIFICATION.md under "Not verified").

CHECKS: swift build (0 warnings); swift test; ./build.sh release; leftovers check; clean-up.
```
