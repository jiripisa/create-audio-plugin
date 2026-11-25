# {{APP_NAME}} — Development Workflow, Build & Distribution

## 1. Toolchain & Project Layout

- Xcode 27 (Swift 6.4), macOS 27+. The Command Line Tools alone are not enough,
  because `actool`, which compiles the app icon, comes with Xcode. No Xcode
  project: Swift Package Manager builds the code, `build.sh` assembles the
  `.app` bundle.

```
{{APP_LOWER}}/
├── Package.swift
├── Sources/{{APP}}/          # SwiftUI app (thin layer)
├── Sources/{{APP}}Core/      # logic without UI, tested
├── Sources/{{APP}}DSP/       # the sound engine, C++ behind a C interface
├── Sources/{{APP}}UI/        # the instrument's panel, shared by the app and the plug-in
├── Sources/{{APP}}AU/        # the Audio Unit (AUv2 instrument), C++ on ThirdParty/AudioUnitSDK
├── Sources/{{APP}}AUView/    # the Audio Unit's window in a host
├── Sources/{{APP}}AUExports/ # no code: what the Audio Unit's library exports (Package.swift)
├── Tests/{{APP}}CoreTests/   # Swift Testing
├── Resources/               # Info.plist, entitlements, AppIcon.png (1024 px master),
│                            # AppIcon.icon (Icon Composer document), Art/
├── scripts/make_appcast.py  # Sparkle feed, called by build.sh dist
├── scripts/check_site_links.sh  # every file the site links exists (before a release)
├── docs/                    # GitHub Pages website + manual
├── build.sh                 # debug | release | dist | clean
└── run.sh                   # debug (logs in terminal) | release (open .app)
```

## 2. Build (`build.sh`)

| Command | Result |
|---|---|
| `./build.sh` / `./build.sh debug` | `swift build` → `build/debug/{{APP}}.app` (ad-hoc signed) |
| `./build.sh release` | same with `-c release` → `build/release/{{APP}}.app` |
| `./build.sh dist` | release build → **Developer ID signing (hardened runtime)** → notarized + stapled app → **DMG** → notarized + stapled DMG → `docs/appcast.xml` |
| `./build.sh clean` | removes `build/` and `.build/` |

### 2.1 App-bundle assembly (all modes)

