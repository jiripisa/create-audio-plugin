# Template manifest

`templates/` is Fanfrnoch, the source instrument of design spec §7, at its tag `v1.0.0` with its
identity replaced by placeholders, moved to macOS 27 (§"macOS 27" below), with its friction-drum
engine replaced by a placeholder instrument, "Tone", behind a seam between the platform and the
instrument (§"The instrument seam" below). The site, the manual and the planning files say what
is the instrument's with `FILL` comments (§"Texts: FILL markers" below).
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

`scripts/check_leftovers.sh templates` (words: `scripts/leftover-words.txt`, the list a run uses
too) finds no identity token; the subtype `Fanf` is matched as a whole word only, so that words
such as `Fanfare` stay allowed. That list also holds the test render's name (`Zkusebnik`,
`Zkušebník`). The template's own list, `scripts/template-words.txt`, holds the siblings' names and
the friction drum's content words (drum, friction, stick, rub, skin, pot, the programs' instrument
names, the palette's Modrotisk, …, and the Czech pages' buben, žíně, hrnec, …), short ones as
whole words so that `sticky` or `pottery` stay allowed; a run does not use it, since a new
instrument may share them. Both find nothing in `templates/`, with no directory skipped:
`verify_template.sh` checks the template with both and the rendered project with the second.

## What resisted a plain rename

- **The test subtype.** The AU tests register the unit in-process under a subtype of their own so
  an installed copy stays out (`'Fant'`, hard-coded as `0x4661_6E74`). It is now computed in Swift
  from the string: `PlugIn.subtypeUnderTest` in `AudioUnitTests.swift` takes `"{{AU_SUBTYPE}}"` and
  changes its last character to `t` (`u` if it already is `t`). The real subtype is a C character
  literal (`'{{AU_SUBTYPE}}'` in `__APP__AU.h`) and a plist string, so it needs no hex anywhere.
- **Braces that are not tags.** The renderer only takes two opening braces, an optional `#`, `^`
  or `/`, uppercase letters or `_`, two closing braces. C++ aggregate
  initialisers (`{{kLength, 150}, …}` in the source's `Params.cpp`; the template's tables
  write `{ {` with a space) and Python's f-string braces in
  `scripts/make_appcast.py` do not match; no file of the source held a literal tag.
  `make_appcast.py`'s f-string now holds `{{PAGES_URL}}` and `{{APP}}`, rendered to plain text before
  Python ever reads it.
- **The C++ namespace** is `namespace {{APP_LOWER}}`; `identity.py` guarantees it starts with a letter.
- **Names built from the instrument's name**: the kit extension `.{{APP_LOWER}}kit`, the
  listening renders' directory variable `{{APP_UPPER}}_LISTEN_DIR`. They render to valid code.
  The Czech pages never decline the name (it may be any word): they write "aplikace
  {{APP_NAME}}", "plugin {{APP_NAME}}" or leave it out.
- **Kept as they are**: the manufacturer code `JPis` and its name `Jiri Pisa` (the AU's `name` is
  `Jiri Pisa: {{APP}}`) and the shared Sparkle `SUPublicEDKey`.
- **Display names use `{{APP_NAME}}`** (it may hold diacritics, digits, spaces and hyphens, e.g.
  "Čimbál", "Tape Loop 2"; `identity.py` refuses any other character, and a space or hyphen at
  either end, because the name is written unescaped into Swift strings, plists, XML, HTML and
  shell lines; it composes the name to NFC),
  `{{APP}}` stays where a file, a folder, a target or a code name is meant. `{{APP_NAME}}`:
  `CFBundleName` and `CFBundleDisplayName` of the app (so the app menu, About and Quit), the
  component's `CFBundleName`, its `AudioComponents` `name` (`Jiri Pisa: {{APP_NAME}}`, the
  manufacturer prefix kept) and `description`, the window title (`{{APP}}App.swift`), the panel's
  wordmark (`HeaderView`), the MIDI client and the virtual MIDI port (`MIDIInput`) and the
  Settings text naming it, the "is not a … file" message (`Presets.swift`), the DMG's volume name
  (`build.sh`), the appcast's titles (`make_appcast.py`, `docs/appcast.xml`), every heading and
  sentence of the site, the manual, `README.md`, `CLAUDE.md`, `development_workflow.md`, the
  release skill and `.planning`. `{{APP}}`: the bundle and executable (`{{APP}}.app`, what the user
  drags to Applications), `{{APP}}.component`, the DMG file `{{APP}}-<version>.dmg`, the folder
  `~/Library/Application Support/{{APP}}/`, Swift and C identifiers, test-only names.
  `verify_template.sh` renders with `APP_NAME` "Zkušebník Test" (`APP` Zkusebnik), so the build,
  the tests and `auval` run with such a name (`auval` shows `AudioUnit Name: Zkušebník Test`).
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
- `Resources/Art/` is absent: `build.sh` copies it only when it exists, and every image `Artwork`
  names (`background`, `figure`, `logo`, `knob`, `ornament`) falls back to a plain look; the
  template's palette is the system's own colours. A run puts the panel's artwork here (**instrument**).
