# Release (phase 06, the push question, step 5)

The procedure and every check are the project's own skill: **`<proj>/.claude/skills/release/SKILL.md`**
(rendered from the template). Follow it step by step; this file adds only what a first run of
this skill needs around it. Where the two differ, the project skill wins, **except** that these
always beat it: the user's global rules (`~/.claude/CLAUDE.md`), the single bold push question
below (asked in this run whatever "yes" came earlier in the conversation), and the capture rule of
`verification-kit.md` (the real app starts only when the default output's transport is
Built-in). The project skill already holds both: its step 3 starts the app only on a `Built-in`
default output, and its header asks the question in every run, whatever yes came before. A
project made from an older template whose skill lacks either still follows these rules: that step
is skipped or done the safe way, and recorded in the phase's `VERIFICATION.md`.

## Before step 1

- Phases 01–05 merged; `main` clean.
- `grep -rn "FILL:" docs .planning/ROADMAP.md .planning/STATE.md` → nothing.
- `<skill>/scripts/check_leftovers.sh --skip-dir .planning <proj> <words>` → `no leftovers`
  (`phases.md`, the words file), and the placeholder engine's words apart:
  `grep -rn 'kProgramTone\|"Soft Tone"\|placeholder instrument' Sources/<APP>DSP Tests/<APP>Reference docs`
  → nothing.
- Signing ready: `security find-identity -v -p codesigning | grep "Developer ID Application"`,
  `xcrun notarytool history --keychain-profile notary` succeeds, and
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` equals `SUPublicEDKey` in
  `Resources/Info.plist`. One missing: stop and tell the user what to set up
  (`development_workflow.md` §2.3); never create a new Sparkle key without asking.

## Local part (the project skill's steps 1–5)

- Branch `feature/06-v1.0.0-release`. Version **1.0.0** (the first public release, a fixed
  default); the skeleton's 0.1.0 is replaced in `Info.plist` and the site.
- `CHANGELOG.md` `## 1.0.0 — <date>`: what the user gets, in a few lines (the instrument, its
  programs, the two modes, presets and kits, MIDI learn, the plug-in). Nothing about changes
  between unreleased builds: these lines are the GitHub Release notes and the update dialog.
- `./build.sh dist` in the background (two notarizations take minutes); then the skill's checks:
  `status: Accepted` twice, `spctl` gives `source=Notarized Developer ID`, the appcast diff,
  `auval` on the component that ships (installed only for that run). A `403 … agreement` from
  notarytool: stop and tell the user to accept it at developer.apple.com/account.
- Step 3's screenshot only under the capture rule (`verification-kit.md`); otherwise the
  phase-05 picture stays and the reason is recorded.
- Merge `--no-ff`, lightweight tag `v1.0.0`.
- The catalog entry in a fresh clone in `<scratch>/catalog`, by a **text edit** of `projects.json`
  (never `jq` or a JSON library: they reformat the file), committed locally; nothing pushed.

## The push question (the last gate)

One message, in the user's language, with: what is ready locally (tag, DMG, appcast, catalog
commit, the site's pages), what is **measured, not heard** (every change to the approved sound,
from the phases' `VERIFICATION.md`, with where to listen), the main "Not verified" items, and then
**one bold question naming every outward action in order**. Czech:

> **Mám to zveřejnit? V tomto pořadí: (1) vytvořím veřejný repozitář `jiripisa/<slug>`, (2) pushnu
> tag `v1.0.0`, (3) vytvořím GitHub Release `v1.0.0` s `<APP>-1.0.0.dmg`, (4) curlem ověřím, že
> DMG vrací 200, (5) pushnu `main`, (6) zapnu GitHub Pages (`main`, `/docs`), (7) pushnu záznam
> do katalogu `jiripisa/jiripisa.github.io`.**

English:

> **Shall I publish it? In this order: (1) create the public repo `jiripisa/<slug>`, (2) push the
> tag `v1.0.0`, (3) create the GitHub Release `v1.0.0` with `<APP>-1.0.0.dmg`, (4) check with curl
> that the DMG answers 200, (5) push `main`, (6) turn on GitHub Pages (`main`, `/docs`), (7) push
> the catalog entry to `jiripisa/jiripisa.github.io`.**

When the catalog entry is unchanged or the repo is in the catalog's `exclude` list, (7) says so
as the project skill's step 5 describes. Nothing is pushed, no repo created and no Pages turned
on before the answer. A yes covers exactly the actions named; anything else is asked again. No
yes: stop and report what is ready locally.

## After the yes

The project skill's steps 7–9, in that order: repo, tag, Release, `curl` the DMG for `200`
**before** `main` (it carries the appcast), `main`, Pages; then the live checks: the Pages run
watched, both language pages and both manuals show `1.0.0`, the DMG and the live appcast
downloaded and `sign_update --verify <dmg> <edSignature>` prints nothing and exits 0; then the
catalog (`update-catalog`'s build check, push, live). A failed step stops the sequence: report
where it stopped; nothing later in the order is done.

## The report (step 5)

In the user's language:
- the site URL and the download URL;
- what was verified (test counts, equivalence residuals, `auval`, notarization, live checks);
- **Not verified**, in plain words: a real host (Logic, Live), real MIDI hardware and learn, sound
  through a device, Safari and a phone, every step the sandbox refused, which pictures are
  stand-ins;
- what was measured, not heard, and where to listen: `.planning/research/spike/renders/` (the
  approved prototype) and `renders/engine/` (the engine's listening renders);
- the calls made: the spec's [call] and the phases' [builder] lines, the five or six most worth
  checking first;
- a request: install from the website on another Mac and say what is wrong.
