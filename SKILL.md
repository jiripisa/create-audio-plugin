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

Not gates, but stops: a non-empty folder (step 0), a missing signing piece or Sparkle key before
the release (`references/release.md`), a rejected aspect twice (`references/prototype.md`).

## Step 0 — Intake

1. **The folder**: `ls -A <proj>` shows nothing but dotfiles (such as the session's `.claude/`).
   Anything else: stop and ask what to do.
2. **Identity**: `python3 -I <skill>/scripts/identity.py "<proj>" > <scratch>/identity.json`
   (APP_NAME is the folder name as written; APP, slug, C prefix, `io.jp4.<slug>`, AU subtype not
   yet taken, OWNER; manufacturer is always `JPis`). Exit 2: tell the user why the name cannot be
   used and ask for a corrected name (handled as in 6).
3. **Preflight, read-only** (`new-macos-app` §2 plus):

   | Check | Command |
   |---|---|
   | GitHub, name free | `gh auth status`; `gh repo view <OWNER>/<slug>` must fail |
   | Toolchain | `swift --version`; `xcrun actool --version` (full Xcode) |
   | Signing | `security find-identity -v -p codesigning \| grep "Developer ID Application"`; `xcrun notarytool history --keychain-profile notary` |
   | Sparkle key | `ls ~/Development/Claude/*/.build/artifacts/sparkle/Sparkle/bin/generate_keys` (another project's Sparkle): the first one's `-p` equals `SUPublicEDKey` in `<skill>/templates/Resources/Info.plist`; none found: checked in phase 01 |
   | Codex | `codex --version` |

   A missing signing piece does not stop the sound work: say it, it must be solved before phase 06
   (a failed keychain lookup may be the sandbox; `release.md` checks again).
   No Codex: the look is native SwiftUI without raster art (`references/codex.md` "No Codex"); say
   so and leave out the look question. A taken repo name: say so in question 1.
4. **Taglines**: propose one sentence each, EN and CS, saying what the instrument is. None may hold
   `"`, `\`, `$`, a backtick or `": "`.
5. **One message** with the playback: the instrument as understood, its family and variants as
   known so far, the derived identity (display name, code name, slug, bundle id, AU
   `aumu <SUB> JPis`), the taglines, the preflight results, and the **fixed defaults, stated, not
   asked**: public repo `jiripisa/<slug>`, MIT, website with manual, EN + CS, Sparkle on, first
   release 1.0.0, catalog entry. Then **one AskUserQuestion with two questions**: "Is the name and
   identity right?" (yes / correct it) and "The look?" ("Three concepts to pick from" / "Leave it
   to me").
6. A **corrected name changes only the identity**: `identity.py "<parent of proj>/<corrected
   name>"` rewrites `<scratch>/identity.json`; repeat the name-free check. The folder is never
   renamed, moved or deleted. From here the identity is permanent.
7. Write `<scratch>/intake.md`: the user's request verbatim, the look answer, the taglines.

## Step 1 — Research (unattended)

Five background `general-purpose` subagents in parallel, then the report writer:
`references/research-briefs.md` (briefs, evidence labels, download safety, report form). Read the
report yourself, in full, before step 2.

## Step 2 — Listening prototype (gate 2)

`references/prototype.md`, using `<skill>/scripts/spike_harness.h` (pattern
`scripts/spike_example.cpp`) and `scripts/analyze.swift`. **No template render and no product code
until the user approves.** Every render is measured before it is shown, and the message says
"measured, not heard". Open the renders folder, then wait. Not approved: change, re-render,
measure, resend. The same aspect rejected twice: stop tuning it; ask for a reference or offer to
drop it. The approval may rename programs or correct the identity one last time.

## Step 3 — Autonomous build

1. **Spec**: `references/spec-template.md`, then its builder check. Identity, parameter IDs and
   their order are permanent from here.
2. **Phases 01–05**: `references/phases.md` ("Every phase", the global-constraints block pasted
   into each brief). 01 main session (render with `new-macos-app`'s `scaffold.py --templates
   <skill>/templates` into `<scratch>`, then copy in); 02 background subagent while the main session
   runs the Codex jobs of 03 (`references/codex.md`); 04 and 05 subagents. Seeing the app:
   `references/verification-kit.md`. `TEMPLATE_MANIFEST.md` describes the platform/instrument seam.
   **The main session re-runs the tests itself before every merge.**
3. **Gate 3** (only "three concepts"): show the three concepts and ask for the pick
   (`codex.md` "The pick"); the engine work goes on meanwhile. "Leave it to me": two concepts, you
   pick and write why.
4. **Phase 06, local part only**: `references/release.md` with the project's own
   `.claude/skills/release/SKILL.md`. Nothing leaves the Mac.

## Step 4 — The push question (gate 4)

One message: what is ready locally, what is measured but not heard, the main "Not verified" items,
then **one bold question naming every outward action in order** (`release.md` has it in Czech and
English). No repo, push, Release, Pages or catalog push before the answer to this question. An
earlier "yes" never counts. A yes covers only the actions named.

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
- Never change permission settings. A step refused by the sandbox or a permission is not retried:
  record it under "Not verified" in the phase's `VERIFICATION.md` and go on.
- Clean up helpers: `defaults delete` their domains, remove the plists, compare
  `~/Library/Preferences` before and after (`verification-kit.md` "Clean-up").
- A subagent's "could not run the tests" is not a pass: fix the environment and run them yourself.

## Files

| Step | Reference | Scripts |
|---|---|---|
| 0 | this file, `references/pitfalls.md` | `scripts/identity.py` |
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
| Rewriting `projects.json` with `jq` | Text edit only |
| Publishing on a "yes" given earlier in the conversation | Only the answer to the step-4 question counts |
