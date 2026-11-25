# Pitfalls

Every "what went wrong" item of the three build reports (`~/Development/Claude/SHARED/`:
Fanfrnoch §13 = F, Brumle §13 = B, Didgeridoo §14 = D) as a guard, by the step it belongs to. The
table at the end maps each item to its guard and to the file that carries it.

## Intake (step 0)

- The workspace folder is never renamed, moved or deleted by the skill. A name the user corrects
  at intake changes the identity only (`identity.py "<parent>/<corrected name>"`); the folder keeps
  its name until the user renames it after the run. (F7)
- Identity and parameter table are fixed once, in the spec, after the ear and before the first
  build. Before 1.0.0 nobody has saved a sound, so nothing is kept "compatible" before it; after
  it, only appending (`TEMPLATE_MANIFEST.md` "Stable IDs"). (D3)

## Research and prototype (steps 1–2)

- No product code before the user has approved renders laid next to real recordings: research,
  then the spike, then the gate. (D1)
- Renders include long tails and quiet passages; before anything is sent every tail is measured
  falling, not flat (two windows from the file's end; `tail.centroidHz` for hiss), and the
  `S…_silence_*` renders, where the voice is over, reach -80 dBFS or below (-200 passes). (B3)
- The analyser finds the pitch first and reads harmonics at that pitch, never at the key's
  nominal pitch; numbers that look too good are checked again. (D12)
- The same aspect rejected twice: stop tuning; ask for a reference the user finds right, or offer
  to drop it. (D4)
- A feature whose sound the user has not approved gets no UI; a rejected feature is removed with
  its knobs, programs and controls. (D6)

## Spec and engine (step 3, phase 02)

- Identifiers are unique across knobs and amounts (`lfo1<id>`, `lfo2<id>`, `vel<id>` included):
  `ParamTable.h`'s `static_assert`s and `ParameterTableTests`. (F4)
- Debug and release render the same samples: `#pragma clang fp contract(off)`, `std::exp2`, and the
  suite in `swift test` and `swift test -c release` in every phase. (F5, D11)
- Numbers in a plan or spec are starting points: measure, deviate, and write the deviation with
  its measurement into `VERIFICATION.md`. (B4)
- TSan (`swift test --sanitize=thread`) in every phase that touches threads; a fix for vendored
  code goes in front of it, never into it. (D16)
- The engine equals the approved prototype (< -60 dB). A change to the approved sound is made in
  the spike, the reference and the engine alike, keeps the approved renders up to where the flaw
  starts, and is named "measured, not heard" in the final report and in the push-question message,
  so the user can listen before saying yes. (D2)

## Codex (phases 03, 05)

- `codex exec … < /dev/null` always; check `pgrep -fl "codex exec"` and `codex.log` when a job runs
  much longer than its siblings. (F1)
- `--add-dir ~/.codex/generated_images` and "do not stop to ask questions" in the command and the
  prompt; a stuck job is killed and re-run once, then recorded and replaced by the fallback. (B1)
- Wait on `-o last-message.txt`, not on the process; kill the leftover wrapper ("exit 144" is
  that kill). (B2)

## Panel, app, Audio Unit (phase 04)

- Decorative art never takes a click (`allowsHitTesting(false)`); every control is hit-tested on
  the real view hierarchy (AX element at its position, own PID). (B6)
- After a hit-testing fix, test the whole control again, spot by spot, for what each spot does. (D5)
- Saved files are untrusted input: tests for missing fields, unknown fields, out-of-range numbers
  and non-JSON in presets and kits. (B7)
- State shared between the AU's host thread and its window is locked or atomic; every AU custom
  property is a review focus; TSan. (B8)
- Pictures come from the real window (`capture_window.swift`, or `CGWindowListCreateImageFromArray`
  from inside the app under a locked screen), never from `ImageRenderer`. (B5)
- A phase whose main control was never seen is not merged as done: build the AX drive in the
  phase; if the environment refuses it, it is the first "Not verified" line and named in the
  final report. (D10)
- Stand-ins carry the release's `LC_BUILD_VERSION` (`vtool -show-build`, `-set-build-version`,
  ad-hoc `codesign`). (D7)
