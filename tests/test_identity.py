"""Tests for scripts/identity.py of the create-audio-plugin skill."""
import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unicodedata
import unittest
from pathlib import Path

IDENTITY = Path(__file__).parent.parent / "scripts" / "identity.py"
BUILT_IN_TAKEN = {"Brml", "Fanf", "Didg"}

_spec = importlib.util.spec_from_file_location("identity", IDENTITY)
identity_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(identity_mod)


def run(name: str, *args: str) -> subprocess.CompletedProcess:
    # --projects "": the tests do not depend on the projects of whoever runs them.
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / name
        d.mkdir()
        return subprocess.run(
            ["python3", "-I", str(IDENTITY), str(d), "--no-auval", "--owner", "someone", "--projects", "", *args],
            capture_output=True, text=True)


def audio_unit_plist(project: Path, subtype: str) -> None:
    """A project's Resources/AudioUnit-Info.plist, as the template renders it."""
    (project / "Resources").mkdir(parents=True)
    (project / "Resources" / "AudioUnit-Info.plist").write_bytes(plistlib.dumps(
        {"CFBundleName": project.name,
         "AudioComponents": [{"type": "aumu", "subtype": subtype, "manufacturer": "JPis"}]}))


def identity(name: str, *args: str) -> dict:
    result = run(name, *args)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


class IdentityTest(unittest.TestCase):
    def test_plain_name(self):
        got = identity("Strunobijec")
        self.assertEqual(got["APP_NAME"], "Strunobijec")
        self.assertEqual(got["APP"], "Strunobijec")
        self.assertEqual(got["APP_LOWER"], "strunobijec")
        self.assertEqual(got["APP_C"], "strunobijec")
        self.assertEqual(got["APP_UPPER"], "STRUNOBIJEC")
        self.assertEqual(got["BUNDLE_ID"], "io.jp4.strunobijec")
        self.assertEqual(got["AU_SUBTYPE"], "Stru")
        self.assertEqual(got["OWNER"], "someone")

    def test_diacritics_are_stripped_but_display_name_kept(self):
        got = identity("Čimbál")
        self.assertEqual(got["APP_NAME"], "Čimbál")
        self.assertEqual(got["APP"], "Cimbal")
        self.assertEqual(got["AU_SUBTYPE"], "Cimb")

    def test_spaces_and_digits(self):
        got = identity("Tape Loop 2")
        self.assertEqual(got["APP"], "TapeLoop2")
        self.assertEqual(got["APP_LOWER"], "tapeloop2")
        self.assertEqual(got["APP_C"], "tapeloop2")

    def test_short_name_is_padded_to_four_chars(self):
        got = identity("Ab")
        self.assertEqual(got["AU_SUBTYPE"], "Abab")

    def test_subtype_is_four_ascii_alnum_first_upper(self):
        for name in ("Ab", "X", "Čimbál", "Tape Loop 2", "a-b"):
            sub = identity(name)["AU_SUBTYPE"]
            self.assertRegex(sub, r"^[A-Z][A-Za-z0-9]{3}$", name)

    def test_taken_picks_next_candidate(self):
        self.assertEqual(identity("Strunobijec", "--taken", "Stru")["AU_SUBTYPE"], "Strn")

    def test_taken_is_case_sensitive(self):
        self.assertEqual(identity("Strunobijec", "--taken", "stru")["AU_SUBTYPE"], "Stru")

    def test_never_a_built_in_taken_code(self):
        for name in ("Fanfrnoch", "Brmlcek", "Didgeridoo"):
            self.assertNotIn(identity(name)["AU_SUBTYPE"], BUILT_IN_TAKEN)

    def test_no_letter_exits_2(self):
        result = run("123")
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stderr.strip())

    def test_leading_digit_exits_2(self):
        for name in ("808 Drum", "3rd Wave"):
            result = run(name)
            self.assertEqual(result.returncode, 2, name)
            self.assertIn("must start with a letter", result.stderr)

    def test_unsafe_characters_exit_2(self):
        # The display name goes into Swift strings, plists, XML, HTML and shell lines unescaped.
        for name in ('A"b', "Tom & Jerry", "a\\b", "Cash$", "A<b>", "Re: Mix", "Jim's", "No#1", "A.b"):
            result = run(name)
            self.assertEqual(result.returncode, 2, name)
            self.assertIn("letters, digits, spaces and hyphens", result.stderr, name)

    def test_space_or_hyphen_at_an_end_exits_2(self):
        for name in ("Bass-", "Bass ", "-Bass"):
            result = run(name)
            self.assertEqual(result.returncode, 2, repr(name))
            self.assertIn("start or end", result.stderr, repr(name))

    def test_safe_display_names_pass(self):
        for name in ("Čimbál", "Tape Loop 2", "Zkušebník Test", "a-b", "Ťuk-ťuk"):
            self.assertEqual(identity(name)["APP_NAME"], name)

    def test_decomposed_name_is_composed(self):
        decomposed = unicodedata.normalize("NFD", "Čimbál")
        self.assertEqual(identity(decomposed)["APP_NAME"], "Čimbál")

    def test_taken_entries_are_stripped(self):
        self.assertEqual(identity("Strunobijec", "--taken", "Brml, Stru")["AU_SUBTYPE"], "Strn")

    def test_subtypes_of_the_projects_beside_it_are_taken(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = Path(tmp)
            audio_unit_plist(projects / "Strunka", "Stru")          # an earlier instrument, not installed
            audio_unit_plist(projects / "Strunobijec", "Strn")      # the folder itself, already rendered once
            (projects / "Notes").mkdir()                            # a project that is no instrument
            (projects / "Broken" / "Resources").mkdir(parents=True)
            (projects / "Broken" / "Resources" / "AudioUnit-Info.plist").write_text("not a plist")
            def subtype(*extra: str) -> str:
                result = subprocess.run(
                    ["python3", "-I", str(IDENTITY), str(projects / "Strunobijec"), "--no-auval", "--owner", "someone", *extra],
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(result.stdout)["AU_SUBTYPE"]
            # "Stru" is another project's; its own "Strn" does not count against it.
            self.assertEqual(subtype("--projects", str(projects)), "Strn")
            self.assertEqual(subtype("--projects", ""), "Stru")
            # Several directories; one that does not exist holds nothing.
            self.assertEqual(subtype("--projects", str(projects / "nowhere"), "--projects", str(projects)), "Strn")

    def test_unreadable_project_plist_is_a_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = Path(tmp)
            (projects / "Broken" / "Resources").mkdir(parents=True)
            (projects / "Broken" / "Resources" / "AudioUnit-Info.plist").write_text("not a plist")
            (projects / "Strunobijec").mkdir()
            result = subprocess.run(
                ["python3", "-I", str(IDENTITY), str(projects / "Strunobijec"), "--no-auval", "--owner", "someone",
                 "--projects", str(projects)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("could not read", result.stderr)
            self.assertEqual(json.loads(result.stdout)["AU_SUBTYPE"], "Stru")

    def test_parse_auval(self):
        text = "aumu Fanf JPis  -  JPis: Fanfrnoch\nno match here\nAU Validation Tool\n"
        self.assertEqual(identity_mod.parse_auval(text), {"Fanf"})


if __name__ == "__main__":
    unittest.main()
