# {{APP_NAME}} — project notes for Claude

{{TAGLINE}}

## Code

- Native macOS app, SwiftUI, macOS 27+. Swift Package Manager plus shell
  scripts; there is no Xcode project, so never add one.
- `Sources/{{APP}}Core` holds logic without UI (no SwiftUI/AppKit) and is
  covered by `swift test` (Swift Testing). `Sources/{{APP}}` is the SwiftUI
  app and stays a thin layer over the core. New logic goes into the core,
  test first.
- Build and run: `./run.sh` (debug, logs in the terminal), `./run.sh release`,
  `./build.sh [debug|release|dist|clean]`. Details in `development_workflow.md`.
- Every user-visible change gets a line under `## Unreleased` in
  `CHANGELOG.md`; the release notes and the update dialog come from it.
- **The Audio Unit's identity is permanent.** Its codes (`aumu` / `{{AU_SUBTYPE}}` /
  `JPis`, bundle id `{{BUNDLE_ID}}.audiounit`, the factory function
  `{{APP}}AUFactory`, the view class `{{APP}}AUViewFactory`) and its
  parameter IDs never change: host projects find the plug-in and their
  automation by them. An ID names a knob or an amount, not its place in the
  engine's table (`{{APP_C}}_param_id`: knob k is k, LFO l's amount on knob k is
  1000·(l + 1) + k, the velocity's 3000 + k). Knobs are only appended, at the
  end of the instrument's; identifiers are never renamed; everything saved
  names parameters by identifier or ID. Validate every change of the Audio Unit with
  `auval` (`development_workflow.md` §2.1).
- **The instrument lives in a few files**: `Sources/{{APP}}DSP/Params.h` (its knobs,
  its playing style as defaults of platform knobs (`kPlatformDefaults`), sections,
  programs, kit), `Voice.h` (its voice), `Tests/{{APP}}Reference/` and the
  instrument tests (`PrototypeEquivalenceTests`, `SoundRegressionTests`,
  `InstrumentTableTests`, `ReferenceTests`), plus the panel's `Artwork.swift` and
  `SectionLayout` plans. Everything else is the platform the project was made from:
  the platform tests must stay green without knowing the instrument's knobs.

## Releases

- Use the project skill `release` (`.claude/skills/release/SKILL.md`) for
  every release; it holds the whole procedure and its checks.
- Signing: Developer ID Application certificate and the `notary`
  notarytool profile live in the login Keychain.
- The Sparkle EdDSA private key lives only in the login Keychain. Never put
  it (or an exported copy) into the repo; `Info.plist` holds only the public
  key (`SUPublicEDKey`).

## Website (`docs/`, GitHub Pages)

- Served from `main` / `docs` at {{PAGES_URL}}. The download links and
  version strings on the pages are bumped with every release.
- `docs/manual.html` describes every control of the app. A user-visible
  change is not done until the manual says how to use it; screenshots live
  in `docs/assets/manual/`.
- **The site is bilingual.** Every change to `docs/index.html` or
  `docs/manual.html` must also go into `docs/cs/` (and the other way
  round): the same tags in the same order. Shared styles live in `docs/assets/`.
- The pages, `.planning/ROADMAP.md` and `.planning/STATE.md` were made from
  templates that mark what is the instrument's with `<!-- FILL: … -->`
  comments, saying what goes there and from where. A release has none left:
  `grep -rn 'FILL:' docs .planning/ROADMAP.md .planning/STATE.md` finds nothing.

## Planning

- Work runs in phases: `.planning/phases/NN-slug/` with `PLAN.md` and
  `VERIFICATION.md`, one feature branch per phase, merged to `main` with
  `--no-ff`; `ROADMAP.md` and `STATE.md` are updated at the end of each
  phase. See `development_workflow.md` §4.
