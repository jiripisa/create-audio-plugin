"""Tests for `scaffold.py --templates` of the new-macos-app skill."""
import filecmp
import json
import subprocess
import tempfile
import unittest
from datetime import date
from pathlib import Path

SCAFFOLD = Path.home() / ".claude/skills/new-macos-app/scripts/scaffold.py"
CONFIG = {
    "APP": "Foo", "APP_NAME": "Foo Bar", "APP_LOWER": "foo", "BUNDLE_ID": "io.jp4.foo",
    "OWNER": "someone", "AUTHOR": "A B", "TAGLINE": "does x", "LICENSE_KEY": "none",
    "LICENSE_LABEL": "All rights reserved", "WEBSITE": True, "MANUAL": True,
    "PUBLIC": True, "CS": True, "TAGLINE_CS": "dělá x", "PLANNING": True,
}
# The change to scaffold.py (a file of the new-macos-app skill, outside this repo), kept here.
PATCH = Path(__file__).parent.parent / "patches" / "new-macos-app-scaffold.diff"
# Render of the built-in templates made before --templates existed, on 2026-11-24.
BEFORE = Path(__file__).parent / "fixtures" / "builtin-render"
FIXTURE_DATE = "2026-11-24"


def scaffold(tmp: Path, out: Path, extra_cfg=None, templates=None) -> subprocess.CompletedProcess:
    cfg_path = tmp / "cfg.json"
    cfg_path.write_text(json.dumps({**CONFIG, **(extra_cfg or {})}))
    cmd = ["python3", "-I", str(SCAFFOLD), "--config", str(cfg_path), "--out", str(out)]
    if templates:
        cmd += ["--templates", str(templates)]
    return subprocess.run(cmd, capture_output=True, text=True)


def same_tree(cmp: filecmp.dircmp) -> bool:
    return (not cmp.left_only and not cmp.right_only and not cmp.diff_files
            and not cmp.funny_files and all(same_tree(c) for c in cmp.subdirs.values()))


def pin_date(tree: Path) -> None:
    """Rewrite today's date and year in a rendered tree to the fixture's."""
    today = date.today()
    for path in tree.rglob("*"):
        if path.is_file():
            text = path.read_text()
            fixed = text.replace(today.isoformat(), FIXTURE_DATE)
            fixed = fixed.replace(f"© {today.year}", f"© {FIXTURE_DATE[:4]}")
            if fixed != text:
                path.write_text(fixed)


class ScaffoldTemplatesTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_custom_templates_dir(self):
        tpl = self.tmp / "tpl"
        (tpl / "__APP__").mkdir(parents=True)
        (tpl / "__APP__" / "x.txt").write_text("{{APP}}-{{AU_SUBTYPE}}")
        out = self.tmp / "out"
        result = scaffold(self.tmp, out, {"AU_SUBTYPE": "Fooo"}, tpl)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((out / "Foo" / "x.txt").read_text(), "Foo-Fooo")

    def test_default_unchanged(self):
        out = self.tmp / "after"
        result = scaffold(self.tmp, out)
        self.assertEqual(result.returncode, 0, result.stderr)
        pin_date(out)
        self.assertTrue(same_tree(filecmp.dircmp(BEFORE, out, ignore=[])))

    def test_build_leftovers_at_the_top_are_skipped(self):
        # What a build, an indexing editor or git leaves at the top of the template tree is not
        # the template; the same names deeper down, and names that only start alike, are.
        tpl = self.tmp / "tpl"
        skipped = [".build/index-build/x.txt", "build/release/x.txt", ".swiftpm/x.txt", ".git/config",
                   ".DS_Store", "docs/.DS_Store"]
        kept = ["build.sh", ".gitignore", "docs/build/x.txt", "Sources/__APP__/.build/x.txt", ".claude/x.txt"]
        for rel in skipped + kept:
            (tpl / rel).parent.mkdir(parents=True, exist_ok=True)
            (tpl / rel).write_text("{{APP}}")
        out = self.tmp / "out"
        result = scaffold(self.tmp, out, templates=tpl)
        self.assertEqual(result.returncode, 0, result.stderr)
        rendered = sorted(p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file())
        self.assertEqual(rendered, sorted(rel.replace("__APP__", "Foo") for rel in kept))
        self.assertEqual((out / "build.sh").read_text(), "Foo")

    def test_installed_scaffold_is_the_original_with_the_repo_patch(self):
        # patches/new-macos-app-scaffold.diff taken back out of the installed scaffold.py leaves
        # no rejected hunk: the patch in the repo is what the tests here run against.
        result = subprocess.run(["patch", "-p1", "-R", "--dry-run", "-d", str(SCAFFOLD.parent.parent), "-i", str(PATCH)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAILED", result.stdout)

    def test_binary_files_copied(self):
        tpl = self.tmp / "tpl"
        tpl.mkdir()
        data = bytes([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE, 0x00, 0x80])
        (tpl / "icon.png").write_bytes(data)
        (tpl / "blob.bin").write_bytes(b"\xff\xfe{{APP}}\x80")  # not UTF-8, no known suffix
        out = self.tmp / "out"
        result = scaffold(self.tmp, out, templates=tpl)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((out / "icon.png").read_bytes(), data)
        self.assertEqual((out / "blob.bin").read_bytes(), b"\xff\xfe{{APP}}\x80")


if __name__ == "__main__":
    unittest.main()
