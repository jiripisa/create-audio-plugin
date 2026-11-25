# Codex (phases 03 and 05)

Codex (OpenAI's CLI, `codex exec`, with an image tool) draws the panel concepts, the panel's
assets, the app icon and the website's look. The main session runs every job; subagents do not.
Jobs run in the background, in parallel with the engine.

## Invocation

One scratch folder per job, `<scratch>/codex-<job>/` (`concepts`, `assets`, `icon`, `site`), each
with `PROMPT.md` and a `reference/` folder of images (copies, never links into the project).

```
cd <scratch>/codex-<job>
codex exec --skip-git-repo-check -s workspace-write \
  --add-dir "$HOME/.codex/generated_images" -C "$PWD" -o last-message.txt \
  "Read PROMPT.md in the current directory and do exactly what it says. Look at the images in reference/ first. Do not stop to ask questions." \
  < /dev/null > codex.log 2>&1
```

Run it with the Bash tool's `run_in_background`. The guards, each learned from a hang:
- `< /dev/null` always: without it Codex waits on stdin ("Reading additional input from
  stdin…"); a job sat like this for over an hour.
- `--add-dir ~/.codex/generated_images`: the image tool stages every image there; without it
  Codex stopped to ask for permission and sat 30 minutes.
- "Do not stop to ask questions" in the command and in every `PROMPT.md`.
- **Wait on `last-message.txt`** (non-empty), not on the process: once the wrapper stayed alive
  after Codex had finished. When the file is there, look for leftovers
  (`pgrep -fl "codex exec"`) and kill the ones of this job; their later "exit 144" notice is
  that kill, not a failure.
- Watch `codex.log` (`tail -n 40`) when a job runs much longer than its siblings (a concepts job
  takes tens of minutes): a question, a permission prompt or a stdin wait means it is stuck.
  Kill it, fix the prompt, run it once more. A second failure or a refused command (sandbox,
  permission, network) is not retried: record it in `VERIFICATION.md` and use the no-Codex
  fallback for that job. Permission settings are never changed.

After each job, look at every image yourself (Read the PNGs), check sizes and alpha with
`sips -g pixelWidth -g pixelHeight -g hasAlpha <file>`, and keep briefs, prompts, notes and the
chosen images in `.planning/design/<job>/` once phase 03 (or 05) is on its branch.

## No Codex

`codex --version` fails at intake, or Codex is refused: the look is **native SwiftUI / Liquid
Glass without raster art** (said in the intake message). Then:
- no `Resources/Art/`; `Artwork.swift` keeps the system colours or gets a palette of two or three
  colours chosen by the main session from the instrument [call];
- the icon: a scratch Swift program in `<scratch>/icon/` (AppKit, a 1024 x 1024 bitmap with no
  alpha channel, full bleed: a gradient of the palette and one simple glyph or the initial; no
  rounded tile, no transparent corners) writes `Resources/AppIcon.png`. `make_icon.swift` of
  `new-macos-app` does not fit: it draws a rounded tile with transparent corners;
- the website: the template's `site.css` with the palette (the `frontend-design` skill for the
  look), no hero art: `assets/hero-<slug>.jpg` is the real window capture converted with
  `sips -s format jpeg`, and the ornament's `<img>` and CSS uses are replaced by a CSS rule, tag
  for tag in EN and CS.

## Concepts (phase 03)

`reference/`: `skeleton-keyboard.png` (phase 01's capture of the template's window, if one was
made). Fill every `<…>`; the controls come from spec §6 with their default values as the example
values.

```markdown
# Design concepts for "<APP_NAME>" — a synthesized <instrument> for macOS

Use your image generation tool to create UI mockups, then save them as PNG files in the current
working directory with the exact names given below.

## The product
<APP_NAME> is a software instrument: a native macOS 27 app and an Audio Unit plug-in that shows
the same window inside music hosts (Ableton Live, Logic Pro). It synthesizes <the instrument, in
two or three concrete sentences: what it is made of, how it is played, where it comes from>. It
is played <melodically / mainly for rhythm / as a drone>.
<If reference/skeleton-keyboard.png exists:> `reference/skeleton-keyboard.png` is the window's
structure as built today: header, titled knob sections in Liquid Glass cards, the mode area below.
Keep that structure; the look is new and must be the product's own.

## What the window must show (every mockup must contain these, legibly)
**Header bar:** the "<APP_NAME>" wordmark with a small emblem; a Program menu (value
"<kPrograms[0] name>") and a Preset menu (value "<an example name>"); a segmented switch
**Keyboard | Pads**; buttons **LFO 1**, **LFO 2**, **VEL**, **MIDI**; a settings gear.
**Knob sections, each titled, every label once, each knob with its name above and its value below:**
- **<Section>:** <Name> <value unit>, … (one line per kSections entry, every knob, switches as
  "a 2-way switch **A | B**")
- **Master:** Volume 0.0 dB, Pan 0 %, Tune 0 ct, Octave 0, Bend Up 2 st, Bend Down 2 st, a switch
  **Voice Mode: Poly | Mono | Legato**, Glide 0 ms, a switch **LFO Start: Hit | Free**, LFO 1 Rate
  6.0 Hz + LFO 1 Shape (small menu "Sine"), LFO 2 Rate 2.0 Hz + LFO 2 Shape, Vel Sens 70 %.
That is <n> knobs. They must stay readable (modest knob caps, strong contrast for labels and
values). Arrange the sections in a balanced grid; every control visible.
**Mode area, below the knobs:**
- *Keyboard mode:* a three-octave on-screen keyboard strip, a "Last note" readout and a **Send to
  pad** button, with the instrument's artwork placed decoratively in this area.
- *Pad mode:* a **4 × 4 grid of 16 pads**, MPC-style. Each pad shows its number, its sound's name
  (<the default kit's program names>), its pitch (e.g. "C2") and its group (e.g. "G1" or "Off").
  One pad is selected; beside the grid a small inspector shows its Pitch and Group, and a Kit menu.

## Look and feel
- **Motif:** <the instrument itself, its materials, the craft and places it belongs to>.
  <For an instrument of a living tradition:> Ornament is a craft-inspired, abstract
  interpretation, not a copy of a traditional design or symbol.
- **macOS 27 Liquid Glass:** translucent glass cards, segmented controls and buttons floating over
  the artwork. A modern Mac app, not a skeuomorphic plug-in from 2005.
- Controls clearly usable: high contrast for labels and values, knobs that read at a glance.

## Deliverables
Make **<three | two> clearly different concepts**, each with a name and a direction:
1. **"<name>"** — <direction>
2. **"<name>"** — <direction>
<3. **"<name>"** — <direction>>
If you have a better idea for one of them, use it, but keep the concepts strong and distinct.
For each concept two images at landscape 16:10 (about 1600 × 1000):
`concept-N-keyboard.png`, `concept-N-pads.png`.
Then write `concepts.md` with a short section per concept: its name and idea; the palette (hex
values); the materials and ornament; the typography; which parts are **raster artwork**
(background, instrument figure, logo, knob cap, ornament band) and which are **native SwiftUI /
Liquid Glass controls**.

Your image tool's automatic staging under `$CODEX_HOME/generated_images/` is fine: copy the final
PNGs from there into the current directory. Apart from that, write nothing outside the current
working directory. Do not stop to ask questions: make sensible choices and note them in
`concepts.md`.
```

**The pick.** "Three concepts" [user at intake]: three concepts; show the six images to the user
(`open <scratch>/codex-concepts`, Quick Look) with a one-line description each and the main
session's recommendation, ask which one; the engine work goes on meanwhile. "Leave it to me":
two concepts; the main session picks and writes why in `.planning/design/concepts/choice.md`
(identity of the instrument, contrast and readability, distinct from the siblings, how well it
carries Liquid Glass) [call]. Either way the choice goes into the spec §10 as an amendment.

## Assets (phase 03)

`reference/`: the chosen concept's two mockups. Fill `<…>` from `concepts.md`.

```markdown
# Artwork assets for "<APP_NAME>" — concept <N> "<name>"

Use your image generation tool to create the artwork below, then save each as a PNG in the current
working directory with the exact name given. The approved mockups are
`reference/concept-<N>-keyboard.png` and `reference/concept-<N>-pads.png`: match their look.

<APP_NAME> is a synthesized <instrument> for macOS 27 (app and Audio Unit). The panel is built in
SwiftUI: every label, value, knob pointer and arc, pad, key, menu and button is drawn live in code
with Liquid Glass. You make ONLY the decorative raster art the code places behind or under them.

**Absolute rule: no text, letters, digits, labels, UI controls, knobs (except the requested blank
cap), pads, keys, buttons, arcs or highlights baked into any image** (the wordmark is live text
too).

Palette: <hex values with their roles>. Mood: <from concepts.md>. <Craft-inspired interpretation,
not a reproduction of a documented pattern.>

## Deliverables
1. `background.png` — **2200 × 1375** (16:10), opaque. The whole window background: <ground>.
   Calm and dark (or calm and even) everywhere so that glass cards and text on top stay readable;
   no focal object.
2. `figure.png` — **1200 × 1200**, transparent background (real alpha). The instrument: <what, which
   view>, the whole object within generous margins, a soft contact shadow allowed, no background,
   no table.
3. `logo.png` — **512 × 512**, transparent background. A simple emblem of <…> (as beside the
   wordmark in the mockup), a strong silhouette usable at 40 pt. No text.
4. `knob.png` — **512 × 512**, transparent background. A round knob cap seen straight from above,
   <material>, a fine bevel ring, a soft drop shadow inside the canvas. **Rotationally symmetric,
   with NO pointer, notch, tick or marking**, centred, cap diameter about 80 % of the canvas (code
   draws the pointer and the value arc).
5. `ornament.png` — **2400 × 64**, transparent background. A horizontal band of <ornament> (as the
   dividers in the mockups) that tiles seamlessly left to right (the right edge continues the left
   edge).

## Process
- Generate, then normalise each file to the exact pixel size with macOS `sips`, keeping
  transparency where required.
- Check alpha: `sips -g hasAlpha <file>` must say yes for 2–5, with real zero-alpha pixels around
  the objects (no checkerboard painted in).
- Composite the assets on the background in the mockup's layout as a check (keep it as
  `composite-check.png`) and fix what looks wrong: fringes, a cap that is not symmetric, an
  ornament seam.
- Write `assets.md`: one line per file (size, alpha, what it is), your choices, the generation
  prompts.

Your image tool's automatic staging under `$CODEX_HOME/generated_images/` is fine: copy the final
PNGs from there into the current directory. Apart from that, write nothing outside the current
working directory. Do not stop to ask questions: make sensible choices and note them in
`assets.md`.
```

**Round 2.** Look at every asset next to the mockups and at `composite-check.png`. An asset that
is weak (a knob too busy or too faint, an ornament too thin, a seam, fringes) gets a second job
`PROMPT2.md` in the same folder naming only those files and what is wrong with each. One round is
usually not enough (Brumle redid the knob and the ornament).

## Icon (phase 05, started during phase 04)

`reference/`: `figure.png`, `background.png`, the chosen keyboard mockup.

```markdown
# App icon for "<APP_NAME>" (macOS 27)

Use your image generation tool to create the app icon artwork, then save it as `AppIcon.png` in
the current working directory.

<APP_NAME> is a synthesized <instrument> (<one sentence on what it looks like>) for macOS 27. Its
panel look is "<concept name>": <palette and materials>. References in `reference/`: `figure.png`
(the panel's instrument), `background.png` (the panel's ground), `concept-<N>-keyboard.png` (the
whole panel).

## Requirements
- **1024 × 1024, fully opaque, full-bleed square artwork.** Do NOT draw the macOS rounded tile, a
  squircle, a frame, a drop shadow around the tile, or transparent corners: macOS applies its own
  mask to the full square. The art must fill every pixel to the edges.
- Subject: <the instrument>, large and centred (about 70 % of the height, kept well inside the
  central ~80 % so the system mask never clips it), on <the ground>.
- Bold, simple, readable at 32 px: a strong silhouette, <contrast>, soft light, little fine
  detail. No text, letters or digits.
- Save as `AppIcon.png` (sRGB, no alpha channel). Check with `sips -g pixelWidth -g pixelHeight
  -g hasAlpha AppIcon.png` (1024, 1024, no). Also save `preview-32.png` and `preview-128.png`
  (downscaled with `sips -Z`) and look at them.
- Write `icon.md` with the generation prompt and your checks.

Your image tool's automatic staging under `$CODEX_HOME/generated_images/` is fine: copy the final
PNG from there into the current directory. Apart from that, write nothing outside the current
working directory. Do not stop to ask questions.
```

The icon is compiled by `build.sh` with actool from `Resources/AppIcon.png` and the Icon Composer
document `Resources/AppIcon.icon`, never with `iconutil` (`development_workflow.md` §2.1.1).

## Website look (phase 05)

Copy `docs/` to `<scratch>/codex-site/docs/` after the texts and screenshots are final. `reference/`:
the chosen mockups, `app-keyboard.png` and `app-pads.png` (captures of the real app), the five
panel assets, `AppIcon.png`; and as a model of the kind of work wanted, if it exists,
`~/Development/Claude/Fanfrnoch/.planning/design/site/DESIGN.md` copied as
`reference/sibling-site-DESIGN.md`. Copy the result back file by file after review.

```markdown
# <APP_NAME> — a website look

<APP_NAME> is a synthesized <instrument> for macOS 27: an app and an Audio Unit. <Two sentences on
the real instrument.> Its window wears the "<concept name>" look: see
`reference/concept-<N>-keyboard.png`, `reference/concept-<N>-pads.png` (the approved mockups),
`reference/app-keyboard.png` and `reference/app-pads.png` (the real app), the panel's artwork in
`reference/` (`background.png`, `figure.png`, `logo.png`, `knob.png`, `ornament.png`) and the app
icon `reference/AppIcon.png`.

Palette: <hex values with roles: ground, cards, headings, accent, body text>. Mood: <…>.
<Ornament is a craft-inspired interpretation, not a reproduction of a documented design.>

Work only in the current directory. Do not stop to ask; make choices and write them down.

## The website: `docs/`
`docs/` is a copy of the project's GitHub Pages site: an overview (`index.html`), a manual
(`manual.html`) and the same two in Czech (`cs/`), styled by `assets/site.css` and
`assets/manual.css`. The texts are final. The styles are a neutral template;
`reference/sibling-site-DESIGN.md` (if present) describes a sibling app's site as a model of the
kind of work wanted, not of its colours. Restyle the site for <APP_NAME>:
1. A look for the site from the app: ground, headings, body text, links and buttons in the
   palette (check the contrast of text on the button and of links on the ground), a display face
   for headings as in the app (`"New York", ui-serif, Georgia, serif` or the app's), the system
   sans for body.
2. Graphics with your image tool, in `docs/assets/`: a **hero illustration**
   `assets/hero-<slug>.jpg` (the pages already point at this name), wide, about 2400 × 1000, the
   instrument as in `reference/figure.png` and the icon, calm space for the heading, the lede and
   the download button; a **tileable ornament band** `assets/ornament.png` adapted from
   `reference/ornament.png`; optionally a quiet page texture. Each image under ~600 KB (JPEG for
   painted art, PNG only where alpha is needed); no text in images. Remove images you made and do
   not use.
3. Apply it: `assets/site.css` (and `assets/manual.css` only as needed: keep its `.fig`, `.view`,
   `.mark` figure system working and the marks over their controls), the HTML of `index.html` and
   `cs/index.html` only where the look needs it. **Every change to an English page goes to its
   Czech twin, tag for tag**; change no wording. Keep every link, download URL and version string
   as it is. Keep `assets/icon.png` and `assets/<slug>-window.png` as they are. No third-party web
   fonts, no JS frameworks, no page JavaScript. The first comment line of each CSS file names the
   <APP_NAME> look.
4. It must read well at 1440 px and at 400 px wide (no horizontal page scroll) and respect
   `prefers-reduced-motion` if anything moves (prefer not).
5. Check it yourself: render the pages with headless Chrome (`--user-data-dir` inside this
   directory, removed afterwards), look at the screenshots, fix what is off; save them in `shots/`.

## Deliverables
- the edited `docs/` with the new images;
- `shots/*.png`: overview EN at 1440 and 400, CS overview at 1440 and 400, manual EN at 1440, one
  zoomed manual figure showing its marks still on their controls;
- `DESIGN.md`: the look in a few lines (palette roles, type, graphics, what changed in which file),
  your choices, how you made and checked the images, anything you could not do.

Your image tool's staging under `$CODEX_HOME/generated_images/` is fine; copy finals here. Write
nothing else outside this directory.
```

Our own review (Playwright at 1440 and 400, tag for tag) follows in phase 05; Codex's
screenshots are not the check.
