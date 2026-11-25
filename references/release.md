# Release (phase 06, the push question, step 5)

The procedure and every check are the project's own skill: **`<proj>/.claude/skills/release/SKILL.md`**
(rendered from the template). Follow it step by step; this file adds only what a first run of
this skill needs around it. Where the two differ, the project skill wins, **except** that these
always beat it: the user's global rules (`~/.claude/CLAUDE.md`), the single bold push question
below (asked in this run whatever "yes" came earlier in the conversation), and the capture rule of
`verification-kit.md` (the real app starts only when the default output's transport is
Built-in), and the capture queue (`verification-kit.md` "Queued captures"): a picture on the
queue is never taken out at step 1, whatever the project skill's step 1 says; it waits for the
push question, where the user is back to have it taken. The project skill already holds both: its step 3 starts the app only on a `Built-in`
default output, and its header asks the question in every run, whatever yes came before. A
project made from an older template whose skill lacks either still follows these rules: that step
is skipped or done the safe way, and recorded in the phase's `VERIFICATION.md`.

## Before step 1

- Phases 01–05 merged; `main` clean.
- `grep -rn "FILL:" docs .planning/ROADMAP.md .planning/STATE.md` → nothing.
- `<skill>/scripts/check_leftovers.sh --skip-dir .planning <proj> <words>` → `no leftovers`
  (`phases.md`, the words file), and the placeholder grep (`phases.md`):
  `grep -rn 'kProgramTone\|"Soft Tone"\|placeholder instrument' Sources/<APP>DSP Tests/<APP>Reference docs`
  → nothing.
- **Every picture is there**: `scripts/check_site_links.sh` → `site links ok` (every `src=` and
  `href=` to a local file and every CSS `url()` under `docs/` exists). For each file it lists:
  a picture on the capture queue is taken when the user is back (below, "The push question");
  one that still cannot be made has its figure taken out of the page, the same tags in `docs/`
  and `docs/cs/` (the `<figure>` or `<img>` and the sentence pointing at it; then the tag-for-tag
  diff of `phases.md` again), until the check passes. Each figure taken out is written under
  "Not verified" and named in the push question. A broken picture is never shipped, and nothing
  is drawn in its place.
- Signing ready, **checked with the sandbox disabled** (SKILL.md "Outside the sandbox"; inside it
  the keychain is out of reach and every one of these reads as "not set up"):
  `security find-identity -v -p codesigning | grep "Developer ID Application"`,
  `xcrun notarytool history --keychain-profile notary` succeeds, and
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` equals `SUPublicEDKey` in
  `Resources/Info.plist`. A piece is missing only when its check fails with the sandbox disabled
  (or the request to disable it is refused: say that instead). One missing: stop and tell the
  user what to set up (`development_workflow.md` §2.3); never create a new Sparkle key without
  asking.

## Local part (the project skill's steps 1–5)

- Branch `feature/06-v1.0.0-release`. Version **1.0.0** (the first public release, a fixed
  default); the skeleton's 0.1.0 is replaced in `Info.plist` and the site.
- `CHANGELOG.md` `## 1.0.0 — <date>`: what the user gets, in a few lines (the instrument, its
  programs, the two modes, presets and kits, MIDI learn, the plug-in). Nothing about changes
  between unreleased builds: these lines are the GitHub Release notes and the update dialog.
- `./build.sh dist` in the background with the sandbox disabled (codesign, two notarizations
  that take minutes, `sign_update`); then the skill's checks: `status: Accepted` twice, `spctl`
  gives `source=Notarized Developer ID`, the appcast diff, `auval` on the component that ships
  (installed only for that run). A `403 … agreement` from notarytool: stop and tell the user to
  accept it at developer.apple.com/account. Notarization uploads the app to Apple's notary
  service; nothing is published by it.
- Step 3's screenshot only under the capture rule (`verification-kit.md`), by the main session;
  otherwise the phase-05 picture stays, or the capture goes on the queue, and the reason is
  recorded.
- Merge `--no-ff`, lightweight tag `v1.0.0`.
- The catalog entry in a fresh clone in `<scratch>/catalog`, by a **text edit** of `projects.json`
  (never `jq` or a JSON library: they reformat the file), committed locally; nothing pushed.

## The push question (the last gate)

**First the queued captures** (`verification-kit.md` "Queued captures"): the user is at the Mac
to answer, so the screen is unlocked. Take every picture on `<scratch>/capture-queue.md` (the
real app with a built-in default output, else the labelled stand-in), look at each, write the
manual's marks, commit; then run
`scripts/check_site_links.sh` again. What still cannot be taken has its figure taken out as
"Before step 1" says. These are commits on `main` after the tag (`docs/` only: the DMG and the
appcast are unchanged, and the site is served from `main`); the tag stays where it is.

One message, in the user's language, with: what is ready locally (tag, DMG, appcast, catalog
commit, the site's pages), what is **measured, not heard** (every change to the approved sound,
from the phases' `VERIFICATION.md`, with where to listen), the main "Not verified" items, **every
figure that was taken out because its picture could not be made** ("the manual ships without the
pictures of …": said explicitly, never left for the user to find), and then **one bold question
naming every outward action in order**. Czech:

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
on before the answer. This question is the confirmation the user's global rule asks for before a
push: one question covers every push it names (the tag, `main`, the catalog), so none of them is
asked again; a yes covers exactly the actions named, and anything else is asked again. No yes:
stop and report what is ready locally.

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
  through a device, Safari and a phone, every step that was refused, which pictures are
  stand-ins, which figures were taken out for want of a picture;
- what was measured, not heard, and where to listen: `.planning/research/spike/renders/` (the
  approved prototype) and `renders/engine/` (the engine's listening renders);
- the calls made: the spec's [call] and the phases' [builder] lines, the five or six most worth
  checking first;
- a request: install from the website on another Mac and say what is wrong.