Executable → `Contents/MacOS`, `Resources/Info.plist` → `Contents/`,
the app icon → `Contents/Resources/Assets.car` and a fallback `AppIcon.icns`
(actool, see 2.1.1), Sparkle.framework →
`Contents/Frameworks` (XPC services removed; the app is unsandboxed), PkgInfo,
then an ad-hoc signature with the entitlements; a signature that fails stops
the build. New resource files must be copied in `build.sh` explicitly.
`Resources/Art/` (the panel's artwork) goes to `Contents/Resources/Art`.

**The Audio Unit** is assembled in the same step: `lib{{APP}}AU.dylib` →
`Contents/PlugIns/{{APP}}.component/Contents/MacOS/{{APP}}`, with
`Resources/AudioUnit-Info.plist` as its `Info.plist`. The dylib exports only
the factory function `{{APP}}AUFactory` (`Package.swift`), because a plug-in
shares the host's process with other plug-ins. `Resources/Art/` is copied
into the component too: its own window (the class `{{APP}}AUViewFactory`,
which the host finds through the unit's CocoaUI property) shows the app's
panel. `build.sh` writes the app's version into that plist (both strings and
the numeric `AudioComponents` version, `major << 16 | minor << 8 | patch`),
so the version is bumped in one place. The component is signed before the
app (ad-hoc, or Developer ID + hardened runtime in `dist`). Users install it
from the app: Settings › Install Audio Unit copies it to
`~/Library/Audio/Plug-Ins/Components`.

Check a build of the plug-in with Apple's validator:

```
cp -R build/release/{{APP}}.app/Contents/PlugIns/{{APP}}.component ~/Library/Audio/Plug-Ins/Components/
auval -v aumu {{AU_SUBTYPE}} JPis        # must end with AU VALIDATION SUCCEEDED
```

### 2.1.1 App icon (actool)

- `Resources/AppIcon.png` is the master: 1024 px, full bleed and opaque (no
  transparent corners, no own squircle). macOS 27 masks it to the icon shape.
  A plain `.icns` that does not fill the shape is put small on a light tile,
  which is why the icon is not built with `sips` + `iconutil`.
- `Resources/AppIcon.icon` is an Icon Composer document (`icon.json`: one
  layer, glass, shadow, translucency and specular off, an indigo fill) that
  holds no image in the repo. `build.sh` copies it to a temporary folder and
  puts the master in as `Assets/AppIcon.png`; actool does not follow a symlink
  there.
- One actool call compiles it into `Contents/Resources/Assets.car` and a
  fallback `AppIcon.icns` before anything is signed, in every mode (so `dist`
  ships the same icon as `release`):
  ```
  xcrun actool <tmp>/AppIcon.icon --compile <tmp>/out \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist <tmp>/partial.plist \
    --app-icon AppIcon --include-all-app-icons --enable-on-demand-resources NO \
    --development-region en --target-device mac --minimum-deployment-target 27.0 \
    --platform macosx
  ```
  `Info.plist` carries what the partial plist asks for: `CFBundleIconName`
  and `CFBundleIconFile`, both `AppIcon`. Without Xcode (only the Command
  Line Tools selected) the build stops with a hint to run
  `sudo xcode-select -s /Applications/Xcode.app`.
- `docs/assets/icon.png` (256 px, the system's squircle applied) is drawn from
  the same artwork; regenerate it when the master changes. The art, its prompt
  and Codex's notes: `.planning/design/icon/`.

### 2.2 Distribution (`dist`)

1. Sign Sparkle's parts inside-out, then the Audio Unit's component, then the
   app with the first "Developer ID Application" identity in the Keychain,
   hardened runtime, timestamp.
2. Notarize the zipped app (`notarytool --keychain-profile notary --wait`), staple it.
3. Build `build/{{APP}}.dmg` (app + Applications symlink), sign, notarize, staple.
4. `scripts/make_appcast.py` signs the stapled DMG with Sparkle's `sign_update`
   (EdDSA private key from the login Keychain) and writes `docs/appcast.xml`:
   version, release notes from the CHANGELOG section, the GitHub Release
   download URL, length and signature. Create the GitHub Release (DMG uploaded
   as `{{APP}}-<version>.dmg`) **before** pushing the appcast, so the feed
   never points at a missing file.

A notarization `HTTP status code: 403. A required agreement is missing or has
expired` is an account issue: accept the updated agreement at
developer.apple.com/account.

### 2.3 One-time signing setup (per machine)

1. A **Developer ID Application** certificate in the login keychain.
2. A stored notarization profile named `notary` (or set `NOTARY_PROFILE`):
   ```
   xcrun notarytool store-credentials notary \
     --apple-id <apple-id-email> --team-id <TEAMID> --password <app-specific-password>
   ```
3. The Sparkle EdDSA key: `.build/artifacts/sparkle/Sparkle/bin/generate_keys`
   keeps the private key in the login Keychain and prints the public key that
   lives in `Info.plist` (`SUPublicEDKey`). Back it up
   (`generate_keys -x <file>`, kept offline): without it no update can ever be
   signed for existing installs again.

### 2.4 Entitlements & sandbox policy

The app ships **unsandboxed** (`com.apple.security.app-sandbox = false`),
which is fine for Developer ID / DMG distribution; Gatekeeper needs the
hardened runtime and notarization. Add entitlements to
`Resources/{{APP}}.entitlements` only when a feature needs them.

## 3. Run (`run.sh`)

- `./run.sh debug` *(default)* — rebuilds when anything under `Sources/` or
  `Resources/` is newer than the binary, registers the bundle with Launch
  Services, then runs the binary in the terminal: logs stream live, Ctrl+C quits.
- `./run.sh release` — rebuilds if stale, then `open`s the app.

## 4. Development Methodology

- Logic goes into `{{APP}}Core`, test first (`swift test`); the UI is checked
  by running the app.
- Conventional Commits with a scope: `feat(core): …`, `fix(ui): …`,
  `docs(manual): …`, `chore(release): v1.2.0 — …`.
- `main` is always green: builds, tests pass, the app launches.

### Phases

- `.planning/ROADMAP.md` lists phases (newest first) with status;
  `.planning/STATE.md` says where work stands and what comes next.
- One phase = `.planning/phases/NN-slug/` (`PLAN.md`, `VERIFICATION.md`) =
  one branch `feature/NN-slug` = one `--no-ff` merge into `main`.
- Definition of done: acceptance criteria checked, `swift test` green, app
  built and run, CHANGELOG and manual updated, ROADMAP/STATE updated.
- The first phases make the instrument: 01 skeleton (the platform template
  rendered, green on its placeholder engine), 02 engine (the approved prototype
  as the engine, equal to its reference), 03 art (the panel's look), 04 panel, app,
  Audio Unit and manual, 05 icon and website, 06 the 1.0.0 release.

### Versioning & releases

- The version lives in `Resources/Info.plist` (`CFBundleShortVersionString`
  and `CFBundleVersion`), semantic versioning. The skeleton carries 0.1.0 until
  the first release, which is 1.0.0.
- Releases follow the project skill `.claude/skills/release/SKILL.md`.
- Pushes to GitHub happen only after explicit confirmation.
