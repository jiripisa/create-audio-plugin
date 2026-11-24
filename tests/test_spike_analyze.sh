#!/bin/bash
# Check the spike harness (scripts/spike_harness.h, through scripts/spike_example.cpp) and the
# analysis tool (scripts/analyze.swift) against renders whose answer is known.
#
#   tests/test_spike_analyze.sh
#
# Builds into a new folder under $TMPDIR (never the repo) and removes it at the end. Prints
# SPIKE ANALYZE OK last on success; exits 1 on the first failed check.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/spike-analyze.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }
# within <value> <target> <tolerance>
within() { awk -v v="$1" -v t="$2" -v d="$3" 'BEGIN { exit !(v != "null" && v - t <= d && t - v <= d) }'; }
below() { awk -v v="$1" -v t="$2" 'BEGIN { exit !(v != "null" && v < t) }'; }

# --- the harness: build, render, determinism ------------------------------------------------

clang++ -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/scripts/spike_example.cpp" -o "$WORK/spike" \
    || fail "spike_example.cpp does not build without warnings"
ok "spike_example.cpp builds (clang++ -std=c++17 -O2, no warnings)"

"$WORK/spike" "$WORK/renders" > "$WORK/render.log" || fail "the example's renders failed"
COUNT=$(find "$WORK/renders" -name '*.wav' | wc -l | tr -d ' ')
[ "$COUNT" -ge 6 ] || fail "expected at least 6 renders, got $COUNT"
[ ! -e "$WORK/renders/references" ] || fail "the example created a references folder"
ok "$COUNT renders written, no references folder created"