- `docs/assets/*.png|*.jpg` are absent (the window screenshot, hero, icon, ornament and the
  manual's screenshots): the site still links them; a run makes them (**instrument**).

## The instrument seam

The engine is the platform; an instrument is three files a run writes from its spec and its
approved prototype: `Sources/__APP__DSP/Params.h` (its knobs and tables), `Voice.h` (its voice)
and `Tests/__APP__Reference/*` with the instrument test files (table below). Everything else
stays as it is. The contract below is checked at compile time by `static_assert`s in
`ParamTable.h` (identifiers lowercase ASCII and unique; a controller per knob, unreserved and
unique; LFO targets continuous, once each, with Volume, Pan and Tune; VEL targets continuous, once
each, with Volume, Pan, Tune and both LFO rates and without Vel Sens; wheel targets continuous
with depths in (0, 1]; the instrument's defaults of platform knobs (`kPlatformDefaults`) name
knobs of the platform block, each once, within its range (a whole number for a switch or an
integer knob), and the default kit sets none of them; the test sound (`kTestSound`) sets knobs
of the instrument's own, each once, within its range; every instrument knob in exactly one section; programs and kit in range;
fewer than 1000 knobs and at most two LFOs; every stable ID round-trips), and at test time by
`ParameterTableTests` (the platform block's identifiers, order, ranges, choices and units; its
defaults the platform's own, `TestKnobs.platformOwn`, except where the instrument sets one, which
the table then reports, `{{APP_C}}_param_info`, as the C list `{{APP_C}}_platform_default_*` says;
the first program is the defaults; knobs, then LFO 1's, LFO 2's and the VEL amounts; amounts at -100 … 100 %, 0; Master last
with the platform block; every continuous instrument knob a VEL target; at least two programs,
none setting Octave; the test sound as the engine lists it, `{{APP_C}}_test_sound_*`),
`AudioUnitTests.stableParameterIDs` (the IDs below) and
`.unknownParameterRefused` (the unit refuses a global ID the table does not have, also before
Initialize, where the SDK's parameter map would otherwise add it: `__APP__AU::SetParameter`).

**The parameter table** (the engine's index; the Audio Unit's IDs and saved state do not depend
on it, see "Stable IDs" below):

1. The platform block, IDs 0-13, the same for every instrument (`PlatformParams.h`). The
   defaults below are the platform's own; an instrument's spec may choose its own for any of
   them (its playing style: a flute Legato with glide, a guitar Poly with Bend 2), in
   `kPlatformDefaults` only (see "What a run writes in `Params.h`"):

   | ID | Identifier | Name | Range, default | CC |
   |---|---|---|---|---|
   | 0 | `volume` | Volume | -40 … 6 dB, 0 | 7 |
   | 1 | `pan` | Pan | -100 … 100 %, 0 | 10 |
   | 2 | `tune` | Tune | -100 … 100 ct, 0 | 102 |
   | 3 | `octave` | Octave | -2 … 2, 0 (programs leave it alone) | 103 |
   | 4 | `bendup` | Bend Up | 0 … 24 st, 2 | 104 |
   | 5 | `benddown` | Bend Down | 0 … 24 st, 2 | 105 |
   | 6 | `voicemode` | Voice Mode | Poly, Mono, Legato; Poly | 106 |
   | 7 | `glide` | Glide | 0 … 2000 ms, log (`log(1 + x / 2 ms)`), 0 | 5 |
   | 8 | `lfostart` | LFO Start | Hit, Free; Hit | 107 |
   | 9 | `lfo1rate` | LFO 1 Rate | 0.02 … 20 Hz, log, 6 | 108 |
   | 10 | `lfo1shape` | LFO 1 Shape | Sine … Wander (7); Sine | 109 |
   | 11 | `lfo2rate` | LFO 2 Rate | 0.02 … 20 Hz, log, 2 | 110 |
   | 12 | `lfo2shape` | LFO 2 Shape | Sine … Wander (7); Sine | 111 |
   | 13 | `velsens` | Vel Sens | 0 … 100 %, 70 | 112 |

2. The instrument's knobs, IDs from 14 (`kInstrumentKnobs`, in the enum's order).
3. The LFO amounts: LFO 1 on each of `kLfoTargets` (`lfo1<id>`, "LFO 1><Name>"), then LFO 2
   on the same knobs.
4. The VEL amounts: one on each of `kVelTargets` (`vel<id>`, "VEL><Name>").

Every amount is -100 … 100 %, 0 at rest. The template's Tone fills it as: 14 `attack` (1 … 2000 ms,
log, 5, CC 73), 15 `decay` (0.05 … 20 s, log, 2, CC 75), 16 `release` (0.01 … 5 s, log, 0.3, CC
72), 17 `brightness` (0 … 100 %, 30, CC 74); LFO amounts 18-25 on volume, pan, tune, brightness;
VEL amounts 26-34 on attack, decay, release, brightness, volume, pan, tune, lfo1rate, lfo2rate:
35 parameters.

**Stable IDs.** A parameter's index in the table moves when a knob is appended (every amount
after it moves on) or an LFO or VEL target is added; what hosts and saved state hold does not:

