"""The listening prototype's harness and the template's engine must stay in step: the template's
reference copy of the harness is the harness, and the numbers the harness plays by are the engine's."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).parent.parent
HARNESS = ROOT / "scripts" / "spike_harness.h"
TEMPLATE = ROOT / "templates"
ENGINE = TEMPLATE / "Sources" / "__APP__DSP" / "__APP__Engine.cpp"
DSP_HEADER = TEMPLATE / "Sources" / "__APP__DSP" / "include" / "__APP__DSP.h"
VOICE_RANDOM = TEMPLATE / "Sources" / "__APP__DSP" / "VoiceRandom.h"


def number(text: str, pattern: str) -> float:
    match = re.search(pattern, text)
    assert match, pattern
    return float(match.group(1).rstrip("f"))


class HarnessCopiesTest(unittest.TestCase):
    def test_the_templates_reference_harness_is_the_harness(self):
        copy = TEMPLATE / "Tests" / "__APP__Reference" / "spike_harness.h"
        self.assertEqual(copy.read_bytes(), HARNESS.read_bytes(),
                         "cp scripts/spike_harness.h templates/Tests/__APP__Reference/")

    def test_voice_seed_and_draws_are_the_same(self):
        harness, platform = HARNESS.read_text(), VOICE_RANDOM.read_text()
        for line in ("inline constexpr uint32_t kVoiceSeed = 0x51ED270Bu;",
                     "inline double uniform(std::mt19937& rng) { return double(rng() >> 8) * (1.0 / 16777216.0); }",
                     "inline double white(std::mt19937& rng) { return (2.0 * uniform(rng) - 1.0) * 1.7320508075688772; }"):
            self.assertIn(line, harness)
            self.assertIn(line, platform)

    def test_the_harness_plays_by_the_engines_numbers(self):
        harness, engine, header = HARNESS.read_text(), ENGINE.read_text(), DSP_HEADER.read_text()
        pairs = [
            (r"inline constexpr int kControlFrames = (\d+);", engine, r"constexpr int kControlFrames = (\d+);"),
            (r"inline constexpr int kMaxHeld = (\d+);", engine, r"constexpr int kMaxHeld = (\d+);"),
            (r"inline constexpr float kStealMs = ([\d.]+f);", engine, r"static constexpr float kStealMs = ([\d.]+f);"),
            (r"inline constexpr double kFollowSeconds = ([\d.]+);", engine, r"static constexpr double kFollowSeconds = ([\d.]+);"),
            (r"inline constexpr int kMaxVoices = (\d+);", header, r"\{\{APP_UPPER\}\}_MAX_VOICES = (\d+)"),
            (r"inline constexpr int kFirstPadNote = (\d+);", header, r"\{\{APP_UPPER\}\}_FIRST_PAD_NOTE = (\d+)"),
        ]
        for ours, theirs_text, theirs in pairs:
            self.assertEqual(number(harness, ours), number(theirs_text, theirs), ours)
        # The fade of a stolen or re-hit voice and where it leaves the pool, the glide's step and
        # the velocity's gain: the same expressions in both.
        for expression in ("const float tc = std::max(ms, 1.0f) * 0.001f / 4.6f;",
                           "s.glide = (next > 0.0f) == (s.glide > 0.0f) ? next : 0.0f;",
                           "if (s.choking) s.chokeGain *= s.chokeMul;"):
            self.assertIn(expression, harness)
            self.assertIn(expression, engine)
        self.assertIn("s.choking && s.chokeGain < 1e-5f", harness)
        self.assertIn("s.choking && s.chokeGain < 1e-5f", engine)


if __name__ == "__main__":
    unittest.main()
