# create-audio-plugin

A Claude Code skill that creates a macOS audio plugin (Audio Unit) project, built on the
`new-macos-app` skill: it renders a plugin template from this repo with that skill's `scaffold.py`
(`--templates`), then continues with the usual repo, build and release setup.

Install: `ln -s "$PWD" ~/.claude/skills/create-audio-plugin`

Tests: `python3 -m unittest tests/test_scaffold_templates.py` (needs `~/.claude/skills/new-macos-app`).
