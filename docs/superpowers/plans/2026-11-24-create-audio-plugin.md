# create-audio-plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code skill `create-audio-plugin` that, run in an empty directory named after the
product, researches a real instrument, gets the user's approval of a listening prototype, and then
autonomously builds and prepares the release of a synthesized AUv2 instrument plus macOS 27 app
with a GitHub Pages download site — publishing only after one final "yes".

**Architecture:** The skill is a procedure (`SKILL.md` + `references/`) over a **platform template**
(`templates/`) extracted once from Fanfrnoch 1.0.0, neutralised, moved to macOS 27, extended with
melodic playing, and given a placeholder engine. The template is rendered by
`new-macos-app/scripts/scaffold.py` (extended with `--templates`). Small helper scripts (identity,
spike harness, analysis, window capture, leftover check, template verification) live in `scripts/`.

**Tech Stack:** Swift 6.4 / SwiftPM, C++23 (engine), AudioUnitSDK (AUv2), SwiftUI on the macOS 27.2
SDK, Sparkle 2, Python 3 (scaffold, identity; stdlib only), Swift + Accelerate (analysis), bash.

**Spec:** `docs/superpowers/specs/2026-11-24-create-audio-plugin-design.md` (read it first; §5 is the
run, §6 melodic/rhythmic, §7 the template, §8 the layout).

## Global Constraints

- Skill source: `~/Development/Claude/skills/audio-plugin/`; installed as the symlink
  `~/.claude/skills/create-audio-plugin` → that directory. Frontmatter `name: create-audio-plugin`.
- All skill files, code, comments and commit messages in English. No AI attribution trailers.
- Template origin: Fanfrnoch tag `v1.0.0` (`git -C ~/Development/Claude/Fanfrnoch archive v1.0.0`),
  never the working tree. Fanfrnoch itself is never modified.
- Platform: `.macOS(.v27)`, `swift-tools-version: 6.4`, `LSMinimumSystemVersion` 27.0, Apple silicon
  only, newest Sparkle 2.x, newest SwiftUI / Liquid Glass APIs of the 27.2 SDK where they replace a
  macOS 26 API Fanfrnoch uses. Build must have **zero warnings**.
- SwiftPM + `build.sh` only; never an Xcode project.
- AU identity: type `aumu`, manufacturer `JPis`, subtype `{{AU_SUBTYPE}}`, bundle id
  `io.jp4.{{APP_LOWER}}` (+ `.audiounit`), factory `{{APP}}AUFactory`, view `{{APP}}AUViewFactory`.
- Engine determinism: `#pragma clang fp contract(off)` in every engine `.cpp`; `exp2` not `pow(2,x)`;
  suite green in both `swift test` and `swift test -c release`, plus `--sanitize=thread`.
- Nothing on the audio thread allocates, locks, logs or does I/O.
- A pad is one frozen key press (one note, one knob set, one group). Every set — keyboard and each
  pad — carries its own VEL amounts; VEL targets = every continuous knob + both LFO rates.
- Machine safety in every task that runs the app: launch by path, capture only `-l <window id>` of
  the launched PID (`scripts/capture_window.swift`), no keystrokes, no activation, never open a
  stream on the user's audio device, `defaults delete <bundle id>` and remove helper plists after.
  The AU component is copied to `~/Library/Audio/Plug-Ins/Components/` only for an `auval` run and
  removed right after.
- Runs in auto mode; no permission settings are changed. A refused sandboxed step is recorded and
  skipped, never retried in a loop.
- `new-macos-app` is not in git: back it up to the scratchpad before modifying it.

## Review Focus

1. **Directory names with diacritics, spaces or digits** (`Strunobijec`, `Čimbál`, `Tape Loop 2`):
   `APP_NAME` keeps them, `APP`/slug/C prefix/AU subtype are ASCII and valid → tests in Task 2.