- The website's and the manual's window pictures come from the real app or from a stand-in proved
  pixel-equal to it; any other is labelled. (D8)
- The real app may not be startable (default output not built-in, a copy running): plan the
  stand-in from the start and say which picture is which. (D9)

## Icon and website (phase 05)

- The icon is opaque full-bleed 1024 art compiled by actool from the Icon Composer document, never
  `iconutil` from art with transparent corners; checked with `NSWorkspace.icon(forFile:)` on an
  absolute path. (B9)

## Release (phase 06)

- First-release notes describe what the user gets, never changes between unreleased builds; the
  appcast is written by `build.sh dist` from that section. (B10)
- The catalog's `projects.json` is edited as text, never rewritten by `jq` or a JSON library. (B11)

## Any phase: the user's machine

- Capture only `screencapture -x -o -l <window id>` of a window of a process this run started,
  options before the path (`capture_window.swift`); a wrong capture is deleted unopened and
  reported. (F2, D15)
- No keystrokes, no clicks through System Events, no activation: AX actions on the own PID only.
  (F3)
- Nothing needs the front: typing is tested in a hidden-window harness; what would need the front
  is "Not verified". System daemons are never restarted for a clean-up. Anything that could
  disturb the user is said before it is done, not after. (D14)
- Helpers and stand-ins leave settings files: `defaults delete <name>`, the plist removed,
  `~/Library/Preferences` compared before and after. (D13)
- The leftover-words check runs at the end of every phase, with the run's words file. (F6)
- Every `VERIFICATION.md` ends with "Not verified" in plain words (ear, hand, real host, device,
  Safari and phone, refused steps, stand-in pictures); the final report repeats it. (F8, B12, D17)

## Guards of the template (not from the reports)

- `check_leftovers.sh`'s list holds the source instrument's words (`drum`, `stick`, `skin`, …): an
  instrument whose own words are in it uses a copy without them (`phases.md`).
- The list does not hold the placeholder engine's words: after phase 02,
  `grep -rn 'kProgramTone\|"Soft Tone"' Sources/<APP>DSP Tests/<APP>Reference docs` → nothing.
- A fresh instance starts on the table's defaults: `kPrograms[0]` has no overrides; a playing
  style other than Poly / Glide 0 / Bend 2 lives in the other programs (`spec-template.md` §7).
