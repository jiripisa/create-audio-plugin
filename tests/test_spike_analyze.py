"""Runs tests/test_spike_analyze.sh (spike harness and analysis tool) under unittest."""
import shutil
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parent / "test_spike_analyze.sh"


@unittest.skipUnless(all(shutil.which(t) for t in ("clang++", "swiftc", "afconvert", "jq")),
                     "needs clang++, swiftc, afconvert and jq (macOS with the developer tools)")
class SpikeAnalyzeTest(unittest.TestCase):
    def test_shell_checks(self):
        result = subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SPIKE ANALYZE OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
