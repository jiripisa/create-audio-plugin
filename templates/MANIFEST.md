# Template manifest

This tree is the source instrument of design spec §7 at its tag `v1.0.0` with its identity
replaced by placeholders. It still carries the friction-drum engine; the placeholder engine and
the platform/instrument seam come later. `scaffold.py --templates` renders it (double-brace
variables, flag blocks, `__APP__` in paths).

This file is the skill's map of the template, not part of a project: scaffold renders it like any
other file, and `scripts/verify_template.sh` (as every run of the skill) deletes it from the
rendered project right away. It must stay renderable (no double-brace tag here may name anything
but a config variable, and no flag block may open) and free of the words of
`scripts/leftover-words.txt`, which is why the source's name is written `Src` below.

Every file is **platform** (rendered as it is on every run) or **instrument** (a run replaces its
content with the new instrument's; the line says with what).

## How it was made

`Src`, `SRC` and `src` stand for the source's name in its PascalCase, upper and lower case
spellings, `Sub` for its 4-character AU subtype.

1. `git -C <source repo> archive v1.0.0`, everything except `.planning/`, `Resources/Art/`,
   `Resources/AppIcon.png`, `docs/assets/*.png|*.jpg`, `docs/assets/manual/` and `LICENSE`
   (scaffold writes it from `LICENSE_KEY`).
2. Paths renamed deepest-first, `Src` → `__APP__`.
3. Text, with `LC_ALL=C sed`, in this order (earlier rules win):

   | Source | Template |
   |---|---|
   | `https://jiripisa.github.io/src/` | `{{PAGES_URL}}` |
   | `https://github.com/jiripisa/src` | `{{REPO_URL}}` |
   | `jiripisa/src` (gh commands) | `{{OWNER}}/{{APP_LOWER}}` |
   | `jiripisa/jiripisa.github.io`, `https://jiripisa.github.io/` (catalog) | `{{OWNER}}/{{OWNER}}.github.io`, `https://{{OWNER}}.github.io/` |
   | `io.jp4.src` (app; `.audiounit` for the component) | `{{BUNDLE_ID}}` |
   | `1.0.0` in `Resources/Info.plist` and `docs/**/*.html` | `{{VERSION}}` (0.1.0) |
   | `Src` | `{{APP}}` |
   | `SRC` | `{{APP_UPPER}}` |
   | `src_` | `{{APP_C}}_` |
   | `src` | `{{APP_LOWER}}` |
   | `'Sub'`, `<string>Sub</string>`, `aumu Sub JPis`, `` `Sub` `` | `{{AU_SUBTYPE}}` |

4. By hand: `CHANGELOG.md` reset to `## Unreleased` / `- First version.`; `docs/appcast.xml`
   emptied to its channel (no `<item>`); the tagline in `README.md`, `CLAUDE.md` and the site's
   meta/lede → `{{TAGLINE}}` / `{{TAGLINE_CS}}`; footers' `Jiří Píša. MIT License.` →
   `{{AUTHOR}}. {{LICENSE_LABEL}}.` (`{{LICENSE_LABEL_CS}}` in `docs/cs/`); README's licence line
   in LICENSE / not-LICENSE flag blocks as in `new-macos-app`; the release skill's "first release
   was 1.0.0" → "first release is 0.1.0"; comments naming a sibling instrument rewritten without
   it (`Lfo.h`, `MidiQueue.h`, `__APP__Engine.cpp`).

`scripts/check_leftovers.sh templates` (words: `scripts/leftover-words.txt`) finds no identity
token. Content words of the friction drum (drum, friction, stick, horsehair, the programs'
instrument names, …) are still here on purpose.

## What resisted a plain rename

- **The test subtype.** The AU tests register the unit in-process under a subtype of their own so
  an installed copy stays out (`'Fant'`, hard-coded as `0x4661_6E74`). It is now computed in Swift
  from the string: `PlugIn.subtypeUnderTest` in `AudioUnitTests.swift` takes `"{{AU_SUBTYPE}}"` and
  changes its last character to `t` (`u` if it already is `t`). The real subtype is a C character
  literal (`'{{AU_SUBTYPE}}'` in `__APP__AU.h`) and a plist string, so it needs no hex anywhere.
- **Braces that are not tags.** The renderer only takes two opening braces, an optional `#`, `^`
  or `/`, uppercase letters or `_`, two closing braces. C++ aggregate
  initialisers (`{{kLength, 150}, …}` in `Params.cpp`) and Python's f-string braces in
  `scripts/make_appcast.py` do not match; no file of the source held a literal tag.
  `make_appcast.py`'s f-string now holds `{{PAGES_URL}}` and `{{APP}}`, rendered to plain text before
  Python ever reads it.
- **The C++ namespace** is `namespace {{APP_LOWER}}`; `identity.py` guarantees it starts with a letter.
- **Names built from the instrument's name**: programs `{{APP}}` and `{{APP}} High` with their enum
  values `k{{APP}}`, `k{{APP}}High` (`Params.h/.cpp`), test names such as `b_{{APP_C}}_default_groove`,
  the kit extension `.{{APP_LOWER}}kit`, Czech declensions such as `{{APP}}u` in `docs/cs/`. They
  render to valid code and text; the instrument files that hold them are replaced per run.
- **Kept as they are**: the manufacturer code `JPis` and its name `Jiri Pisa` (the AU's `name` is
  `Jiri Pisa: {{APP}}`), the shared Sparkle `SUPublicEDKey`, `Package.resolved`, and macOS 26
  (`.macOS(.v26)`, tools 6.2, `LSMinimumSystemVersion`, actool's deployment target) until the
  move to macOS 27.
- **Display names use `{{APP}}`**, as the mechanical rename gives them (window title, bundle
  names, the site). For a name with spaces or diacritics `{{APP_NAME}}` would read better there.
- **Feature flags are not wired**: the template always renders the site, manual, Czech pages,
  Sparkle and the release skill (the verification config sets every flag true).

## Placeholder art

- `Resources/AppIcon.png` — **instrument**: a plain grey 1024 × 1024 opaque PNG so that `build.sh`
  (actool) has a master to compile; a run puts the instrument's icon art here.
- `Resources/Art/` is absent: `build.sh` copies it only when it exists and `Artwork` falls back to
  its colours. A run puts the panel's artwork here (**instrument**).
- `docs/assets/*.png|*.jpg` are absent (the window screenshot, hero, icon, ornament and the
  manual's screenshots): the site still links them; a run makes them (**instrument**).

## Files

### Project

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `MANIFEST.md` | platform | this map |
| `.gitignore` | platform | build output, local Claude files, spike renders |
| `Package.swift` | platform | targets DSP, AudioUnitSDK, AU, AUView, AUExports, Core, UI, app, Reference, tests |
| `Package.resolved` | platform | Sparkle pin |
| `build.sh` | platform | debug / release / dist / clean, app + component bundle, actool icon |
| `run.sh` | platform | debug in the terminal / release with `open` |
| `scripts/make_appcast.py` | platform | Sparkle feed from the CHANGELOG section |
| `CHANGELOG.md` | platform | `## Unreleased` |
| `README.md` | platform | name, tagline, build commands, licence |
| `CLAUDE.md` | platform | project rules; its first line is `{{TAGLINE}}` |
| `development_workflow.md` | platform | toolchain, build, auval, icon, distribution, phases |
| `.claude/skills/release/SKILL.md` | platform | the release procedure |

### Resources

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `Resources/Info.plist` | platform | app bundle: id, version `{{VERSION}}`, Sparkle feed + key |
| `Resources/AudioUnit-Info.plist` | platform | component: `aumu` / `{{AU_SUBTYPE}}` / `JPis`, factory |
| `Resources/__APP__.entitlements` | platform | unsandboxed, audio input off |
| `Resources/AppIcon.icon/icon.json` | platform | Icon Composer document (one full-bleed layer; its fill colour may follow the art) |
| `Resources/AppIcon.png` | instrument | the icon master (placeholder: plain grey) |
| `Resources/Art/*` | instrument | the panel's artwork (absent in the template) |

### Sources

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `Sources/__APP__DSP/include/__APP__DSP.h` | platform | C interface to the engine |
| `Sources/__APP__DSP/__APP__Engine.cpp` | platform | voices, pads, sets, LFOs, MIDI, oversampling, limiter (names instrument knobs in places) |
| `Sources/__APP__DSP/Params.h` | instrument | the parameter table's enum, sections, programs |
| `Sources/__APP__DSP/Params.cpp` | instrument | the table, the sections, the programs, the default kit |
| `Sources/__APP__DSP/Voice.h` | instrument | the instrument's voice from the approved prototype |
| `Sources/__APP__DSP/Lfo.h` | platform | LFO phase and its seven shapes |
| `Sources/__APP__DSP/MidiQueue.h` | platform | lock-free MIDI queue to the audio thread |
| `Sources/__APP__DSP/HalfBand.h` | platform | decimator by 2 |
| `Sources/__APP__DSP/dsp/noise.h` | platform | noise and xorshift generator |
| `Sources/__APP__AU/__APP__AU.cpp` | platform | the AUv2 music device on AudioUnitSDK |
| `Sources/__APP__AU/include/__APP__AU.h` | platform | the AU's permanent codes, bundle id, view class, properties |
| `Sources/__APP__AUExports/Exports.c`, `include/__APP__AUExports.h` | platform | no code: the exported factory symbol |
| `Sources/__APP__AUView/AudioUnitModel.swift` | platform | the panel's model over the unit in a host |
| `Sources/__APP__AUView/AudioUnitWindow.swift` | platform | the plug-in's window, `__APP__AUViewFactory` |
| `Sources/__APP__Core/__APP__Core.swift` | platform | the skeleton's greeting |
| `Sources/__APP__Core/AppModelLogic.swift` | platform | when the app saves the sound |
| `Sources/__APP__Core/Controllers.swift` | platform | MIDI controllers and learn |
| `Sources/__APP__Core/KeyboardLayout.swift` | platform | the on-screen keyboard's keys |
| `Sources/__APP__Core/KeyStrip.swift` | platform | press position → velocity |
| `Sources/__APP__Core/Kits.swift` | platform | kits and the kit library |
| `Sources/__APP__Core/LibraryMenu.swift` | platform | Preset and Kit menus |
| `Sources/__APP__Core/Modulation.swift` | platform | LFO and VEL amounts |
| `Sources/__APP__Core/Notes.swift` | platform | note names |
| `Sources/__APP__Core/PadPanel.swift` | platform | what the panel writes on pads |
| `Sources/__APP__Core/Parameter.swift` | platform | one knob, from the engine's table |
| `Sources/__APP__Core/Presets.swift` | platform | presets and their library |
| `Sources/__APP__Core/PresetShelves.swift` | platform | a window's view of the files per set |
| `Sources/__APP__Core/SectionLayout.swift` | platform, its `plans` instrument | placement of a section's controls; a run writes the `plans` for its sections |
| `Sources/__APP__Core/StandaloneSettings.swift` | platform | MIDI source, audio output choices |
| `Sources/__APP__Core/Synth.swift` | platform | the Swift wrapper over the engine |
| `Sources/__APP__Core/SynthState.swift` | platform | saved knob sets |
| `Sources/__APP__UI/Artwork.swift` | instrument | the panel's images and palette |
| `Sources/__APP__UI/HeaderView.swift` | platform | emblem, wordmark, menus, mode, LFO/VEL/MIDI |
| `Sources/__APP__UI/InstrumentModel.swift` | platform | what the panel needs from its owner |
| `Sources/__APP__UI/InstrumentPanel.swift` | platform | the panel |
| `Sources/__APP__UI/KeyboardStripView.swift` | platform | three octaves of keys |
| `Sources/__APP__UI/KnobEdit.swift`, `KnobView.swift` | platform | knobs and their edits |
| `Sources/__APP__UI/LibraryMenuView.swift`, `NameSheetView.swift` | platform | file menus, Save as… |
| `Sources/__APP__UI/ModeFooterView.swift` | platform | keyboard / pads footer (places the instrument art where it exists) |
| `Sources/__APP__UI/PadGridView.swift`, `PadInspectorView.swift`, `SendToPadView.swift` | platform | pads |
| `Sources/__APP__UI/SectionView.swift` | platform | one section's card |
| `Sources/__APP__/*.swift` (`__APP__App`, `AppModel`, `AudioOutput`, `ContentView`, `MIDIInput`, `SettingsView`, `UpdateService`) | platform | the standalone app |
| `ThirdParty/AudioUnitSDK/**` | platform | Apple's AudioUnitSDK (Apache-2.0), vendored unchanged |

### Tests

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `Tests/__APP__Reference/__APP__Reference.cpp`, `include/__APP__Reference.h` | instrument | the approved listening prototype as a C++ reference |
| `Tests/__APP__CoreTests/PrototypeScores.swift` | instrument | the prototype's scores and reference render calls |
| `Tests/__APP__CoreTests/PrototypeEquivalenceTests.swift` | instrument | engine vs prototype for the instrument's renders |
| `Tests/__APP__CoreTests/SoundRegressionTests.swift` | instrument | fingerprints taken from the new engine |
| `Tests/__APP__CoreTests/ListeningRenders.swift` | instrument | renders of the instrument for the ear |
| `Tests/__APP__CoreTests/Grooves.swift` | instrument | scores over the instrument's default kit |
| `Tests/__APP__CoreTests/ReferenceTests.swift` | instrument | the reference renders its own scores |
| `Tests/__APP__CoreTests/EngineHarness.swift` | platform | engine test helpers and measures |
| `Tests/__APP__CoreTests/EngineTests.swift` | platform | engine promises (names instrument knobs in places) |
| `Tests/__APP__CoreTests/ParameterTableTests.swift` | platform | table invariants (lists the instrument's knobs in places) |
| `Tests/__APP__CoreTests/ModulationTests.swift`, `ControllerTests.swift`, `PadTests.swift` | platform | LFO/VEL, controllers, pads (address instrument knobs in places) |
| `Tests/__APP__CoreTests/AudioUnitTests.swift`, `AudioUnitWindowTests.swift` | platform | the AU in-process, its window model |
| `Tests/__APP__CoreTests/SectionLayoutTests.swift` | platform | placement (checks the instrument's plans in places) |
| `Tests/__APP__CoreTests/ThreadTests.swift` | platform | audio-thread rules |
| `Tests/__APP__CoreTests/` `__APP__CoreTests`, `AppModelLogicTests`, `KeyboardLayoutTests`, `KeyStripTests`, `KitTests`, `KnobEditTests`, `LibraryMenuTests`, `NotesTests`, `PadPanelTests`, `PresetFileTests`, `PresetLibraryTests`, `PresetShelvesTests`, `StandaloneSettingsTests`, `SynthStateTests`, `SynthTests` | platform | the platform's logic |

### Website (`docs/`)

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `docs/.nojekyll` | platform | Pages serves files as they are |
| `docs/appcast.xml` | platform | empty Sparkle feed; `build.sh dist` writes it |
| `docs/assets/site.css`, `manual.css` | platform | shared styles |
| `docs/index.html`, `docs/cs/index.html` | platform frame, instrument body | head, nav, download, footer stay; a run writes what the instrument is and its images |
| `docs/manual.html`, `docs/cs/manual.html` | platform frame, instrument body | the platform's chapters (modes, pads, presets, kits, MIDI, LFO/VEL) stay; a run writes the sections of its knobs, its programs and kit |
| `docs/assets/*.png`, `docs/assets/*.jpg`, `docs/assets/manual/*` | instrument | screenshots, hero, icon, ornament (absent in the template) |
