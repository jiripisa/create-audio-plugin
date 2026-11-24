---
name: release
description: Use when the user wants to release, publish or ship a new version of {{APP_NAME}} ("udělej release", "vydej novou verzi", "make a release"), or to build the signed and notarized DMG for distribution.
---

# Releasing {{APP_NAME}}

A release is: version bump → tests → signed + notarized DMG + appcast →
merge + tag → catalog entry (local) → **the push question** → GitHub repo,
Release, `main`, Pages → live checks → catalog published. Every step below has
a check; a step is not done until its check passed.

**Pushing needs the user's explicit OK** (global rule). Steps 1–5 change only
this Mac. Before step 7 ask **one bold question** that names every outward
action this release takes, in the order they happen, unless the user has
already said yes to exactly that in the conversation. For the first release
that is all of them:

1. create the public repo `{{OWNER}}/{{APP_LOWER}}` (or make it public, if it
   exists and is private);
2. push the tag `vX.Y.Z`;
3. create the GitHub Release `vX.Y.Z` with the DMG;
4. check with `curl` that the DMG downloads (`200`);
5. push `main`;
6. turn on GitHub Pages (`main`, `/docs`);
7. push the catalog entry to `{{OWNER}}/{{OWNER}}.github.io` — or, when the entry is
   unchanged, start the catalog's rebuild
   (`gh workflow run pages.yml -R {{OWNER}}/{{OWNER}}.github.io`).

For a later release, leave out what is already so (step 7.0 says how to tell)
and say that it is. The question is asked once; a yes covers exactly the
actions it named.

## 1. Prepare

1. `git status` clean, on `main`, up to date. Create the branch `feature/NN-vX.Y.Z-release`
   (NN = next phase number from `.planning/ROADMAP.md`).
2. Pick the version. The **first release is 1.0.0**; until then the skeleton
   carries 0.1.0, which the website links point at, and this step replaces it.
   After that: patch for fixes and small additions, minor for new features or
   removed UI, major only when the user says so. Say which and why.
3. `CHANGELOG.md`: rename `## Unreleased` to `## X.Y.Z — YYYY-MM-DD`. If there
   is no Unreleased section, write the entries from `git log` since the last tag
   first. These lines become the GitHub Release notes and the text of the update
   dialog.
4. Bump `CFBundleShortVersionString` **and** `CFBundleVersion` in
   `Resources/Info.plist`.
5. Replace the old version in the website: `grep -rn "<old version>" docs/*.html docs/cs/*.html`
   (download links `releases/download/v…/{{APP}}-….dmg` and version texts).
   Leave `docs/appcast.xml` alone; `build.sh dist` writes it.

Check: `swift test` green (redirect the output to a file, read the summary line);
`grep -rn "<old version>" docs/*.html docs/cs/*.html` finds nothing;
`grep -rn "FILL:" docs .planning/ROADMAP.md .planning/STATE.md` finds nothing
(every template placeholder of the site, the manual and the planning files is
written; plans and specs are not templates and are not checked).

## 2. Build the DMG

`./build.sh dist` — takes several minutes (two notarizations); run it in the
background and wait for it to finish.

Check, all of them:
- the log shows `status: Accepted` twice and ends with `Done!`;
- `spctl -a -vv build/release/{{APP}}.app` says `source=Notarized Developer ID`;
- `git diff docs/appcast.xml` shows the new version, the new download URL
  and a new `sparkle:edSignature`.

A `403 … agreement is missing or has expired` from notarytool means the user
must accept the new Apple agreement at developer.apple.com/account — stop and
tell them.

Then validate the component that ships: copy
`build/release/{{APP}}.app/Contents/PlugIns/{{APP}}.component` to
`~/Library/Audio/Plug-Ins/Components/`, run `auval -v aumu {{AU_SUBTYPE}} JPis` (must end
with `AU VALIDATION SUCCEEDED`), and remove the copy again unless the user
keeps one installed there.

## 3. Screenshot (when the UI changed)

Open `build/release/{{APP}}.app` by its path, capture only its window
(`screencapture -x -o -l <window id>`; the window id from
`CGWindowListCopyWindowInfo`, filtered on the PID of the process you started),
look at the image, then copy it to `docs/assets/{{APP_LOWER}}-window.png`. Never
capture the whole screen or other apps' windows. Quit the app afterwards.

## 4. Commit, merge, tag

1. Update `.planning` (ROADMAP row, STATE line,
   `phases/NN-vX.Y.Z-release/VERIFICATION.md` with the checks above).
2. `git status`, then commit (never with AI attribution trailers): `chore(release): vX.Y.Z — version bump, CHANGELOG, appcast, website`.
3. `git switch main && git merge --no-ff <branch> -m "chore: merge … — vX.Y.Z release"`,
   delete the branch, `git tag vX.Y.Z` (lightweight).

## 5. Catalog entry (local)

The catalog at https://{{OWNER}}.github.io/ is built from `{{OWNER}}/{{OWNER}}.github.io`.
The global `update-catalog` skill says what an entry holds and how to choose
its words; here its work is split in two, because its build check and its push
need the public repo, the Release and Pages. This step is its local part (its
§2 and §3):

