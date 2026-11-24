#!/bin/bash
# List every line and every path under <dir> that still holds one of the words of the words file
# (default: leftover-words.txt next to this script). Exits 1 when anything is found.
#
#   scripts/check_leftovers.sh <dir> [words-file]
#
# Words are fixed strings, matched case-sensitively; lines starting with # and empty lines in the
# words file are ignored. Build output (.build, build, .swiftpm) and .git are skipped.

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ] || [ ! -d "$1" ]; then
    echo "usage: $(basename "$0") <dir> [words-file]" >&2
    exit 2
fi
DIR="${1%/}"
WORDS="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leftover-words.txt}"
if [ ! -f "$WORDS" ]; then
    echo "no words file: $WORDS" >&2
    exit 2
fi

PATTERNS=$(mktemp)
trap 'rm -f "$PATTERNS"' EXIT
grep -v '^[[:space:]]*#' "$WORDS" | grep -v '^[[:space:]]*$' > "$PATTERNS" || true
if [ ! -s "$PATTERNS" ]; then
    echo "the words file has no words: $WORDS" >&2
    exit 2
fi

FOUND=0
if grep -rIn -F -f "$PATTERNS" \
        --exclude-dir=.build --exclude-dir=build --exclude-dir=.swiftpm --exclude-dir=.git \
        "$DIR"; then
    FOUND=1
fi
# Paths relative to <dir>, so that a word in <dir>'s own location does not count.
if (cd "$DIR" && find . \( -name .build -o -name build -o -name .swiftpm -o -name .git \) -prune -o -print) \
        | grep -F -f "$PATTERNS" | sed "s|^\.|path: $DIR|"; then
    FOUND=1
fi

if [ "$FOUND" -eq 1 ]; then
    echo "leftovers found in $DIR (words: $WORDS)" >&2
    exit 1
fi
echo "no leftovers in $DIR"
