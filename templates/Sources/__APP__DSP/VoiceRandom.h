// VoiceRandom.h - a voice's random numbers: the seed and the two ways a draw becomes a number.
// The same as in the listening prototype's harness (spike_harness.h: kVoiceSeed, uniform, white),
// so that a prototype's voice is ported draw for draw.
//
// The rule (Voice.h): a voice that needs random numbers owns a std::mt19937 and seeds it with
// kVoiceSeed in every fresh start (continuing == false); a continuing start goes on in the same
// stream. Nothing else is random (no generator shared between voices, no clock, no count of
// hits), so two equal notes render equal samples, in a debug and in a release build alike.
// Seeding and drawing neither allocate nor lock.

#pragma once

#include <cstdint>
#include <random>

namespace {{APP_LOWER}} {

// The seed of every voice's generator, at every fresh start. The same constant as the
// harness's: change neither.
inline constexpr uint32_t kVoiceSeed = 0x51ED270Bu;

// Uniform in [0, 1) from the top 24 bits, the same on every platform.
inline double uniform(std::mt19937& rng) { return double(rng() >> 8) * (1.0 / 16777216.0); }

// White noise with unit RMS (uniform, so its peaks are +-1.73).
inline double white(std::mt19937& rng) { return (2.0 * uniform(rng) - 1.0) * 1.7320508075688772; }

} // namespace {{APP_LOWER}}
