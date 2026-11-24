"""Tests for scripts/identity.py of the create-audio-plugin skill."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

IDENTITY = Path(__file__).parent.parent / "scripts" / "identity.py"
BUILT_IN_TAKEN = {"Brml", "Fanf", "Didg"}


def run(name: str, *args: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp) / name
        d.mkdir()
        return subprocess.run(
            ["python3", "-I", str(IDENTITY), str(d), "--no-auval", "--owner", "someone", *args],
            capture_output=True, text=True)


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


if __name__ == "__main__":
    unittest.main()
