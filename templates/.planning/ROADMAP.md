# {{APP_NAME}} — Roadmap

Phases, newest first. One phase = one folder in `phases/`, one branch, one
`--no-ff` merge. Research: `research/reports/<!-- FILL: the research report's file name -->`.
Design: `specs/<!-- FILL: the spec's file name, <date>-instrument-design.md -->`.

Planned phases are ⬜, the open one ▶️. At the end of a phase its status becomes ✅ and its
goal ends with " — <date>" (or " — built on `feature/NN-slug` <date>, not merged yet" while it
waits for the merge), and says what was made in the instrument's own words.

| Phase | Goal | Status |
|---|---|---|
| 06-v1.0.0-release | Version 1.0.0: signed and notarized DMG, appcast, `auval` on the shipped component, GitHub repo and Release, Pages, catalog | ⬜ |
| 05-icon-website | The icon (actool, Icon Composer document) and the website: the overview of <!-- FILL: the instrument --> in English and Czech, the look by Codex, the real app's window, checked in headless Chrome at 1440 and 400 px | ⬜ |
| 04-app-and-audiounit | The panel of the approved look (<!-- FILL: the sections and how the cards are laid out -->), presets, kits and MIDI learn in the real app, the Audio Unit in a host, `auval`, the manual in English and Czech with pictures of the real app | ⬜ |
| 03-panel-design | The panel's look: <!-- FILL: "three concepts, the user picked N" or "two concepts, N chosen and why" -->; background, figure, logo, knob cap, ornament | ⬜ |
| 02-engine | `{{APP}}DSP`: <!-- FILL: the voice of the approved prototype in a few words -->, its knobs, programs and default kit (`Params.h`, `Voice.h`), equal to its reference (`{{APP}}Reference`) within −60 dB, regression references, `auval` | ⬜ |
| 01-skeleton | The platform template of `create-audio-plugin` rendered: identity aumu/{{AU_SUBTYPE}}/JPis, `{{BUNDLE_ID}}`, version 0.1.0; `swift build`, `swift test` (debug and release) green on the placeholder engine — {{TODAY}} | ▶️ |