- The Audio Unit's parameter ID (`{{APP_C}}_param_id`, `Parameter.unitID`): knob k → k (its index
  among the knobs, platform block first); LFO l's amount on knob k → 1000·(l + 1) + k; the VEL
  amount on knob k → 3000 + k. The unit keeps its parameters by these IDs (not as an indexed
  run), maps them to the engine's index (`{{APP_C}}_param_index`), and restores only the IDs it has
  from a project's saved parameters (`copyKnownParameters`), so that one from another version adds
  none. Tone: knobs 0-17, LFO 1 1000-1017, LFO 2 2000-2017, VEL 3000-3017 (only the targets').
- Everything else that is saved names parameters by identifier: the AU state's pads
  (`"values": { identifier: value }`) and controllers (`{ identifier: controller }`), the app's
  state, presets and kits (`SetState.values`), the MIDI controller map (`ControllerMap`). A value
  for an identifier this version lacks is ignored; a parameter the saved state lacks keeps its
  value (AU pads, controllers) or takes its program's (presets, kits).

After a first release a run **may**: append instrument knobs at the end of the instrument block
(new IDs `kNumKnobs`, …), add LFO or VEL targets (new amounts, new IDs), add sections, programs
(at the end of `kPrograms`, whose index presets and projects keep) and change defaults (its own
knobs' and those of `kPlatformDefaults`), ranges or the kit. It **may never**: rename an
identifier, remove or reorder knobs, change the platform block (`PlatformParams.h`), or change
what an ID names. Tests `AudioUnitTests.stableParameterIDs`,
`.stateFromAnotherTable`, `.statePadValuesByIdentifier`, `.stateControllersAreChecked` and
`KitTests.kitFromAnotherTable` hold this.

**What a run writes in `Params.h`** (the shapes are in `PlatformParams.h`):

| Name | What it is | The contract |
|---|---|---|
| `enum InstrumentKnob` | the knobs, the first `= kNumPlatformKnobs`, then `kNumKnobs` | only ever appended to after a release; fewer than 1000 knobs in all |
| `kInstrumentKnobs[]` | one `Param` per knob, made with `floatKnob`, `logKnob`, `levelKnob`, `intKnob`, `choiceKnob` | identifiers lowercase ASCII letters and digits, unique; every knob a controller of its own, unreserved, none the platform's (5, 7, 10, 102-112): General MIDI's for the thing, else 14-31, 85-90, 113-119 |
| `kLfoTargets[]` | the knobs an LFO may move | continuous knobs, each once; must hold `kVolume`, `kPan`, `kTune` |
| `kVelTargets[]` | the knobs the velocity may move | every continuous instrument knob, and `kVolume`, `kPan`, `kTune`, `kLfo1Rate`, `kLfo2Rate`; never `kVelSens` |
| `kModWheelTargets[]`, `kAftertouchTargets[]` | `{ param, depth }`: what the wheel moves on a keyboard voice, `depth` the part of the knob's travel at the top | continuous knobs, depth in (0, 1]; `{ kNoTarget, 0 }` for none |
| `kPlatformDefaults[]` | `{ platform knob, plain value }`: the instrument's own default of a platform knob (Voice Mode, Glide, Bend Up/Down, …), from the spec's playing style; `{ kNoTarget, 0 }` for none (Tone) | the only way an instrument changes a platform default: `ParamTable.h` puts it into the platform block (`kPlatformBlock`), so the table's default (`{{APP_C}}_param_info`), a fresh engine's sets, the programs (which start from the defaults), the Audio Unit's parameters, "reset to default", presets and the panel all agree; a platform knob each, once, in its range; the default kit sets none of them; `ParameterTableTests`, `EngineTests.freshEngineDefaults`, `AudioUnitTests.freshUnitDefaults` |
| `kSections[]` | `{ name, { knobs… } }`, in the order shown; Master (the platform block) follows | every instrument knob in exactly one; at most 16 a section (`kMaxSectionKnobs`) |
| `enum ProgramIndex`, `kPrograms[]` | `{ name, { { param, plain value }… } }`: the defaults with up to 16 overrides (`kMaxProgramOverrides`) | at least two (the platform tests load the last); a program never sets Octave; `kPrograms[0]` has no overrides (a fresh set holds the defaults and names program 0, which the Audio Unit shows as its preset: `ParameterTableTests.firstProgramIsTheDefaults`) |
| `kDefaultKit[16]` | `{ program, note, group, { overrides… } }` per pad, up to 4 overrides (`kMaxKitOverrides`) | valid programs, notes 0-127, groups 0-16 (0 = Off) |
| `kTestSound[]` | `{ knob, plain value }`: the instrument's own knobs as the platform's tests play it, over the defaults; `{ kNoTarget, 0 }` for none (Tone) | with these values the voice sounds at `Knobs::hz(note)` steadily (no vibrato, pitch envelope, drift or detune of its own), for at least half a second while a key is held, and is over within 1.5 s of its note-off; so every such pitch movement and every longer release must be reachable by a knob. Only instrument knobs, each once, in range. Only tests read it (`{{APP_C}}_test_sound_*`, `TestKnobs.testSound`); see "What the platform's tests assume" below |
| `kRehitContinues` | a note-on on a sounding voice (same key, or a pad of the same group): `true` continues it (`start(…, continuing = true)`), `false` fades it out in 3 ms and starts a fresh one | |
| `kOutputLevel` | the voice's units to the engine's | set by the fullest gesture of the playing style (a full chord or strum for a polyphonic instrument, one note for a mono one, the default kit's busiest bar for a rhythmic one): at full velocity and Volume 0 dB it peaks just under the knee of the output stage, 0.6 (above it the limiter bends the peaks). Tone: a four-note chord under 0.57, one note 0.14 (-17 dBFS); `InstrumentTableTests.fullestGesture`, `.level` |
| `kTailSeconds` | the longest a voice sounds after its note-off, worked out from the knobs' ranges (Tone: Release's top × 100/60) | the Audio Unit's tail time (`{{APP_C}}_tail_time`); `InstrumentTableTests.tail` measures it |

**What a run writes in `Voice.h`**: `struct Voice`, default-constructible, with exactly the four
calls the engine makes (no allocation, lock or I/O in any):

- `void start(const Knobs& knobs, int note, float velocity, bool continuing)`: a note-on.
  `knobs` (`ParamTable.h`) stays valid while the voice sounds and the engine updates it before
  every `render`: plain values in table order (`knobs[kAttack]`), moved by the voice's LFOs, the
  hit's velocity and, on a keyboard voice, the wheels; `knobs.bend` in semitones; `knobs.rate`
  the voice's rate (twice the host's below 88.2 kHz). `knobs.hz(note)` is the note's frequency
  with Octave, Tune and the bend. `velocity` is 0…1; the engine already applies Vel Sens and
  VEL>Volume to the level. `continuing` is true only when the note-on takes over this voice
  while it sounds (`kRehitContinues`; in Legato a note played while another key is held; in Mono
  and Legato the return to a key still held): go on at the new `note` without a new attack. What
  continuing sounds like is the instrument's; when it is asked for is the platform's.
  `knobs.glide` is how far, in semitones, the pitch still is from `note` while it glides;
  `knobs.hz` adds it as it adds the bend, so a voice that takes its pitch from `hz` glides.
  **Random numbers**: the engine gives a fresh voice no seed (it default-constructs one per
  note). A voice that draws random numbers owns its generator, a `std::mt19937` member, seeds it
  with `kVoiceSeed` here when `continuing` is false, and draws through `uniform()` and `white()`
  (`VoiceRandom.h`, platform). A continuing start goes on in the same stream. No other source
  (a generator shared between voices, a clock, a count of hits): two equal notes render equal
  samples, which `ModulationTests.lfoHitRepeats` and the regression references need. The
  listening prototype's harness (`scripts/spike_harness.h`) has the same constant and the same
  two functions (`tests/test_harness_copies.py` holds them together), and its voices are seeded
  the same way, so a prototype's voice is ported draw for draw.
- `void release()`: the note-off of its key or pad.
- `void render(float* out, int frames)`: the next 1 … 16 mono samples, written (not added).
- `bool finished() const`: true once the voice is silent for good; the engine frees it.

The platform does around the voice: the voice pool (16 sounding, steal the quietest by a peak
follower, 3 ms fade), keys, pads and groups (one voice a group), the voice modes, Glide and the
sustain pedal (below), Volume, Pan, Vel Sens,
VEL>Volume, the LFOs and VEL amounts on every target, the wheels by the instrument's tables,
pitch bend by Bend Up/Down, the half-band 2x stage, `kOutputLevel`, the limiter, sample-accurate
MIDI, MIDI learn, the Audio Unit and its state. Code stays under `#pragma clang fp contract(off)`
and uses `std::exp2` for powers of two, so that debug and release builds render the same samples.

**Melodic playing** (`__APP__Engine.cpp`, platform; `VoiceModeTests`). In keyboard mode, by the
keyboard set's Voice Mode:

- *Poly*: a voice per key, as before (a re-hit as `kRehitContinues` says).
- *Mono*: one voice, last-note priority. Every new note attacks anew (`continuing = false`, a
  fresh voice; the one it replaces fades out in 3 ms), whatever `kRehitContinues` says. Letting
  the newest key go returns the voice to the newest key still held with `continuing = true`, so
  the return is heard as the same note moving, not a new one (and it glides); letting the last
  key go releases the voice.
- *Legato*: as Mono, but a note played while another key is held takes the voice over with
  `continuing = true`; a note played with no key held (a sustained or releasing voice is not a
  key) attacks as in Mono.
- A legato note and a return keep the voice's velocity and LFOs (they are not new hits).
- *Glide* moves the pitch from where the voice was (its note plus what is left of a glide) to the
  new note in exactly Glide ms, at an even number of semitones per second, i.e. exponentially in
  Hz, a control tick (16 internal samples) at a time, through `knobs.glide`. Mono glides at every
  note while its voice still sounds (held, sustained or releasing), Legato only between notes that
  overlap, both on a return. Glide 0, Poly and the pads never glide.
- The keys held are a stack of 16 per engine (a fixed array, no allocation; a key pressed again
  moves to the top, the oldest falls out of a full stack), kept in every voice mode, so a mode
  changed while keys are down finds them. Voices sounding when the voice mode changes keep to
  their note-offs, so none hangs.
- The *sustain pedal* (CC 64, down from 64 up, reserved: no knob or learn takes it) holds a key's
  voice that its note-off would release, in every voice mode; the pedal coming up releases those
  whose keys are up, exactly as their note-offs would have then. In Mono the stack decides the
  pitch: a key let go while others are held still returns, the pedal only holds the last note.
  The pedal holds no pad (a pad is a key press, released by its own note-off).
- All Notes Off (123), All Sound Off (120) and Reset All Controllers (121) put the pedal up
  (releasing what it held) and empty the stack; reset does too.
- Pads ignore the voice mode and Glide (a pad is a frozen key press; groups keep their own voice).
  Pitch bend works in every mode.
- A note-off finds only voices not yet released; one for a key the stack does not hold changes
  nothing.
- The probe (`{{APP_C}}_voice_probe`, `{{APP}}VoiceProbe`): fresh and continuing starts and releases
  since creation, the keys' voices not released and those the pedal holds, the stack's size, the
  mono voice's note and glide, as of the last block. Relaxed atomics, published at the end of
  `process`; for tests and diagnostics, so that the platform tests need no ear for the instrument.

**The listening prototype's harness plays by the same rules.** `scripts/spike_harness.h` is the
engine's voice pool again, rule for rule and number for number (the re-hit, Poly / Mono / Legato,
the glide a control tick of 16 samples at a time, the sustain pedal, the bend, Vel Sens, sixteen
voices with the quietest stolen and a 3 ms fade, pads and groups), with a `Voice` of the same
four calls. `Tests/__APP__Reference/` holds a copy of it (the template's is the skill's own, byte
for byte; a run's is the copy its approved renders were played with) and the prototype's voice
behind a C interface, so `PrototypeEquivalenceTests` compares the engine with what the user
heard, playing rules included: Tone's nine scores (a melody, chords, re-hits, held notes, the
kit, Legato with glide, Mono with glide and returns, the pedal, the bend) come out at -133 to
-149 dB. A change to the engine's playing rules is a change to the harness as well, or that
suite fails.

