# create-audio-plugin

A Claude Code skill that creates a macOS audio plugin (Audio Unit) project, built on the
`new-macos-app` skill: it renders a plugin template from this repo with that skill's `scaffold.py`
(`--templates`), then continues with the usual repo, build and release setup.

Install: `ln -s "$PWD" ~/.claude/skills/create-audio-plugin`

The renderer is `new-macos-app`'s `scripts/scaffold.py` with a `--templates <dir>` option, which is
a change to that skill's file (outside this repo; built-in mode renders the same bytes as before).
The change is kept here as `patches/new-macos-app-scaffold.diff`, against the skill's original.
Check: `python3 -I ~/.claude/skills/new-macos-app/scripts/scaffold.py --help | grep -- --templates`.
Re-apply it after that skill was reinstalled or updated:
`patch -p1 -d ~/.claude/skills/new-macos-app < patches/new-macos-app-scaffold.diff`, then
`python3 -m unittest tests.test_scaffold_templates`.

Tests: `python3 -m unittest discover -s tests` (the scaffold tests need
`~/.claude/skills/new-macos-app`); `tests/test_spike_analyze.sh` alone checks the spike harness and
the analysis tool.

Template check: `scripts/verify_template.sh [--quick] [--auval] [--capture]` checks that
`templates/` holds nothing git ignores or does not track (the renderer would copy it into every
project), renders it for a dummy instrument into `$SCRATCH` (default `$TMPDIR`), builds it without
warnings, runs its tests and ends with `TEMPLATE OK`; `scripts/check_leftovers.sh [--skip-dir NAME]... <dir> [words]`
lists words of `scripts/leftover-words.txt` (a run's list) or of another words file
(`scripts/template-words.txt`, the template's own) that are still there. What each template file is:
`TEMPLATE_MANIFEST.md`.

Listening prototype: `scripts/spike_harness.h` (header-only C++17: scores, a voice pool that
plays them by the platform's rules (re-hit, Poly / Mono / Legato, glide, sustain pedal, bend, Vel
Sens, stealing, pads), a seeded generator per voice, 24-bit WAV writer, `<dir>` / `--analyze`
command line), with `scripts/spike_example.cpp` as the pattern; `tests/harness_rules.cpp` checks
the rules, and the template's own reference (`templates/Tests/__APP__Reference/`) is the harness,
so the template's equivalence tests compare the engine with it. Measuring recordings and renders: `swift scripts/analyze.swift <audio>... [--json]
[--tail a-b] [--window a-b] [--ref <audio>]`; its header documents the method and the JSON fields.