- `scaffold.py` refuses a non-empty target: render into the scratchpad and copy in (`phases.md`).
- Taglines hold no `"`, `\`, `$`, backtick or `": "` (`TEMPLATE_MANIFEST.md` "Taglines").

## Mapping

| Item | What went wrong | Guard (short) | Where |
|---|---|---|---|
| F1 | Codex hung on stdin | `< /dev/null`; `pgrep`, log | `codex.md` Invocation |
| F2 | Full-screen screenshots (file name before options) | `-l` of own PID only, options first | `verification-kit.md` Screenshot protocol; `phases.md` constraints |
| F3 | Stray Escape keystroke via System Events | no keystrokes or activation; AX on own PID | `verification-kit.md`; `phases.md` constraints |
| F4 | Parameter ID collision (`veltune`) | unique identifiers, asserted and tested | `spec-template.md` §6; template `ParamTable.h` |
| F5 | Debug and release rendered different samples | fp contract off, exp2, both configs | `phases.md` constraints and merge checks |
| F6 | Old instrument's words leaked | leftovers check every phase, run's words file | `phases.md` Every phase |
| F7 | Session started in a misspelled folder | never touch the folder; corrected name changes identity only | step 0 (SKILL.md); here |
| F8 | Never verified by a human | "Not verified" in every VERIFICATION.md and the report | `verification-kit.md`; `release.md` report |
| B1 | Codex asked a question (generated_images) | `--add-dir`, "do not stop", watch log, one re-run | `codex.md` Invocation |
| B2 | Codex wrapper stayed alive | wait on `last-message.txt`, kill wrapper | `codex.md` Invocation |
| B3 | Hiss in the tails only the ear found | tails in renders, tail floor measured | `prototype.md` Measuring; `phases.md` phase 02 task 6 |
| B4 | Plan's numeric caps wrong | measure, deviate, record | `phases.md` constraints |
| B5 | Locked screen; `ImageRenderer` lies | real window, in-app capture fallback | `verification-kit.md` Screenshot protocol |
| B6 | Decorative art swallowed clicks | `allowsHitTesting(false)`, AX hit test | `phases.md` phase 04; `verification-kit.md` table |
| B7 | Damaged preset trapped on `Int32` | damaged/later file tests | `phases.md` phase 04 task 6 |
| B8 | AU host thread and window shared state without lock | lock/atomic, review focus, TSan | `phases.md` phase 04 review focus |
| B9 | Icon on a light plate | actool, opaque full bleed | `codex.md` Icon; `phases.md` phase 05 |
| B10 | First release notes had pre-release changes | notes = what the user gets | `release.md` Local part |
| B11 | Catalog JSON reformatted | text edit only | `release.md` Local part |
| B12 | Never verified by a human (incl. Sparkle update, MPC) | "Not verified" | `verification-kit.md`; `release.md` |
| D1 | Sound invented first, heard last | no product code before approved renders + references | `prototype.md`; step 2 |
| D2 | 1.0.0 carried an unheard sound | engine = prototype; any change "measured, not heard" before the push question | `phases.md` phase 02 task 7; `release.md` push question |
| D3 | Compatibility kept for a 3-hour-old release | identity fixed in the spec; nothing kept before 1.0.0 | `spec-template.md` (intro, §6) |
| D4 | Overblown note tuned three times | rejected twice → stop, reference or drop | `prototype.md` The loop |
| D5 | Hit-testing fix exposed hidden behaviour | press the whole control again | `phases.md` phase 04 task 3 |
| D6 | UI built for a feature that died | no UI for unapproved sound; remove rejected | `spec-template.md` After writing; `prototype.md` The loop |
| D7 | Stand-ins looked newer than the release | mark with `LC_BUILD_VERSION` | `verification-kit.md` Stand-ins |
| D8 | Stand-in title bar 4 pt taller | site/manual pictures real or proved equal | `verification-kit.md` Stand-ins |
| D9 | Real app could not be started | plan the stand-in, label pictures | `verification-kit.md` Before starting the real app |
| D10 | Phase merged with its main control never seen | AX drive in the phase; else first "Not verified" | `phases.md` phase 04 task 3 |
| D11 | Debug and release differed twice | both configs every phase | `phases.md` |
| D12 | Harmonics read at the key's pitch | pitch first (`analyze.swift`) | `prototype.md`; `research-briefs.md` recordings |
| D13 | Helper settings files left | `defaults delete`, plist removed, compare | `verification-kit.md` Clean-up |
| D14 | Stand-in came to the front; daemon restarted | nothing needs the front; no daemon restarts; say before | `verification-kit.md` |
| D15 | Whole-screen screenshots | `-l` of own PID only | `verification-kit.md` |
| D16 | Race in a vendored header found by TSan | TSan every phase; fix in front of vendored code | `phases.md` constraints |
| D17 | Never verified by a human | "Not verified" | `verification-kit.md` |

Adapted rather than carried over word for word: **D2** (Didgeridoo's "no release that changes the
sound before a listening round" would add a gate; here the approved prototype is the bar and every
later change reaches the user's ear through the push-question message), **D14** (its "batch what
needs the front into one run" becomes "nothing needs the front"), **F7** (the folder's name is the
identity, so a misspelling is corrected in the identity, never by moving the folder).