**What the platform's tests assume.** The platform's tests (the table of tests below: all but
the instrument's) know no knob of the instrument by name. They address knobs by identifier from
the platform block or by position among the instrument's (`TestKnobs.first`, the first
instrument knob, moved only through its controller or to a place on its travel, so it may be a
switch; `TestKnobs.programKnob`, a knob the last program sets apart from the first;
`TestKnobs.freeControllers`). What a VEL or an LFO amount does is measured on platform knobs
every instrument has as targets (`veltune`, `velvolume`, `lfo1tune`, `lfo2pan`).

Their engines come from `makeEngine`, and the pads' sets from `PadTests.makePads`, which put the
**plain sound** into a set over the table's defaults (`TestKnobs.plainSound`): the platform's own
playing style (the knobs of `kPlatformDefaults` back at the platform's, `TestKnobs.platformStyle`)
and the instrument's **test sound** (`kTestSound`, `TestKnobs.testSound`). A test that loads a
program afterwards puts the plain sound back. On the plain sound the tests assume, and a run must
keep true:

- at least two programs;
- a voice that sounds at the note's pitch (`Knobs::hz`), steadily (pitches are read to 0.1 %),
  for at least half a second while its key is held, and follows `hz` while the bend, Tune or the
  glide move it;
- a voice released by its note-off and over (`finished()`) within 1.5 s of it (two notes 2.1 s
  apart must not overlap), and, at any knob setting, within `kTailSeconds`;
- two equal notes render equal samples (the rule for random numbers above);
- one note at full velocity peaks between 0.02 and the knee, 0.6, so that renders add and scale
  exactly under Volume -12 dB;
- no velocity in the voice's level beyond what a note of the same velocity has (the VEL>Volume
  and Vel Sens tests compare notes of equal velocity).