1. Clone the catalog fresh into the session's scratchpad (never into the
   project): `gh repo clone {{OWNER}}/{{OWNER}}.github.io "<scratchpad>/catalog" -- --depth 1`.
   Read its `README.md` and `projects.json`. If `{{APP_LOWER}}` is in its `exclude`
   list, the user hid it on purpose: stop and ask before removing it from there
   (and leave the catalog out of the push question until they answer).
2. Write the entry `projects.{{APP_LOWER}}` (the repo name, exact case) as
   `update-catalog` §3 says: `section` (`music` for an instrument), `order` (after
   the last of its section), `title` (`{{APP_NAME}}`, as the website's `<h1>`), a
   `summary` when the repo description does not already say what the instrument
   is, `image` `{{PAGES_URL}}assets/{{APP_LOWER}}-window.png` and `icon`
   `{{PAGES_URL}}assets/icon.png`. For a later release, change the entry only when
   the release changed what the app does; an unchanged entry is normal.
3. **Edit `projects.json` as text** (the Edit tool, an insertion or a changed
   line), never by rewriting the JSON with a program (`jq`, `json.dump`): that
   reformats the whole file.
4. Check: `jq empty projects.json` succeeds; `git diff` shows only this entry.
   Commit it locally, `catalog: {{APP_NAME}} X.Y.Z` (no AI attribution
   trailers); nothing is pushed yet.

## 6. The push question

Ask the bold question of the top of this file, naming each action and the
release URL it leads to. Wait for the answer. Without a yes, stop here and
report what is ready locally (the tag, the DMG, the catalog commit).

## 7. Publish (order matters)

0. Find out what already exists:
   - `gh repo view {{OWNER}}/{{APP_LOWER}} --json visibility --jq .visibility`:
     an error (no such repo) → create it,
     `gh repo create {{OWNER}}/{{APP_LOWER}} --public --source . --remote origin --description "{{TAGLINE}}" --homepage "{{PAGES_URL}}"`
     (no `--push`); `PRIVATE` →
     `gh repo edit {{OWNER}}/{{APP_LOWER}} --visibility public --accept-visibility-change-consequences`;
     `PUBLIC` → nothing to do.
   - `git remote get-url origin` is `{{REPO_URL}}.git` (or its SSH form). When the
     repo exists but this clone has no `origin` (`gh repo create` was not run here),
     add it: `git remote add origin {{REPO_URL}}.git`.
1. `git push origin vX.Y.Z`
2. Copy `build/{{APP}}.dmg` to a scratch folder as `{{APP}}-X.Y.Z.dmg` and run
   `gh release create vX.Y.Z <that file> --title "{{APP_NAME}} X.Y.Z" --notes-file <CHANGELOG section>`.
3. Check: `curl -sIL -o /dev/null -w "%{http_code}" {{REPO_URL}}/releases/download/vX.Y.Z/{{APP}}-X.Y.Z.dmg` → `200`.
4. Only now `git push -u origin main` (it carries the appcast; the DMG must
   already exist).
5. Pages: `gh api repos/{{OWNER}}/{{APP_LOWER}}/pages` answers 404 → turn it on,
   `gh api -X POST repos/{{OWNER}}/{{APP_LOWER}}/pages -f "source[branch]=main" -f "source[path]=/docs"`;
   otherwise it is on already.

## 8. Live checks

1. Wait for the Pages deploy: `gh run list --limit 1`, then `gh run watch <id> --exit-status`.
2. `curl -s "{{PAGES_URL}}?x=$RANDOM" | grep -o "X.Y.Z"` shows the new version;
   the same for `{{PAGES_URL}}cs/`, `manual.html` and `cs/manual.html`.
3. Download the DMG from the release URL and the live appcast
   (`{{PAGES_URL}}appcast.xml`), then
   `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify <dmg> <edSignature from the live appcast>`
   must print nothing and exit 0 — the feed's signature matches the published bytes.

## 9. Catalog published

Only after the live checks passed, in the catalog clone of step 5 (the rest of
`update-catalog`, its §1 and §4–6):

1. `gh api repos/{{OWNER}}/{{APP_LOWER}} --jq '[.name, .private, .has_pages] | @tsv'`
   says public with Pages.
2. The entry's `image` and `icon` URLs answer `200`
   (`curl -s -o /dev/null -w '%{http_code}' <url>`); one that does not leaves the
   entry (a text edit again, amended into the local commit).
3. Build check: `GITHUB_TOKEN=$(gh auth token) node scripts/build.mjs`, then
   `grep -c 'id="p-{{APP_LOWER}}"' dist/index.html` → `1` and
   `grep -o '{{OWNER}}/{{APP_LOWER}}/releases/download/vX.Y.Z/[^"]*' dist/index.html`
   shows the new DMG.
4. `git status`, then `git push origin main` (the bold question covered it). With
   no change to the entry, there is nothing to push: start the rebuild instead,
   `gh workflow run pages.yml -R {{OWNER}}/{{OWNER}}.github.io`.
5. Live: `gh run watch <id> -R {{OWNER}}/{{OWNER}}.github.io --exit-status`, then
   `curl -s "https://{{OWNER}}.github.io/?x=$RANDOM" | grep -o '{{OWNER}}/{{APP_LOWER}}/releases/download/vX.Y.Z/[^"]*'`
   (retry once after 30 s; Pages may serve the old page for a minute).

## Report

Tell the user: the release URL, the site URL, what was pushed, the results of
every check, the version choice and why, the catalog entry (or why it stayed),
and ask them to confirm that an installed older version offers the update.
