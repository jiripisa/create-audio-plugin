# Verification kit

Claude cannot hear, cannot hold a mouse in the user's app and has no host. Every claim comes from
something that runs. Harnesses live in `<scratch>`, never in the repo; each `VERIFICATION.md` names
the ones it used. **A harness is evidence only for what it runs**: a stand-in is the app's model
and views, not the app.

## Who runs what, and where

- **The main session** starts the real app, captures windows, drives the app through AX and runs
  the scratch AU host, as it runs the Codex jobs. **A subagent does none of these**: it hands
  back a capture list (`phases.md` "Captures are the main session's") and gets the pictures back.
  Subagents run the tests, the hidden-window harnesses, `auval` and the site review.
- **With the Bash sandbox disabled from the start** (`dangerouslyDisableSandbox` on the call;
  SKILL.md "Outside the sandbox"): every capture and AX drive, the component's copy into
  `~/Library/Audio/Plug-Ins/Components` with its `auval` or host run and its removal, `codex exec`,
  headless Chrome, and anything that reads the login Keychain or signs. Inside the sandbox these
  fail in ways that look like something else ("could not create image from window", no signing
  identity found). Only a refusal of the request to disable the sandbox is final: the step is
  "Not verified". Everything else runs in the sandbox.

## What to show, and how (Didgeridoo's kit)

| What had to be shown | How |
|---|---|
| The audio output follows the hardware | The app's real `AudioOutput.swift` compiled with a stand-in synth. "A device is plugged in" is an aggregate device private to the process (`kAudioAggregateDeviceIsPrivateKey`) whose only sub-device, if any, is a built-in one (never the user's interface). Only silence is rendered |
| MIDI input survives devices coming and going | The real `MIDIInput.swift` against virtual sources (`MIDISourceCreateWithProtocol`). A replugged device is a new source with the old unique ID |
| A text field's behaviour | The view in an `NSHostingView` inside a window that is never shown, typed into through the field editor |
| The plug-in's window on the real unit | The template's tests register the Audio Unit inside the test process and drive it through the window's model (`AudioUnitWindowTests`) |
| The component in a host | The scratch AU host below |
| The app's window without sound | A stand-in app built from the real `AppModel`, `ContentView`, panel views and `SettingsView`, with stand-ins for `AudioOutput` and `MIDIInput`, captured by PID |
| A control does what it shows | AX actions (`AXPress`, menu items) on the own PID; the hit test: the AX element at each control's position (`AXUIElementCopyElementAtPosition` on `AXUIElementCreateApplication(pid)`) is the control, not the art |
| An open menu, a popover | The app or stand-in started in the background, driven through AX: press the menu, read its items and ticks, capture the menu's window (same PID) |
| The window as the released app draws it | The stand-in marked with the release's `LC_BUILD_VERSION` (below) |
| The icon as the system shows it | `NSWorkspace.shared.icon(forFile:)` with an **absolute** path (a relative one gives the generic icon), drawn into a bitmap |
| The website | Playwright screenshots at 1440 and 400 px (no browser installed by the run: without one it is "Not verified"); EN and CS compared tag for tag |
| The sound | `scripts/analyze.swift` on WAVs the engine wrote (`ListeningRenders`, a scratch program over `Synth`): pitch found first, then harmonics, levels, tails, strokes |

## Before starting the real app

The real app opens an audio stream on the default output. Start it only when all hold, else use
a stand-in (no audio) and say so:
1. `system_profiler SPAudioDataType`: the device with `Default Output Device: Yes` has
   `Transport: Built-in` (the rule of `scripts/verify_template.sh`). Never open a stream on the
   user's audio interface, never change the default output.
2. No copy of the app is running (`pgrep -x <APP>` empty): an installed copy shares the bundle id
   and the settings.
3. Its settings hold no chosen device: `defaults read <BUNDLE_ID>` fails or names none.
4. Settings put aside: `defaults export <BUNDLE_ID> <scratch>/prefs-backup.plist` when the domain
   exists (put back with `defaults import` afterwards), else `defaults delete <BUNDLE_ID>` after.
5. `ls -1 ~/Library/Preferences > <scratch>/prefs-before.txt`.

## Screenshot protocol

- Launch by path, in the background, and keep the PID:
  `"<proj>/build/release/<APP>.app/Contents/MacOS/<APP>" > <scratch>/app.log 2>&1 &` (`$!`). Never
  `open -a`, never `tell application "<APP>"`: they start another copy.
- `swiftc -O <skill>/scripts/capture_window.swift -o <scratch>/capture_window` once, then
  `<scratch>/capture_window <pid> <out.png> --wait 15`. It finds the window by
  `kCGWindowOwnerPID` and runs `screencapture -x -o -l <id>`; never `screencapture` without `-l`,
  and the options always before the file name. Exit 3: no window; 4: all black (a locked screen,
  file deleted); 5: `screencapture` gave no image (a locked screen, or it ran inside the sandbox,
  or a refusal). After 4 or 5 the capture is queued (below); no retry, no other way round.
- Never bring the app to the front, never send keystrokes, never click through System Events.
  AX actions only, on the own PID:
  `tell application "System Events" to tell (first process whose unix id is <pid>) to …`.
  Typing is tested in the hidden-window harness, not in the app. Nothing needs the front; when
  something seems to, it is "Not verified".
- Look at every capture (Read the PNG). A full-screen or foreign capture made by mistake is
  deleted unopened and reported.
