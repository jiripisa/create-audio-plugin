# create-audio-plugin

A Claude Code skill that creates a macOS audio plugin (Audio Unit) project, built on the
`new-macos-app` skill: it renders a plugin template from this repo with that skill's `scaffold.py`
(`--templates`), then continues with the usual repo, build and release setup.

Install: `ln -s "$PWD" ~/.claude/skills/create-audio-plugin`

Tests: `python3 -m unittest discover -s tests` (the scaffold tests need
`~/.claude/skills/new-macos-app`); `tests/test_spike_analyze.sh` alone checks the spike harness and
the analysis tool.

Template check: `scripts/verify_template.sh [--quick] [--auval] [--capture]` renders `templates/`
for a dummy instrument into `$SCRATCH` (default `$TMPDIR`), builds it without warnings, runs its
tests and ends with `TEMPLATE OK`; `scripts/check_leftovers.sh [--skip-dir NAME]... <dir>` lists
words of `scripts/leftover-words.txt` that are still there. What each template file is:
`TEMPLATE_MANIFEST.md`.

Listening prototype: `scripts/spike_harness.h` (header-only C++17: scores, voice pool, seeded
noise, 24-bit WAV writer, `<dir>` / `--analyze` command line), with `scripts/spike_example.cpp` as
the pattern. Measuring recordings and renders: `swift scripts/analyze.swift <audio>... [--json]
[--tail a-b] [--window a-b] [--ref <audio>]`; its header documents the method and the JSON fields.