2. **AU subtype colliding** with an installed or sibling component (`Brml`, `Fanf`, `Didg`, Apple's)
   → the identity script picks the next free code, test in Task 2.
3. **Mono/Legato with sustain and overlapping keys**: releasing the newest held key returns to the
   previous held one; sustain holds a released mono note until pedal up → tests in Task 6.
4. **Saved state from before/after a voice-mode change**: switching Poly→Mono while notes sound
   must not leave a hung voice; AU state round-trips the new parameters → tests in Task 6.
5. **A rendered project with no art** (Codex missing): the panel must build and look intentional
   with native SwiftUI only → check in Task 7.

---

### Task 1: Skill repo and scaffold.py `--templates`

**Files:**
- Create: `.gitignore` (`.DS_Store`, `__pycache__/`), `README.md` (one paragraph + install line)
- Modify: `~/.claude/skills/new-macos-app/scripts/scaffold.py` (argparse, `main`, `load_config`)
- Test: `tests/test_scaffold_templates.py`

**Interfaces:**
- Produces: `scaffold.py --config C --out O [--templates DIR]`; with `--templates`, also accepts
  config keys `AU_SUBTYPE`, `APP_C`, `APP_UPPER`, `APP_NAME_CS` (any extra string keys pass through
  as variables). `FILE_FLAGS` apply only to the built-in templates.

- [ ] **Step 1:** `git init -b main`; back up `new-macos-app` to `<scratchpad>/new-macos-app.bak`;
  render the built-in templates once with a fixed config into `<scratchpad>/before/`.
- [ ] **Step 2: Failing tests** (`unittest`, stdlib):
  - `test_custom_templates_dir`: a temp template dir with `__APP__/x.txt` = `{{APP}}-{{AU_SUBTYPE}}`
    renders to `Foo/x.txt` = `Foo-Fooo`.
  - `test_default_unchanged`: rendering the built-in templates into `after/` equals `before/`
    byte for byte (`filecmp.dircmp`, recursive).
  - `test_binary_files_copied`: a `.png` in the template dir is copied unchanged, not decoded.
- [ ] **Step 3:** Run `python3 -m unittest tests/test_scaffold_templates.py` → FAIL.
- [ ] **Step 4:** Implement: `--templates` (default `TEMPLATES`); binary files (`.png .jpg .car
  .icns` and anything failing UTF-8 decode) copied with `shutil.copyfile`; extra config keys are
  variables.
- [ ] **Step 5:** Tests PASS; commit spec, plan, tests, README (`chore: skill repo, scaffold --templates`).

### Task 2: Identity derivation

**Files:**
- Create: `scripts/identity.py`
- Test: `tests/test_identity.py`

**Interfaces:**
- Produces: `python3 scripts/identity.py <dir-path> [--taken Brml,Fanf]` → JSON on stdout with
  `APP_NAME, APP, APP_LOWER, APP_C, APP_UPPER, BUNDLE_ID, AU_SUBTYPE, OWNER` (OWNER from
  `gh api user --jq .login`, overridable with `--owner` for tests). Exit 2 with a message when the
  name has no ASCII letter left.

- [ ] **Step 1: Failing tests:**
  - `Strunobijec` → APP `Strunobijec`, APP_LOWER `strunobijec`, APP_C `strunobijec`, APP_UPPER
    `STRUNOBIJEC`, BUNDLE_ID `io.jp4.strunobijec`, AU_SUBTYPE `Stru`.
  - `Čimbál` → APP_NAME `Čimbál`, APP `Cimbal`, AU_SUBTYPE `Cimb`.
  - `Tape Loop 2` → APP `TapeLoop2`, APP_LOWER `tapeloop2`, APP_C `tapeloop2`.
  - `Ab` → AU_SUBTYPE padded to 4 chars from the name (`Abab`), always 4 ASCII alnum, first upper.
  - `--taken Stru` for `Strunobijec` → `Strn` (next candidate: first letter + next consonants), and
    never one of the built-in taken list `Brml, Fanf, Didg`.
  - `123` → exit 2.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (`unicodedata.normalize('NFKD')`, strip
  combining marks; taken set = `--taken` ∪ built-ins ∪ subtypes found by `auval -a` when not
  `--no-auval`). **Step 4:** PASS. **Step 5:** Commit `feat: identity from the directory name`.

### Task 3: Import and neutralise the template

Goal: `templates/` = Fanfrnoch v1.0.0 with every identity token replaced, still the friction-drum
engine, and it renders and builds. This isolates the rename from later changes.

**Files:**
- Create: `templates/**` (from `git archive v1.0.0`), `scripts/check_leftovers.sh`,
  `scripts/verify_template.sh`, `TEMPLATE_MANIFEST.md`
- Test: `scripts/verify_template.sh` itself (it is the test)

**Interfaces:**
- Produces: `scripts/verify_template.sh [--quick] [--auval] [--capture]` — renders `templates/` with
  a dummy config (`APP_NAME` `Zkusebnik`, subtype `Zkus`) into `<scratch>/verify-<ts>/`, then runs
  `swift build`; without `--quick` also `swift test`, `swift test -c release`, `./build.sh release`;
  `--auval` installs, runs `auval -v aumu Zkus JPis`, uninstalls; `--capture` launches by path and
  captures by PID (Task 8's script). Prints `TEMPLATE OK` last on success. Cleans up prefs.
- Produces: `scripts/check_leftovers.sh <dir> [words-file]` → lists matches, exit 1 if any.
  Default words: `fanfrnoch Fanfrnoch FANFRNOCH Fanf Brumle brumle Didgeridoo` plus (after Task 4)
  the placeholder engine's own words and `FILL`.
- Produces: `TEMPLATE_MANIFEST.md` — every template file classified **platform** (kept as is per
  run) or **instrument** (replaced per run: `Params.h/.cpp`, `Voice.h`, `SectionLayout.plans`,
  `Artwork.swift`, `Resources/Art/*`, `Tests/__APP__Reference/*`, `PrototypeScores.swift`,
  `SoundRegressionTests.swift`, `PrototypeEquivalenceTests.swift`, `ListeningRenders.swift`,
  manual/site bodies), with one line each on what a run puts there.

- [ ] **Step 1:** Archive into scratch; copy everything except `.planning/`, `Resources/Art/`,
  `Resources/AppIcon.png`, `docs/assets/*.png|*.jpg`, `docs/assets/manual/`, `docs/appcast.xml`
  entries, `LICENSE` (scaffold makes it).
- [ ] **Step 2:** Rename paths deepest-first `Fanfrnoch`→`__APP__`; text with `LC_ALL=C sed`:
  `Fanfrnoch`→`{{APP}}`, `FANFRNOCH`→`{{APP_UPPER}}`, `fanfrnoch_`→`{{APP_C}}_`,
  `fanfrnoch`→`{{APP_LOWER}}`, `'Fanf'`/`Fanf` subtype and its hex test constant →
  `{{AU_SUBTYPE}}` (hex computed in Swift from the string, not hardcoded), version → `0.1.0`,
  CHANGELOG reset to `## Unreleased`, appcast emptied. Keep the shared `SUPublicEDKey`.
- [ ] **Step 3:** `check_leftovers.sh templates` → only friction-drum *content* words remain (they
  go in Task 4); no identity tokens.
- [ ] **Step 4:** `scripts/verify_template.sh` → `TEMPLATE OK` (inherited 275 tests green).
- [ ] **Step 5:** Commit `feat(template): Fanfrnoch 1.0.0 neutralised`.

### Task 4: macOS 27 and newest libraries

**Files:**
- Modify: `templates/Package.swift`, `templates/Resources/Info.plist`,
  `templates/Resources/AudioUnit-Info.plist`, `templates/build.sh`, Swift sources flagged by the
  compiler or by the SDK review below, `templates/CLAUDE.md`, `templates/development_workflow.md`

- [ ] **Step 1:** Set `.macOS(.v27)`, tools `6.4`, `LSMinimumSystemVersion` `27.0`, build.sh's
  deployment target; Sparkle `from:` the newest 2.x release (`gh api repos/sparkle-project/Sparkle/releases/latest`).
- [ ] **Step 2:** `verify_template.sh --quick` and collect every warning (deprecations included).
- [ ] **Step 3:** For each SwiftUI / AppKit / Liquid Glass API the template uses, check the 27.2 SDK
  swiftinterface (`$(xcrun --show-sdk-path)/System/Library/Frameworks/SwiftUI.framework/Modules/`)
  for a newer replacement; adopt it. List each replacement in `TEMPLATE_MANIFEST.md` §"macOS 27".
- [ ] **Step 4:** `verify_template.sh --capture` → `TEMPLATE OK`, zero warnings
  (`swift build 2>&1 | grep -c warning:` = 0); look at the capture.
- [ ] **Step 5:** Commit `feat(template): macOS 27, newest Sparkle and SwiftUI APIs`.

### Task 5: Placeholder engine and the platform/instrument split

**Files:**
- Modify (instrument files per MANIFEST): `templates/Sources/__APP__DSP/{Params.h,Params.cpp,Voice.h}`,
  `templates/Sources/__APP__DSP/__APP__Engine.cpp` (only where it names instrument knobs),
  `templates/Sources/__APP__Core/{SectionLayout.swift,Kits.swift}`,
  `templates/Sources/__APP__UI/Artwork.swift`, `templates/Tests/__APP__Reference/*`,
  `templates/Tests/__APP__CoreTests/{PrototypeScores,EngineTests,PrototypeEquivalenceTests,SoundRegressionTests,ListeningRenders,ModulationTests,ControllerTests,ParameterTableTests,PadTests,AudioUnitTests,AudioUnitWindowTests}.swift`
- Create: `templates/Sources/__APP__DSP/PlatformParams.h` (the platform's knobs)

**Interfaces:**
- Produces, parameter table order (permanent convention for every instrument): **platform knobs**
  (IDs from 0: `volume, pan, tune, octave, bendup, benddown, voicemode, glide, lfostart,
  lfo1rate, lfo1shape, lfo2rate, lfo2shape, velsens`), then **instrument knobs**, then LFO amounts,
  then VEL amounts. Identifiers are lowercase ASCII, unique (existing uniqueness test kept).
- Produces, the instrument seam in `Voice.h`: the platform engine calls only
  `void start(const Knobs&, int note, float velocity, bool continuing)`,
  `void release()`, `void render(float* out, int frames)`, `bool finished() const`, and the
  instrument's `constexpr` tables `kInstrumentKnobs[]`, `kLfoTargets[]`, `kVelTargets[]` (VEL
  targets must include `lfo1rate, lfo2rate`), `kModWheelTargets[]`/`kAftertouchTargets[]` as
  `{param, depth}` pairs, `kPrograms[]`, `kDefaultKit`. Whether a re-hit continues or chokes is
  the instrument's (`continuing`).
- Placeholder instrument "Tone": a sine with one harmonic, Attack, Decay, Release, Brightness;
  programs `Tone`, `Soft Tone`; default kit = Tone at notes 36…51, groups off.

- [ ] **Step 1:** Rewrite platform tests (`PadTests`, `ControllerTests`, `ModulationTests`,
  `ParameterTableTests`, `AudioUnit*Tests`) to address knobs by identifier from the platform block
  or "the first instrument knob", never by friction-drum names. Add
  `@Test("A pad hit applies its own set's VEL amounts")`: set pad 3's `vel<firstInstrumentKnob>`
  to +100 % and keyboard's to 0; hit pad 3 at velocity 127 and at 1; the rendered RMS differs by
  > 6 dB; the same two keyboard notes differ by < 0.1 dB.
- [ ] **Step 2:** Run → the new test and the renamed ones FAIL (no Tone engine yet).
- [ ] **Step 3:** Implement PlatformParams + Tone engine; instrument test files become small Tone
  versions (Reference = Tone spike copy, equivalence < −60 dB, two regression references).
  `SectionLayout.plans` empty (flowing layout); `Artwork` = native colours, no images.
- [ ] **Step 4:** `verify_template.sh --auval` → `TEMPLATE OK`; `check_leftovers.sh` with the
  friction words → no match.
- [ ] **Step 5:** Commit `feat(template): placeholder engine, platform/instrument seam`.

### Task 6: Melodic playing

**Files:**
- Modify: `templates/Sources/__APP__DSP/__APP__Engine.cpp` (voice allocation, MIDI handling),
  `PlatformParams.h`, `__APP__Core` presets/state if they enumerate parameters, panel's Master section
- Test: `templates/Tests/__APP__CoreTests/VoiceModeTests.swift`

**Interfaces:**
- Consumes: Task 5's seam and `voicemode` (choice `Poly, Mono, Legato`), `glide` (ms, 0–2000,
  log, default 0).
- Produces: sustain (CC 64 ≥ 64 = down) holds released voices in every mode; in pads mode sustain
  is ignored (a pad is a key press, released by its own note-off).

- [ ] **Step 1: Failing tests** in `VoiceModeTests`:
  - `polyChordSoundsThreeVoices`: Poly, notes 60/64/67 → `sounding_voices == 3`.
  - `monoLastNotePriority`: Mono, hold 60 then 64 → 1 voice at 64; release 64 → back to 60 (pitch
    from zero-crossings within 5 ct); release 60 → voice releases.
  - `legatoNoReattack`: Legato, 60 then 64 overlapping → `start(... continuing: true)` (peak level
    at the change < 1 dB above the sustained level); Mono → re-attack.
  - `glideTime`: Legato, glide 100 ms, 60→72: pitch at 50 ms is between 63 and 69.
  - `sustainHoldsReleased`: Poly, note on/off with pedal down → still sounding after 500 ms; pedal
    up → finished within the Release time.
  - `sustainWithMono`: Mono, pedal down, 60 on/off, 64 on/off → 64 sounds; pedal up → releases.
  - `modeChangeWhileSounding`: Poly with 3 voices, switch to Mono → no voice left sounding after all
    note-offs (no hang).
  - `auStateRoundTripsVoiceMode`: AU state save/restore keeps `voicemode` and `glide`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (a held-note stack of 16 per engine, no
  allocation). **Step 4:** `verify_template.sh --auval` → `TEMPLATE OK`. **Step 5:** Commit
  `feat(template): Poly/Mono/Legato, glide, sustain`.

### Task 7: Texts, website, manual and project skill as templates

**Files:**
- Modify: `templates/README.md`, `templates/CLAUDE.md`, `templates/development_workflow.md`,
  `templates/.claude/skills/release/SKILL.md`, `templates/docs/{index,manual}.html`,
  `templates/docs/cs/{index,manual}.html`, `templates/docs/assets/{site,manual}.css`,
  `templates/.planning/{ROADMAP,STATE}.md`

- [ ] **Step 1:** Replace instrument content with `<!-- FILL: … -->` blocks that say exactly what
  goes there (overview, what the instrument is, each section of the manual generated from the
  parameter table, programs, kit); keep structure, CS tag-for-tag parity, and the platform parts of
  the manual (modes, pads, presets, kits, MIDI learn, LFO/VEL, voice modes) written out in EN + CS.
- [ ] **Step 2:** `release/SKILL.md` keeps Fanfrnoch's procedure, renamed, with the catalog step
  split as the spec §5 says (edit `projects.json` locally before the push question; build check and
  push after publishing).
- [ ] **Step 3:** Render, open `docs/index.html` and `manual.html` (EN, CS) in headless Chrome at
  1440 and 400 px (Playwright); compare EN/CS tag sequences (must be equal).
- [ ] **Step 4:** Check the no-art panel capture from Task 5 looks intentional (Review Focus 5);
  fix `Artwork` defaults if not. `verify_template.sh --capture` → `TEMPLATE OK`.
- [ ] **Step 5:** Commit `feat(template): site, manual and project files with FILL markers`.

### Task 8: Window capture by PID

**Files:**
- Create: `scripts/capture_window.swift`

**Interfaces:**
- Produces: `swift scripts/capture_window.swift <pid> <out.png> [--wait 10]` → finds the first
  on-screen window with `kCGWindowOwnerPID == pid` and layer 0, runs
  `screencapture -x -o -l <id> <out.png>`; exit 3 if no window in time; exit 4 if the image is all
  black (locked screen) after deleting it. Never captures without `-l`.

- [ ] **Step 1:** Implement; **Step 2:** verify on the rendered dummy app (launched by path,
  `$!` as pid): PNG written, its size equals the window's; with a bogus PID → exit 3, no file.
- [ ] **Step 3:** Wire into `verify_template.sh --capture`; commit `feat: capture a window by PID`.

### Task 9: Spike harness and analysis tool

**Files:**
- Create: `scripts/spike_harness.h`, `scripts/spike_example.cpp`, `scripts/analyze.swift`
- Test: `tests/test_spike_analyze.sh`

**Interfaces:**
- Produces, `spike_harness.h` (header-only C++17): `struct Score { std::vector<Event> events; double length; }`;
  helpers `note(t, key, vel, dur)`, `stroke(t, key, vel)`, `chord(t, keys, vel, dur, spreadMs)`,
  `held(key, vel, dur)`, `phrase(startT, keys, step, dur)`; `writeWav(path, samples, rate)` 24-bit;
  `renderAll(dir, {name → lambda})`; `main` helper handling `<dir>` and `--analyze`.
- Produces, `analyze.swift`: `swift scripts/analyze.swift <wav>... [--json] [--tail a-b] [--ref <wav>]`
  → per file: f0 found **first** (autocorrelation, then harmonics read at that f0), H1…H10 dB re H1,
  spectral centroid, HNR, attack/decay/T60, RMS, peak, noise floor in the tail window; `--ref`
  prints differences. Converts non-WAV inputs with `afconvert` first.

- [ ] **Step 1: Failing test** `tests/test_spike_analyze.sh`: compile `spike_example.cpp`
  (`clang++ -std=c++17 -O2`), render a 220 Hz tone with H2 at −6 dB and a 1 s silent tail; analyze:
  f0 within 0.5 Hz of 220, H2 within 0.5 dB of −6, tail noise floor < −100 dBFS; a render with
  added −60 dBFS white noise in the tail → floor within 2 dB of −60.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (vDSP FFT, Hann, 5 ms hop). **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat: spike harness and analysis tool`.

### Task 10: References

**Files:**
- Create: `references/{research-briefs,prototype,spec-template,phases,codex,verification-kit,release,pitfalls}.md`

Content comes from the three SHARED reports; each file is the operational form (what to do, exact
commands, brief texts), not history. Required content:
- `research-briefs.md`: the five full briefs (spec §5 step 1 table) with the product-context
  paragraph, evidence labels, download safety rules, the report form (headline, summary, evidence
  paragraph, claim headings, "Recommendation for the engine", playing style, "Questions for the
  user's ear"), output paths.
- `prototype.md`: harness use, render naming by question, references folder (gitignored),
  `LISTENING.md` template, measuring incl. tail floor, how to present ("measured, not heard",
  decisive question first, fallback named, `open` + Quick Look), the twice-rejected rule.
- `spec-template.md`: the 11 sections with markers, identity and table order from Task 5.
- `phases.md`: one brief per phase (02 engine, 04 panel/app/AU/manual, 05 icon/site) with
  "read first (binding)", tasks, checks; main session re-runs tests before every merge.
- `codex.md`: invocation (`< /dev/null`, `-s workspace-write`, `--add-dir ~/.codex/generated_images`,
  `-o last-message.txt`, "do not stop for questions"), the concept brief (3 concepts or 2 + own pick),
  the assets prompt (sizes/alpha list, no baked text), icon (1024 opaque full-bleed → `.icon` +
  actool) and site prompts; the no-Codex fallback.
- `verification-kit.md`: Didgeridoo §13 table, screenshot protocol, scratch AU host, stand-ins
  marked with the release's `LC_BUILD_VERSION`, clean-up list, "Not verified" section.
- `release.md`: local release, the single bold push question (exact list from spec §5 step 4),
  publish order, live checks, catalog.
- `pitfalls.md`: every "what went wrong" item of the three reports as a one-line guard with the
  step it belongs to.

- [ ] **Step 1:** Write the files. **Step 2:** Check each guard in the three "what went wrong"
  sections maps to a line in `pitfalls.md` (list the mapping at the file's end).
- [ ] **Step 3:** Commit `docs: skill references`.

### Task 11: SKILL.md and installation

**Files:**
- Create: `SKILL.md`; symlink `~/.claude/skills/create-audio-plugin` → this directory

- [ ] **Step 1:** Use `superpowers:writing-skills`. `SKILL.md` follows spec §5 steps 0–5 in the
  order and with the gates as written, points to `references/` and `scripts/` by path, and has a
  "Common mistakes" table. Description triggers on "audio plugin for <instrument>", "chci audio
  plugin pro …", "nový nástroj jako Brumle". Language rule: talk in the user's language.
- [ ] **Step 2:** Create the symlink; confirm the skill is listed in a fresh `claude` session
  (`claude -p "list your skills" | grep create-audio-plugin`).
- [ ] **Step 3:** Dry intake test: in `<scratch>/Strunobijec/` run
  `claude -p "chci audio plugin pro elektrickou kytaru"` and check the reply stops at the intake
  question (name + look), creates nothing in the directory and pushes nothing.
- [ ] **Step 4:** Final `scripts/verify_template.sh --auval --capture` → `TEMPLATE OK`; commit
  `feat: create-audio-plugin skill`.
