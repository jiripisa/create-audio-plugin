---
name: create-audio-plugin
description: Use when the user asks for a new synthesized instrument as an Audio Unit plug-in and macOS app, e.g. "audio plugin for an electric guitar", "chci audio plugin pro elektrickou kytaru", "udělej plugin pro flétnu", "nový nástroj jako Brumle / Fanfrnoch / Didgeridoo", usually in an empty folder named after the instrument. Not for an effect, a sampler, or a new version of an instrument that already exists (that project's own release skill).
---

# Create audio plugin

One request ("an audio plugin for <instrument>") in an empty folder ends as a released AUv2
instrument plus standalone app: a public GitHub repo, a notarized DMG, a bilingual site with a
manual, Sparkle updates, a catalog entry. The user is asked **four times and nothing else**; the
rest runs autonomously from the platform in `templates/`.

**This skill's intake replaces brainstorming.** By invoking it the user has already decided the
process and delegated every design decision except the four gates. Do not invoke
`superpowers:brainstorming` or `superpowers:writing-plans` for the run, and do not follow
`new-macos-app`'s "Ask first" section; the phases write their own `PLAN.md`
(`references/phases.md`).

Talk to the user in the user's language. Every file written stays English; Czech only in `docs/cs/`
and the CS strings (`TAGLINE_CS`, the Czech manual and site).

Names: `<skill>` this skill's directory (`~/.claude/skills/create-audio-plugin`), `<proj>` the
session's working directory, `<scratch>` the session's scratchpad. Read `references/pitfalls.md`
once at the start: every guard below comes from a failure in an earlier instrument.

## The four gates

| # | When | What the user does |
|---|---|---|
| 1 | Step 0 | Confirms or corrects the identity; picks the look: "three concepts to pick from" / "leave it to me" |
| 2 | Step 2 | Approves the prototype's renders, or says what to change (loop) |
| 3 | Step 3, only if "three concepts" | Picks one concept |
| 4 | Step 4 | Answers the single bold push question |

Not gates, but stops: a non-empty folder (step 0), a name `identity.py` refuses (exit 2, step 0), a
missing signing piece or Sparkle key before the release (`references/release.md`), a rejected
aspect twice (`references/prototype.md`).

## Step 0 — Intake

1. **The folder**: `ls -A <proj>` shows nothing but dotfiles (such as the session's `.claude/`).
   Anything else: stop and ask what to do.
2. **Identity**: `python3 -I <skill>/scripts/identity.py "<proj>" > <scratch>/identity.json`
   (APP_NAME is the folder name as written; APP, slug, C prefix, `io.jp4.<slug>`, an AU subtype
   that no installed component and no project under `~/Development/Claude` has, OWNER;
   manufacturer is always `JPis`). Exit 2: stop, tell the user why the name cannot be used and
   ask for a corrected name (handled as in 6).
3. **Preflight, read-only**: the checks of `new-macos-app` §2 without its target-directory check
   (the folder is this one, step 1), and:

   | Check | Command |
   |---|---|
   | GitHub, name free | `gh auth status`; `gh repo view <OWNER>/<slug>` must fail |
   | Author | `git config user.name` prints a name (AUTHOR: footers, LICENSE); empty: ask for it in question 1's free text |
   | Toolchain | `swift --version`; `xcrun actool --version` (full Xcode) |
   | Renderer | `python3 -I ~/.claude/skills/new-macos-app/scripts/scaffold.py --help \| grep -- --templates`; nothing printed: re-apply `<skill>/patches/new-macos-app-scaffold.diff` (`<skill>/README.md`) |
   | Signing (sandbox disabled) | `security find-identity -v -p codesigning \| grep "Developer ID Application"`; `xcrun notarytool history --keychain-profile notary` |
   | Sparkle key (sandbox disabled) | `ls ~/Development/Claude/*/.build/artifacts/sparkle/Sparkle/bin/generate_keys` (another project's Sparkle): the first one's `-p` equals `SUPublicEDKey` in `<skill>/templates/Resources/Info.plist`; none found: checked in phase 01 |
   | Codex | `codex --version` |

   The signing and Sparkle rows read the login Keychain: run them with the Bash sandbox disabled
   ("Outside the sandbox" below). A piece is missing only when its check fails with the sandbox
   disabled; inside the sandbox the same failure says nothing. A missing piece does not stop the
   sound work: say it, it must be solved before phase 06.
   No Codex: the look is native SwiftUI without raster art (`references/codex.md` "No Codex"); say
   so and leave out the look question. A taken repo name: say so in question 1.
4. **Taglines**: propose one sentence each, EN and CS, saying what the instrument is. None may hold
   `"`, `\`, `$`, a backtick or `": "`.
5. **One message** with the playback: what will be made, in these words, "a synthesized
   <instrument> you play from MIDI or the keyboard, not an effect for your own <instrument>"; the
   instrument as understood, its family and variants as known so far, the derived identity
   (display name, code name, slug, bundle id, AU `aumu <SUB> JPis`), the taglines, the preflight
   results, and the **fixed defaults, stated, not asked**: public repo `jiripisa/<slug>`, MIT,
   website with manual, EN + CS, Sparkle on, first release 1.0.0, catalog entry. One line more:
   pictures of the app are taken while the screen is unlocked; any that could not be taken wait
   for the push question. Then **one AskUserQuestion with two questions**: "Is the name and
   identity right?" ("Yes" / "No, another name": the corrected name itself is typed into the
   free-text "Other" answer; a "No" without a name is followed by asking for the name, nothing
   else) and "The look?" ("Three concepts to pick from" / "Leave it to me").
6. A **corrected name changes only the identity**: `identity.py "<parent of proj>/<corrected
   name>"` rewrites `<scratch>/identity.json`; repeat the name-free check. The folder is never
   renamed, moved or deleted. The identity becomes permanent in the spec (step 3.1); until then
   the approval at gate 2 may correct it once more, in the same way.
7. Write `<scratch>/intake.md`: the user's request verbatim, the look answer, the taglines.

## Step 1 — Research (unattended)

Five background `general-purpose` subagents in parallel, then the report writer:
`references/research-briefs.md` (briefs, evidence labels, download safety, report form). Read the
report yourself, in full, before step 2.

## Step 2 — Listening prototype (gate 2)

`references/prototype.md`, using `<skill>/scripts/spike_harness.h` (pattern
`scripts/spike_example.cpp`) and `scripts/analyze.swift`. The harness plays the notes as the
plug-in will (a re-hit, Poly / Mono / Legato, glide, pedal, bend), so what is approved is what the
engine must reproduce. **No template render and no product code until the user approves.** Every
render is measured before it is shown, and the message says "measured, not heard". Open the
renders folder, then wait. Not approved: change, re-render, measure, resend. The same aspect
rejected twice: stop tuning it; ask for a reference or offer to drop it. The approval may rename
programs or correct the identity one last time: a corrected name re-runs `identity.py` and the
name-free check of step 0.

## Step 3 — Autonomous build

1. **Spec**: `references/spec-template.md`, then its builder check. Identity, parameter IDs and
   their order are permanent from here.
2. **Phases 01–05**: `references/phases.md` ("Every phase", the global-constraints block pasted
   into each brief). 01 main session (render with `new-macos-app`'s `scaffold.py --templates
   <skill>/templates` into `<scratch>`, then copy in); 02 background subagent while the main session
   runs the Codex jobs of 03 (`references/codex.md`); 04 and 05 subagents. Seeing the app:
   `references/verification-kit.md`. **Captures of the app and AX drives are the main session's,
   like the Codex jobs**: the subagents of 04 and 05 hand back a capture list (what to capture,
   in which state, where it goes) and the main session takes the pictures. `TEMPLATE_MANIFEST.md`
   describes the platform/instrument seam. **The main session re-runs the tests itself before
   every merge.**
3. **Gate 3** (only "three concepts"): show the three concepts and ask for the pick
   (`codex.md` "The pick"); the engine work goes on meanwhile. "Leave it to me": two concepts, you
   pick and write why.
4. **Phase 06, local part only**: `references/release.md` with the project's own
   `.claude/skills/release/SKILL.md`. Nothing is published: no repo, no push, no Release, no
   Pages. (Notarization does upload the app to Apple's notary service; that is what the user's
   signing set-up is for, and it makes nothing public.)

## Step 4 — The push question (gate 4)

The user is at the Mac now: first take the captures that were queued (a locked screen, a
refusal; `verification-kit.md` "Queued captures"), place them, and run the release gate's link
check again (`release.md` "Before step 1"). A picture still missing is taken out of the pages, in
EN and CS alike, and named in the question; no page ships with a broken picture.

One message: what is ready locally, what is measured but not heard, the main "Not verified" items,
then **one bold question naming every outward action in order** (`release.md` has it in Czech and
English). No repo, push, Release, Pages or catalog push before the answer to this question. An
earlier "yes" never counts. A yes covers only the actions named. This question is the confirmation
the user's global rule asks for before a push: one question covers every push it names, so none
of them is asked again.

## Step 5 — Report

`release.md` "The report": URLs, what was verified, **Not verified** in plain words, what was
measured, not heard, and where to listen, the calls worth checking first.

## Rules that always hold

The user's global `~/.claude/CLAUDE.md` wins over this skill and over any project skill. In short:

- Push and anything public only after the step-4 question. No AI attribution trailers
  (Co-Authored-By, session links) in commits, PRs, Releases or tickets. `git status` before every
  commit.
- Launch the app or a helper by its full path, never `open -a` or `tell application "<APP>"`.
  Capture only a window of a PID you started (`scripts/capture_window.swift`). The real app (an
  audio stream) only when the default output's transport is Built-in. AX on your own PID only: no
  keystrokes, no clicks, no activation. Never write to connected hardware.
- Never change permission settings. Outside the sandbox (next section) only by asking for it on
  the call; a refused request is not retried and not worked around: record it under "Not
  verified" in the phase's `VERIFICATION.md` and go on.
- Clean up helpers: `defaults delete` their domains, remove the plists, compare
  `~/Library/Preferences` before and after (`verification-kit.md` "Clean-up").
- A subagent's "could not run the tests" is not a pass: fix the environment and run them yourself.

## Outside the sandbox

Some steps cannot work inside Claude Code's Bash sandbox, and fail there in ways that read as
something else (a keychain lookup "finds nothing", a capture is "refused"). Run these **with the
sandbox disabled from the start** (the Bash tool's `dangerouslyDisableSandbox`), in the main
session and in subagents alike:

- a window capture (`capture_window.swift`, `screencapture -l`) and AX drives of the app;
- copying the component to `~/Library/Audio/Plug-Ins/Components` for `auval` or the scratch AU
  host, the `auval` run, and removing the copy;
- every `codex exec` job;
- headless Chrome (Playwright);
- the login Keychain and signing: `security find-identity`, `xcrun notarytool`, `codesign`,
  Sparkle's `generate_keys -p` and `sign_update`, and `./build.sh dist`.

Only a refusal of that request (by the permission system or the user) is final: the step is then
"Not verified", with the command and what it would have shown. A failure inside the sandbox is
not a finding about the Mac. Everything else stays in the sandbox.

## Files

| Step | Reference | Scripts |
|---|---|---|
| 0 | this file, `references/pitfalls.md` | `scripts/identity.py`; `patches/new-macos-app-scaffold.diff` |
| 1 | `references/research-briefs.md` | `scripts/analyze.swift` |
| 2 | `references/prototype.md` | `scripts/spike_harness.h`, `spike_example.cpp`, `analyze.swift` |
| 3 | `references/spec-template.md`, `phases.md`, `codex.md`, `verification-kit.md`; `TEMPLATE_MANIFEST.md` | `templates/`, `scripts/check_leftovers.sh` + `leftover-words.txt`, `capture_window.swift` |
| 4–5 | `references/release.md` | the project's `release` skill |

`scripts/verify_template.sh` and `template-words.txt` check the template itself, not a run.

## Common mistakes

| Mistake | Fix |
|---|---|
| Invoking brainstorming or writing-plans, or asking about repo, license, languages, website | The intake replaces them; the defaults are stated, not asked |
| A second question round at intake, or questions during the build | Four gates only; build-time choices are [call] / [builder] lines |
| Renaming or moving the folder after a corrected name | Only `identity.json` changes |
| Rendering the template or writing product code before the sound is approved | Spike only until gate 2 is passed |
| Sending renders unmeasured, or saying they "sound right" | Measure first; say "measured, not heard" |
| Tuning a rejected aspect a third time | Ask for a reference or offer to drop it |
| `scaffold.py --out <proj>` | It refuses a non-empty target: render into `<scratch>`, check collisions, `rsync` |
| Merging on a subagent's test report | Re-run build, tests (debug and release) and the leftovers check yourself |
| Placeholder engine words left | `grep -rn 'kProgramTone\|"Soft Tone"\|placeholder instrument' …` after phase 02 and before the release |
| Changing a parameter ID, its order or the AU codes after the spec | Permanent; only append, after 1.0.0 |
| `screencapture` without `-l`, `open -a`, an audio stream on the user's interface | `verification-kit.md` |
| A subagent capturing or driving the app; a capture, `auval`, Codex or a keychain check run inside the sandbox | Captures are the main session's; "Outside the sandbox" |
| Working around a locked screen (a capture from inside the app, `ImageRenderer`) | Queue the capture; take it at gate 4, when the user is back |
| Shipping a page whose picture is missing | The release gate's link check; the figure comes out in EN and CS, and the push question says so |
| Rewriting `projects.json` with `jq` | Text edit only |
| Publishing on a "yes" given earlier in the conversation | Only the answer to the step-4 question counts |
