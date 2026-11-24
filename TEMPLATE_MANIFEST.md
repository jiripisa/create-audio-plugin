# Template manifest

`templates/` is Fanfrnoch, the source instrument of design spec §7, at its tag `v1.0.0` with its
identity replaced by placeholders, moved to macOS 27 (§"macOS 27" below). It still carries the
friction-drum engine; the placeholder engine and the platform/instrument seam come later.
`scaffold.py --templates` renders it (double-brace variables, flag blocks, `__APP__` in paths).

This file is the skill's map of the template. It lives at the repo root, outside `templates/`, so
it is never rendered into a project and may name the source and its siblings plainly.

Every file is **platform** (rendered as it is on every run) or **instrument** (a run replaces its
content with the new instrument's; the line says with what).

## How it was made

1. `git -C <Fanfrnoch repo> archive v1.0.0`, everything except `.planning/`, `Resources/Art/`,
   `Resources/AppIcon.png`, `docs/assets/*.png|*.jpg`, `docs/assets/manual/` and `LICENSE`
   (scaffold writes it from `LICENSE_KEY`).
2. Paths renamed deepest-first, `Fanfrnoch` → `__APP__`.
3. Text, with `LC_ALL=C sed`, in this order (earlier rules win):

   | Source | Template |
   |---|---|
   | `https://jiripisa.github.io/fanfrnoch/` | `{{PAGES_URL}}` |
   | `https://github.com/jiripisa/fanfrnoch` | `{{REPO_URL}}` |
   | `jiripisa/fanfrnoch` (gh commands) | `{{OWNER}}/{{APP_LOWER}}` |
   | `jiripisa/jiripisa.github.io`, `https://jiripisa.github.io/` (catalog) | `{{OWNER}}/{{OWNER}}.github.io`, `https://{{OWNER}}.github.io/` |
   | `io.jp4.fanfrnoch` (app; `.audiounit` for the component) | `{{BUNDLE_ID}}` |
   | `1.0.0` in `Resources/Info.plist` and `docs/**/*.html` | `{{VERSION}}` (0.1.0) |
   | `Fanfrnoch` | `{{APP}}` |
   | `FANFRNOCH` | `{{APP_UPPER}}` |
   | `fanfrnoch_` | `{{APP_C}}_` |
   | `fanfrnoch` | `{{APP_LOWER}}` |
   | `'Fanf'`, `<string>Fanf</string>`, `aumu Fanf JPis`, `` `Fanf` `` | `{{AU_SUBTYPE}}` |

4. By hand: `CHANGELOG.md` reset to `## Unreleased` / `- First version.`; `docs/appcast.xml`
   emptied to its channel (no `<item>`); the tagline in `README.md`, `CLAUDE.md` and the site's
   meta/lede → `{{TAGLINE}}` / `{{TAGLINE_CS}}`; footers' `Jiří Píša. MIT License.` →
   `{{AUTHOR}}. {{LICENSE_LABEL}}.` (`{{LICENSE_LABEL_CS}}` in `docs/cs/`); README's licence line
   in LICENSE / not-LICENSE flag blocks as in `new-macos-app`; the release skill's "first release
   was 1.0.0" → "first release is 0.1.0"; comments naming a sibling instrument (Brumle,
   Didgeridoo) rewritten without it (`Lfo.h`, `MidiQueue.h`, `__APP__Engine.cpp`).

`scripts/check_leftovers.sh templates` (words: `scripts/leftover-words.txt`) finds no identity
token; the subtype `Fanf` is matched as a whole word only, so that words such as `Fanfare` stay
allowed. Content words of the friction drum (drum, friction, stick, horsehair, the programs'
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
  `Jiri Pisa: {{APP}}`) and the shared Sparkle `SUPublicEDKey`.
- **Display names use `{{APP}}`**, as the mechanical rename gives them (window title, bundle
  names, the site). For a name with spaces or diacritics `{{APP_NAME}}` would read better there.
- **Feature flags are not wired**: the template always renders the site, manual, Czech pages,
  Sparkle and the release skill (the verification config sets every flag true).

## macOS 27

A plug-in made by the skill is always for macOS 27, with the newest libraries. The version is
written into the template, not taken from the config's `MIN_MACOS`: the code uses APIs that
macOS 27 introduced, so a project for an older system would not build. (The verification config
still says `MIN_MACOS: "27.0"`, so that the derived `SWIFT_TOOLS` agrees.) Checked with macOS
27.2.1, Xcode 27.2 (SDK 27.2), Swift 6.4.2.

- `Package.swift`: `// swift-tools-version: 6.4`, `.macOS(.v27)`; Sparkle `from: "2.10.1"`, the
  newest 2.x release (`gh api repos/sparkle-project/Sparkle/releases/latest` on 2026-11-24;
  2.11.0-beta.1 is a pre-release and not taken). `Package.resolved` already pinned 2.10.1.
- `LSMinimumSystemVersion` `27.0` in `Resources/Info.plist` and `Resources/AudioUnit-Info.plist`;
  actool's `--minimum-deployment-target 27.0` in `build.sh` (and its copy in
  `development_workflow.md`); `MIN_SYSTEM = "27.0"` (the appcast's
  `sparkle:minimumSystemVersion`) in `scripts/make_appcast.py`.