"$WORK/spike" "$WORK/again" 00_check > /dev/null
for f in "$WORK"/again/*.wav; do
    cmp -s "$f" "$WORK/renders/$(basename "$f")" || fail "$(basename "$f") differs between two runs"
done
[ "$(find "$WORK/again" -name '*.wav' | wc -l | tr -d ' ')" -eq 4 ] || fail "prefix 00_check did not select 4 renders"
ok "renders are deterministic; a name prefix selects renders"

TONE="$WORK/renders/00_check_A_tone_220Hz.wav"
NOISE="$WORK/renders/00_check_B_noise_tail.wav"
WEAK="$WORK/renders/00_check_C_weak_fundamental.wav"
EVEN="$WORK/renders/00_check_D_even_partials.wav"
for f in "$TONE" "$NOISE" "$WEAK" "$EVEN"; do [ -f "$f" ] || fail "missing render $(basename "$f")"; done
afinfo "$TONE" | grep -q "24-bit" || afinfo "$TONE" | grep -q "Int24" || fail "the tone is not a 24-bit WAV"

QUICK=$("$WORK/spike" --analyze 00_check_A) || fail "--analyze failed"
echo "$QUICK" | sed 's/^/    /'
QF0=$(echo "$QUICK" | awk '$1 == "f0" { print $2 }')
QH2=$(echo "$QUICK" | awk '$1 == "H2" { print $2 }')
within "$QF0" 220 0.5 || fail "--analyze f0 $QF0, want 220 +- 0.5"
within "$QH2" -6 0.5 || fail "--analyze H2 $QH2 dB, want -6 +- 0.5"
ok "--analyze: f0 $QF0 Hz, H2 $QH2 dB"

# --- the analysis tool ------------------------------------------------------------------------

swiftc -O "$ROOT/scripts/analyze.swift" -o "$WORK/analyze" 2> "$WORK/swiftc.log" \
    || { cat "$WORK/swiftc.log" >&2; fail "analyze.swift does not compile"; }
ANALYZE="$WORK/analyze"

J=$("$ANALYZE" --json "$TONE" "$NOISE" "$WEAK" "$EVEN") || fail "analyze --json failed"
field() { echo "$J" | jq -r "$1"; }

[ "$(field '.files | length')" -eq 4 ] || fail "expected 4 files in the JSON"
[ "$(field '.files[0].bits')" = 24 ] || fail "bits $(field '.files[0].bits'), want 24"
[ "$(field '.files[0].sampleRate')" = 48000 ] || fail "sampleRate $(field '.files[0].sampleRate')"

F0=$(field '.files[0].f0Hz'); H2=$(field '.files[0].harmonicsDb[1]'); FLOOR=$(field '.files[0].tail.floorDb')
within "$F0" 220 0.5 || fail "tone f0 $F0 Hz, want 220 +- 0.5"
within "$H2" -6 0.5 || fail "tone H2 $H2 dB re H1, want -6 +- 0.5"
below "$FLOOR" -100 || fail "tone tail floor $FLOOR dBFS, want < -100"
ok "tone: f0 $F0 Hz, H2 $H2 dB re H1, tail floor $FLOOR dBFS"

NF=$(field '.files[1].tail.floorDb')
within "$NF" -60 2 || fail "noise tail floor $NF dBFS, want -60 +- 2"
ok "noise in the tail: floor $NF dBFS"

WF0=$(field '.files[2].f0Hz'); WH2=$(field '.files[2].harmonicsDb[1]')
within "$WF0" 220 0.5 || fail "weak fundamental: f0 $WF0 Hz, want 220 (octave error)"
within "$WH2" 20 1 || fail "weak fundamental: H2 $WH2 dB re H1, want +20 +- 1"
ok "weak fundamental: f0 $WF0 Hz (guard $(field '.files[2].octaveGuard')), H2 $WH2 dB re H1"

EF0=$(field '.files[3].f0Hz'); EG=$(field '.files[3].octaveGuard')
within "$EF0" 220 0.5 || fail "weak odd partials: f0 $EF0 Hz, want 220 (octave error)"
[ "$EG" = halved ] || fail "weak odd partials: octave guard $EG, want halved"
[ "$(field '.files[0].octaveGuard')" = none ] || fail "the plain tone was halved"
ok "weak odd partials: f0 $EF0 Hz, guard $EG; the plain tone is not halved"

INSIDE=$("$ANALYZE" --json --tail 0.5-1.0 "$TONE" | jq -r '.files[0].tail.floorDb')
below -30 "$INSIDE" || fail "--tail 0.5-1.0 inside the tone gave floor $INSIDE dBFS"
ok "--tail moves the window: floor $INSIDE dBFS inside the tone"

R=$("$ANALYZE" --json --ref "$TONE" "$NOISE")
RC=$(echo "$R" | jq -r '.files[0].vsRef.f0Cents'); RF=$(echo "$R" | jq -r '.files[0].vsRef.tailFloorDb')
[ "$(echo "$R" | jq -r '.ref.file')" = "$TONE" ] || fail "--ref: the reference is not in the JSON"
within "$RC" 0 1 || fail "--ref: f0 difference $RC cents, want 0"
below 50 "$RF" || fail "--ref: tail floor difference $RF dB, want > 50"
"$ANALYZE" --ref "$TONE" "$NOISE" | grep -q "vs ref" || fail "--ref: no differences in the plain output"
ok "--ref: f0 $RC cents, tail floor +$RF dB against the reference"

PLAIN=$("$ANALYZE" "$TONE") || fail "plain output failed"
echo "$PLAIN" | sed 's/^/    /'
echo "$PLAIN" | grep -q "f0" || fail "plain output has no f0 line"

mkdir "$WORK/aiff"
afconvert -f AIFF -d BEI24 "$TONE" "$WORK/aiff/tone.aiff"
AF0=$("$ANALYZE" --json "$WORK/aiff/tone.aiff" | jq -r '.files[0].f0Hz')
within "$AF0" 220 0.5 || fail "AIFF input: f0 $AF0 Hz"
[ "$(ls "$WORK/aiff")" = "tone.aiff" ] || fail "the conversion wrote next to the input"
ok "a non-WAV input is converted elsewhere and measured: f0 $AF0 Hz"

set +e
"$ANALYZE" "$WORK/missing.wav" > /dev/null 2>&1; MISSING=$?
"$ANALYZE" > /dev/null 2>&1; USAGE=$?
set -e
[ "$MISSING" -eq 1 ] || fail "a missing file exited $MISSING, want 1"
[ "$USAGE" -eq 2 ] || fail "no arguments exited $USAGE, want 2"
ok "exit codes: missing file 1, usage 2"

SCRIPT_F0=$(cd "$ROOT" && swift scripts/analyze.swift --json "$TONE" | jq -r '.files[0].f0Hz')
[ "$SCRIPT_F0" = "$F0" ] || fail "swift scripts/analyze.swift gave f0 $SCRIPT_F0, the compiled tool $F0"
ok "swift scripts/analyze.swift (no compile step) gives the same f0"

find "$WORK/renders" -name '*.wav' -print0 | sort -z | xargs -0 "$ANALYZE" --json \
    | jq -e --argjson n "$COUNT" '.files | length == $n' > /dev/null || fail "analyze could not read every render"
ok "analyze reads every render of the example"

echo "SPIKE ANALYZE OK"