That is why every pitch movement of the voice's own and every release longer than 1.5 s must be
reachable by a knob: `kTestSound` turns it off, the default sound keeps it. A platform test that
fails in a run means the instrument breaks one of these, never that the test is to be changed.
Only the tests of the defaults (`ParameterTableTests`, `EngineTests.freshEngineDefaults`,
`AudioUnitTests.freshUnitDefaults`) read the instrument's own defaults; the tests on the Audio
Unit and on `Synth` play the default sound but measure no pitch and wait for no silence, and set
Poly themselves where they need a voice per key. The instrument's tests make their engines with
`makeDefaultEngine` (the instrument as it ships). What the platform decides (a fresh or a
continuing start, a release, what the pedal holds, the note the voice of Mono and Legato plays
and how far its glide has to go) is read from the engine's probe (`{{APP_C}}_voice_probe`), a
sound is compared with the same notes played another way, and a pitch is measured within 0.6 s
of the event that sets it.

Checked by running the whole suite, debug and release, with stand-ins for Tone; only the
instrument tests (`PrototypeEquivalenceTests`, `SoundRegressionTests`, `InstrumentTableTests`,
`ReferenceTests`) fail there, no platform test:

- an organ-like voice (no decay while held), Release 1.2 s, and a pluck (Decay 0.3 s);
- Tone given the defaults of platform knobs Legato, Glide 120 ms, Bend Up 12, Octave -1,
  Vel Sens 40 and LFO 1 Rate 3 Hz;