- Text: "macOS 27 or later" in `README.md`, `docs/index.html`, `docs/cs/index.html` (both
  places each); "macOS 27+" in `CLAUDE.md`; "Xcode 27 (Swift 6.4), macOS 27+" and the icon note in
  `development_workflow.md`.
- **No warnings.** `swift build`, `swift test`, `swift test -c release` and `./build.sh release`
  of the rendered project print no `warning:` line; `scripts/verify_template.sh` fails when one
  appears.

### API replacements

The SDK marks an API either deprecated in a version (the compiler warns at deployment target 27)
or "to be deprecated" (`deprecated: 100000`, no warning yet, the replacement named). Both kinds
were replaced where the template used them:

| Old | New | File | SDK mark |
|---|---|---|---|
| `AVAudioIONode.audioUnit` | `withAudioUnit { unit in … }` (the optional unit copied out inside the closure) | `Sources/__APP__/AudioOutput.swift` (device, channel map) | deprecated 27.0, "in favor of withAudioUnit" |
| `AVAudioEngine.connect(_:to:format:)` | `try connectNode(_:to:format:)` | `Sources/__APP__/AudioOutput.swift` | deprecated 27.0, replacement `connect:to:format:error:` |
| `overlay(_:alignment:)` with a view | `overlay { … }` | `Sources/__APP__UI/HeaderView.swift`, `ModeFooterView.swift` | to be deprecated, "Use `overlay(alignment:content:)`" |
| `URL.appendingPathComponent(_:)`, `(_:isDirectory: true)` | `appending(path:)`, `appending(path:directoryHint: .isDirectory)` | `Sources/__APP__Core/Presets.swift`, `Sources/__APP__/AppModel.swift`; tests `KitTests`, `PresetLibraryTests`, `PresetFileTests`, `PresetShelvesTests`, `ListeningRenders` | to be deprecated |
| `URL.path` | `path(percentEncoded: false)` | `Sources/__APP__/AppModel.swift`; tests `KitTests`, `PresetLibraryTests` | to be deprecated |
| `URL(fileURLWithPath:isDirectory: true)` | `URL(filePath:directoryHint: .isDirectory)` | `Tests/__APP__CoreTests/ListeningRenders.swift` | to be deprecated |

Behaviour stays the same; where the new API differs it does not show:

- `connectNode` reports a failure as a thrown error where `connect` raised an Objective-C
  exception (the app died). The error now becomes the settings window's "Audio did not start: …"
  problem and audio stays off until the next hardware change, as for an unusable format.
- `appendingPathComponent(_:)` without `isDirectory` asked the file system whether the path is a
  directory and then added a trailing slash; `appending(path:)` infers it from the path. Every such
  URL is a file, a folder that does not exist yet, or a bundle path handed to `FileManager`,
  which ignores the slash.
- `path(percentEncoded: false)` keeps a directory URL's trailing slash, `path` dropped it. The two
  tests on the standard folders (`PresetLibraryTests`) now expect `…/{{APP}}/Presets/` and
  `…/{{APP}}/Kits/`.

### Checked and current

- Compiler: no deprecation warning left in Swift or C++ (`__APP__AU.cpp`, the vendored
  AudioUnitSDK, the DSP).
- The SDK's Swift interfaces of SwiftUI, SwiftUICore, AppKit, AVFAudio, AVFoundation,
  Foundation, CoreMIDI, AudioToolbox, CoreAudio, Observation, Synchronization and os, scanned for
  declarations marked deprecated (in a version or "to be deprecated") whose name the template's
  Swift code uses, and the Objective-C/C headers of AppKit, AudioToolbox, CoreMIDI, CoreAudio,
  AVFAudio, CoreFoundation and vecLib for the functions it calls. Current, nothing to replace:
  `Font.system(size:weight:design:)` (the calls resolve to the optional-parameter overload; the
  deprecated one is disfavoured),
  `onChange(of:)` with two parameters, `onTapGesture(count:)` without a coordinate space,
  `background(_:in:)`, `DragGesture`, `GeometryReader`, `Image(nsImage:)`, `NSHostingView`,
  `AUCocoaUIBase`; CoreMIDI's `MIDIClientCreateWithBlock`, `MIDIInputPortCreateWithProtocol`,
  `MIDIDestinationCreateWithProtocol`, `MIDIEventList`; the `AudioUnit…`, `AudioComponent…` and
  `AudioObject…` C functions; `Mutex`, `OSAllocatedUnfairLock`; vDSP's FFT and window functions;
  Sparkle 2.10.1's `SPUStandardUpdaterController`.
- Not adopted, because the SDK does not mark the old way deprecated and this step does not
  change the UI: Foundation's typed notification messages (`NSApplication.WillTerminateMessage`,
  `DidResignActiveMessage`) in place of the name-based observers, and Liquid Glass
  (`glassEffect`) for the panel.

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
| `TEMPLATE_MANIFEST.md` (repo root, not in `templates/`) | skill only | this map; never rendered |
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