- A locked screen has no way round: the window server gives no picture of a window then, and
  the old in-app way (`CGWindowListCreateImageFromArray`) is gone from macOS 27. Never
  `ImageRenderer` for the panel either: it draws no Liquid Glass and no menus, so its pictures
  lie. The capture waits (below).
- Quit: `kill <pid>`, wait up to 5 s, `kill -9` only if still alive.

## Queued captures

The build runs unattended, often with the screen locked. A capture that cannot be taken (exit 4
or 5, a refused request) is **queued**, not replaced: append a line to
`<scratch>/capture-queue.md` (the picture's file, the state it shows, the AX actions that reach
it, the phase, why it failed), name it in that phase's `VERIFICATION.md` under "Not verified",
and go on. The pages keep linking the file. (When only the default output stands in the way,
the stand-in of the next section is captured instead, and labelled.)

The main session empties the queue **when the user is back**: at gate 4, right before the push
question (the user is at the Mac to answer it). With a built-in default output it starts the
real app once (else the stand-in), takes every queued picture, looks at each, measures the
manual's marks on the new screenshots, commits them (`docs: screenshots of the app`), cleans up.
What still cannot be taken then (the request is refused) is handled by the release gate
(`release.md` "Before step 1"): its figure comes out of the pages, EN and CS alike, and the push
question says so. A release never ships a page with a broken picture, and never one drawn in
its place (`ImageRenderer`, a mock-up).

## Stand-ins marked as the release

A stand-in built with plain `swiftc` for the running system looks and behaves newer than the
release. Mark it as the release binary is:
1. `xcrun vtool -show-build <proj>/build/release/<APP>.app/Contents/MacOS/<APP>` → `minos`, `sdk`.
2. `xcrun vtool -set-build-version macos <minos> <sdk> -replace -output <standin> <standin>`, then
   `codesign -s - -f <standin>` (inside its `.app` when it is a bundle).
3. Proof: capture the real window and the stand-in's in the same state; count the differing pixels
   (a scratch Swift diff). Only a stand-in proved equal may make the website's or the manual's
   window pictures; otherwise each such picture is labelled "stand-in, not proved equal" in
   `VERIFICATION.md` and in the final report.

## Scratch AU host

A Swift program in `<scratch>/auhost/`, run by path by the main session with the sandbox disabled,
with the component installed only for the run (as for `auval`):
- `AudioComponentFindNext` for `aumu`/`<SUB>`/`JPis`, `AudioComponentInstanceNew`,
  `AudioUnitInitialize`; play a note (`MusicDeviceMIDIEvent`) and render blocks (`AudioUnitRender`)
  to check it sounds;
- `kAudioUnitProperty_CocoaUI` → the view factory → the view, in a window of this process (not
  activated), captured by its PID in both modes, before and after a parameter change
  (`AudioUnitSetParameter`), and with controllers passed on as a host does;
- close the window before disposing of the unit (the other order was a use-after-free under ASan).

## auval

With the sandbox disabled: copy `build/release/<APP>.app/Contents/PlugIns/<APP>.component` to
`~/Library/Audio/Plug-Ins/Components/` (one already there is moved to `<scratch>` first and put back
after, its `codesign -v` checked), wait until `auval -a | grep "aumu <SUB> JPis"`, run
`auval -v aumu <SUB> JPis` → `AU VALIDATION SUCCEEDED`, remove the copy.

## Clean-up (after every run of the app, a stand-in or a host)

- Processes: none left (`pgrep -fl <APP>`, the stand-ins' and hosts' names).
- Defaults: `defaults delete <BUNDLE_ID>` (or `defaults import` of the backup),
  `<BUNDLE_ID>.audiounit`, every stand-in's and helper's domain (a bundle-less helper writes
  `~/Library/Preferences/<its name>.plist`), and the test helpers' (`swiftpm-testing-helper`,
  `xctest`, `<APP>PackageTests`) only when this run created them; then remove the plists.
  `ls -1 ~/Library/Preferences` against `prefs-before.txt`: anything new is explained.
- `~/Library/Application Support/<APP>` (Presets, Kits) when the run created it;
  `~/Library/Caches/<BUNDLE_ID>`, `~/Library/Saved Application State/<BUNDLE_ID>.savedState`,
  `~/Library/HTTPStorages/<BUNDLE_ID>*` when they are new.
- The installed component, unless it was the user's (put back).
- Stand-in bundles registered with Launch Services:
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <bundle>`.
- Never restart system daemons (`cfprefsd`, `coreaudiod`) to clean up.
- List everything removed in `VERIFICATION.md`.

## "Not verified" (closes every VERIFICATION.md)

```markdown
## Not verified
- By ear: <renders and changes that were only measured ("measured, not heard")>.
- By hand: a real mouse on the knobs, LFO and VEL amounts, pads; MIDI learn with a real controller.
- In a real host: Logic, Live; automation, several instances, a sandboxed host and the shared
  preset folder.
- Sound through an audio device.
- Safari and a phone (the site was checked in headless Chromium only).
- Refused (the request to run outside the sandbox, or a permission): <command> — <what it would
  have shown>.
- Pictures: <which are of the real app, which of a stand-in, proved equal or not; which are
  queued for the push question (`<scratch>/capture-queue.md`)>.
```

The final report repeats these in plain words, so the user knows what to try.