- a 15-cent vibrato at 5.5 Hz in the voice behind a knob that defaults on and is 0 in
  `kTestSound` (without the entry 11 platform tests fail, in `EngineTests`, `ModulationTests`
  and `VoiceModeTests`);
- Release defaulting to 2.0 s, 0.3 s in `kTestSound` (without the entry the two LFO Start tests
  of `ModulationTests` fail);
- a switch as the first instrument knob;
- the last three at once.

**Also the instrument's**: `SectionLayout.plans` and `PanelLayout.plannedRows`
(`Sources/__APP__Core/SectionLayout.swift`), `Artwork.swift`, `Resources/AppIcon.png`,
`Resources/Art/*`, and the site's and manual's bodies.

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
| `scripts/check_site_links.sh` | platform | lists every local file the pages and styles under `docs/` link (`src`, `href`, CSS `url()`) that is missing; the release gate (`site links ok`) |
| `CHANGELOG.md` | platform | `## Unreleased` |
| `README.md` | platform | name, tagline, build commands, licence |
| `CLAUDE.md` | platform | project rules; its first line is `{{TAGLINE}}`; where the instrument lives; no `FILL:` left at a release |
| `development_workflow.md` | platform | toolchain, build, auval, icon, distribution, phases 01–06; 0.1.0 until the first release, 1.0.0 |
| `.claude/skills/release/SKILL.md` | platform | the release procedure (below) |
| `.planning/ROADMAP.md`, `.planning/STATE.md` | platform frame, instrument rows | the run's phases 01–06 with `FILL` comments for what each made |

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
| `Sources/__APP__DSP/include/__APP__DSP.h` | platform | C interface to the engine (and, for tests, its probe, `{{APP_C}}_voice_probe`, the list of the instrument's defaults of platform knobs, `{{APP_C}}_platform_default_*`, and its test sound, `{{APP_C}}_test_sound_*`) |
| `Sources/__APP__DSP/__APP__Engine.cpp` | platform | voice pool, voice modes, glide, sustain, pads, sets, LFOs, VEL, wheels, MIDI, oversampling, limiter; names no instrument knob |
| `Sources/__APP__DSP/PlatformParams.h` | platform | `Param`, the platform block with the platform's own defaults, the shapes of the instrument's tables (`PlatformDefault` among them) |
| `Sources/__APP__DSP/ParamTable.h`, `ParamTable.cpp` | platform | the whole table put together (the platform block with the instrument's `kPlatformDefaults`, `kPlatformBlock`), `Knobs`, the seam's `static_assert`s |
| `Sources/__APP__DSP/Params.h` | instrument | the instrument's knobs and tables, its test sound among them (§"The instrument seam") |
| `Sources/__APP__DSP/Voice.h` | instrument | the instrument's voice from the approved prototype |
| `Sources/__APP__DSP/VoiceRandom.h` | platform | a voice's random numbers: `kVoiceSeed`, `uniform()`, `white()`, the same as the prototype harness's |
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
| `Sources/__APP__Core/SectionLayout.swift` | platform, its `plans` and `PanelLayout.plannedRows` instrument | placement of a section's controls and of the cards; a run writes the plans of its sections and the rows of its cards (both empty: everything flows) |
| `Sources/__APP__Core/StandaloneSettings.swift` | platform | MIDI source, audio output choices |
| `Sources/__APP__Core/Synth.swift` | platform | the Swift wrapper over the engine |
| `Sources/__APP__Core/SynthState.swift` | platform | saved knob sets |
| `Sources/__APP__UI/Artwork.swift` | instrument | the panel's images, their bounds and palette (template: no images, system colours) |
| `Sources/__APP__UI/HeaderView.swift` | platform | emblem, wordmark, menus, mode, LFO/VEL/MIDI |
| `Sources/__APP__UI/InstrumentModel.swift` | platform | what the panel needs from its owner |
| `Sources/__APP__UI/InstrumentPanel.swift` | platform | the panel |
| `Sources/__APP__UI/KeyboardStripView.swift` | platform | three octaves of keys |
| `Sources/__APP__UI/KnobEdit.swift`, `KnobView.swift` | platform | knobs and their edits |
| `Sources/__APP__UI/LibraryMenuView.swift`, `NameSheetView.swift` | platform | file menus, Save as… |
| `Sources/__APP__UI/ModeFooterView.swift` | platform | keyboard / pads footer (`FigureView`: the instrument's figure where the art has one) |
| `Sources/__APP__UI/PadGridView.swift`, `PadInspectorView.swift`, `SendToPadView.swift` | platform | pads |
| `Sources/__APP__UI/SectionView.swift` | platform | one section's card |
| `Sources/__APP__/*.swift` (`__APP__App`, `AppModel`, `AudioOutput`, `ContentView`, `MIDIInput`, `SettingsView`, `UpdateService`) | platform | the standalone app |
| `ThirdParty/AudioUnitSDK/**` | platform | Apple's AudioUnitSDK (Apache-2.0), vendored unchanged |

### Tests

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `Tests/__APP__Reference/__APP__Reference.cpp`, `include/__APP__Reference.h` | instrument | the approved listening prototype as a C++ reference: its voice, played by its harness, behind a C interface (parameter sets, a playing style, events as MIDI gives them, the engine's decimator); template: Tone |
| `Tests/__APP__Reference/spike_harness.h` | instrument | the harness the prototype's renders were played with, unchanged: a run copies its spike folder's (template: the skill's `scripts/spike_harness.h`, byte for byte) |
| `Tests/__APP__CoreTests/PrototypeScores.swift` | instrument | the prototype's programs, scores (notes, pedal, bend; the playing style as knobs) and reference render calls |
| `Tests/__APP__CoreTests/PrototypeEquivalenceTests.swift` | instrument | engine vs prototype for every score, at 96 and 48 kHz (residual < -60 dB) |
| `Tests/__APP__CoreTests/SoundRegressionTests.swift` | instrument | fingerprints taken from the new engine (template: two) |
| `Tests/__APP__CoreTests/ListeningRenders.swift` | instrument | renders of the instrument for the ear |
| `Tests/__APP__CoreTests/Grooves.swift` | instrument | scores over the instrument's default kit |
| `Tests/__APP__CoreTests/ReferenceTests.swift` | instrument | the reference renders its own scores |
| `Tests/__APP__CoreTests/InstrumentTableTests.swift` | instrument | the instrument's knobs, controllers, targets, wheels, sections, programs, kit, tail, the fullest gesture under the limiter's knee, the level of one note |
| `Tests/__APP__CoreTests/EngineHarness.swift` | platform | engine test helpers and measures; `TestKnobs` (the platform block and its own defaults, `platformOwn`; the instrument's defaults of platform knobs, `platformDefaults`; its test sound, `testSound`; the instrument's knobs by position); `makeEngine` plays the plain sound (`plainSound`: the platform's own playing style and the test sound), `makeDefaultEngine` the instrument as it ships |
| `Tests/__APP__CoreTests/EngineTests.swift` | platform | engine promises for every instrument |
| `Tests/__APP__CoreTests/ParameterTableTests.swift` | platform | table invariants: the platform block (with the instrument's defaults of platform knobs), order, amounts, sections, the first program the defaults, the test sound |
| `Tests/__APP__CoreTests/ModulationTests.swift`, `ControllerTests.swift`, `PadTests.swift` | platform | LFO/VEL (on Tune, Volume and Pan), controllers, pads (the pad VEL test, on VEL>Volume, included) |
| `Tests/__APP__CoreTests/VoiceModeTests.swift` | platform | Poly, Mono, Legato, Glide, the sustain pedal, the resets, the stack's edges (16 keys, a key twice, a key not held), mode changes with keys and pedal down, pads unaffected, the AU state keeping Voice Mode and Glide; on the engine's probe |
| `Tests/__APP__CoreTests/AudioUnitTests.swift`, `AudioUnitWindowTests.swift` | platform | the AU in-process, its window model |
| `Tests/__APP__CoreTests/SectionLayoutTests.swift` | platform | placement with made-up plans over the platform block (through the internal `SectionLayout.of(_:plans:)`, `PanelLayout.of(_:plannedRows:)`, `PanelLayout.widths(…plans:)`) and without plans |
| `Tests/__APP__CoreTests/ThreadTests.swift` | platform | audio-thread rules |
| `Tests/__APP__CoreTests/` `__APP__CoreTests`, `AppModelLogicTests`, `KeyboardLayoutTests`, `KeyStripTests`, `KitTests`, `KnobEditTests`, `LibraryMenuTests`, `NotesTests`, `PadPanelTests`, `PresetFileTests`, `PresetLibraryTests`, `PresetShelvesTests`, `StandaloneSettingsTests`, `SynthStateTests`, `SynthTests` | platform | the platform's logic |

What the platform tests assume of every instrument, and how they stay independent of it, is
§"The instrument seam", "What the platform's tests assume".

### Website (`docs/`)

| File | Kind | What it is / what a run puts there |
|---|---|---|
| `docs/.nojekyll` | platform | Pages serves files as they are |
| `docs/appcast.xml` | platform | empty Sparkle feed; `build.sh dist` writes it |
| `docs/assets/site.css`, `manual.css` | platform | shared styles |
| `docs/index.html`, `docs/cs/index.html` | platform frame, instrument body | head, nav, the platform's three feature cards, download, footer stay; a run writes the first and third cards and a sentence of the second, and makes the images |
| `docs/manual.html`, `docs/cs/manual.html` | platform frame, instrument body | the platform's chapters stay written out (window, header, Master, keyboard mode, voice modes, glide and sustain, pads and groups, Send to pad, presets, kits, LFO/VEL amounts per pad, MIDI controllers and learn, Settings, the Audio Unit, updates); a run writes the sections of its knobs, its programs, its kit, its wheels and re-hit, the numbers that follow from `Params.h`, and the screenshots' marks |
| `docs/assets/*.png`, `docs/assets/*.jpg`, `docs/assets/manual/*` | instrument | screenshots, hero, icon, ornament (absent in the template) |

## Texts: FILL markers

What a run writes is marked where it goes, by an HTML comment (`<!-- FILL: … -->` in HTML and
Markdown, `/* … FILL: … */` in `site.css`) that says what goes there and from which source: the
research report, the spec, `Params.h` (`kSections`, `kInstrumentKnobs`, `kPrograms`,
`kDefaultKit`, `kLfoTargets`, `kVelTargets`, `kModWheelTargets`, `kAftertouchTargets`,
`kRehitContinues`), `Voice.h`, the approved look, a real-app screenshot captured by PID. A FILL
in running text sits where its words go, so the sentence around it reads on. The Czech pages hold
the same tags in the same order as the English ones, their FILL comments included (each asks for
the English page's content in Czech). The figures keep their marks with placeholder coordinates;
the FILL above each says what the screenshot shows and that the marks are measured on it. A
release has none left (`CLAUDE.md`; the release skill's step 1 checks `grep -rn "FILL:" docs
.planning/ROADMAP.md .planning/STATE.md`; plans and specs are the run's own and are not checked).
The standing rules of `ROADMAP.md` and `STATE.md` (status marks, what an entry holds) are plain
text, not FILL, so they stay.

| File | FILL comments | What they ask for |
|---|---|---|
| `docs/index.html`, `docs/cs/index.html` | 6 each | the page's images (one comment), the first and third feature cards, what "synthesized" lets the instrument do |
| `docs/manual.html`, `docs/cs/manual.html` | 36 each | the contents' and the panel's section names, what the instrument is, the programs, each section of knobs, Master's defaults that `kPlatformDefaults` sets, re-hit and start-only knobs, the wheels, groups and the default kit, the LFO/VEL target lists, the knobs centred on 0, the standard and free controllers, the Audio Unit's parameter counts, each figure's screenshot and caption |
| `docs/assets/site.css` | 1 | the approved site look's palette, display font and button (the template's is a neutral dark one) |
| `.planning/ROADMAP.md` | 6 | file names of the report and the spec, what phases 02–05 made |
| `.planning/STATE.md` | 4 | the research, prototype and spec entry (date, file names, approval date) |

Checked by rendering (`Zkušebník Test`) and opening the four pages in headless Chrome
(Playwright 1.65.1, its Chromium 1255) at 1440 and 400 px: no page is wider than its viewport, the
in-page anchors all resolve, no script error, and the English and Czech pages have the same
sequence of elements and FILL comments (87 for the overview, 720 for the manual; the Master
defaults' FILL came later, at the same place in both languages). The only failed
requests are the images a run makes: `assets/icon.png`, `assets/hero-<app>.jpg`,
`assets/<app>-window.png`, `assets/ornament.png` and the ten `assets/manual/*.png`.
`scripts/check_site_links.sh` lists exactly these in the rendered template and nothing once they
are there (`verify_template.sh` checks both).

## The release skill

Fanfrnoch's procedure, renamed, with these changes: the first release is 1.0.0 (the skeleton
carries 0.1.0, which step 1 replaces in the site with every other old version); step 1 also checks
that no `FILL:` is left and that every file the site links exists (`scripts/check_site_links.sh`;
a figure whose picture cannot be made is taken out of the English and the Czech page alike and
named in the push question, never shipped broken); the steps the Bash sandbox breaks (signing,
notarization, the keychain, the component's copy for `auval`, the window capture) run with it
disabled, and a signing piece counts as missing only when its check fails that way; `auval` runs
on the component that ships; the catalog is split as design
§5 says: its entry is written into `projects.json` of a fresh clone of
`{{OWNER}}/{{OWNER}}.github.io` by a text edit (never a JSON rewrite) and committed locally before
the push question, and the `update-catalog` build check and push run after publishing and the live
checks. The one bold push question names every outward action of the first release in order
(create the public repo, push the tag, the GitHub Release with the DMG, `curl` the DMG for 200,
push `main`, turn on Pages, push the catalog entry or, when it is unchanged, start the catalog's
rebuild); a later release names only what is not so already. The question is asked in the run
itself, every time: an earlier yes in the conversation never stands in for it, and it is the
one confirmation the user's global push rule asks for. Step 3 starts the
app for its screenshot only when the default output's transport is `Built-in` (the rule of
`scripts/verify_template.sh`), by the path of its binary with its PID kept (never `open`);
otherwise the old screenshot stays and the capture is recorded
under "Not verified"; a capture a locked screen prevents waits for the user, right before the
push question. The catalog step stops and asks when
the repo is in the catalog's `exclude` list; publishing adds `origin` when the repo exists but the
clone has none.

## Taglines

`TAGLINE` and `TAGLINE_CS` are written unescaped into HTML attributes (`content="{{TAGLINE}}"`),
Markdown and a shell line (`gh repo create … --description "{{TAGLINE}}"` in the release skill),
and a run may put them into YAML, where `": "` breaks a plain value. They must not contain `"`,
`\`, `$`, a backtick or the sequence `": "` (colon and space); the skill's intake enforces it.
