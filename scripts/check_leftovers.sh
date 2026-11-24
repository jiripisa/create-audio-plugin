#!/bin/bash
# List every line and every path under <dir> that still holds one of the words of the words file
# (default: leftover-words.txt next to this script). Exits 1 when anything is found.
#
#   scripts/check_leftovers.sh [--skip-dir NAME]... <dir> [words-file]
#
# Words are fixed strings, matched case-sensitively anywhere in a line or a path; a word written
# \bword\b matches only as a whole word (letters, digits and _ around it do not count, so
# \bFanf\b finds 'Fanf' but not Fanfare). Lines starting with # and empty lines in the words file
# are ignored. Build output (.build, build, .swiftpm) and .git are skipped, and so is every
# directory named by a --skip-dir (by its name, at any depth, as grep's --exclude-dir).

set -euo pipefail

SKIP=(.build build .swiftpm .git)
while [ $# -gt 0 ] && [ "$1" = "--skip-dir" ]; do
    if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "usage: $(basename "$0") [--skip-dir NAME]... <dir> [words-file]" >&2
        exit 2
    fi
    SKIP+=("$2")
    shift 2
done
if [ $# -lt 1 ] || [ $# -gt 2 ] || [ ! -d "$1" ]; then
    echo "usage: $(basename "$0") [--skip-dir NAME]... <dir> [words-file]" >&2
    exit 2
fi
DIR="${1%/}"
WORDS="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leftover-words.txt}"
if [ ! -f "$WORDS" ]; then
    echo "no words file: $WORDS" >&2
    exit 2
fi

ALL=$(mktemp)
ANYWHERE=$(mktemp)
WHOLE=$(mktemp)
trap 'rm -f "$ALL" "$ANYWHERE" "$WHOLE"' EXIT
grep -v '^[[:space:]]*#' "$WORDS" | grep -v '^[[:space:]]*$' > "$ALL" || true
if [ ! -s "$ALL" ]; then
    echo "the words file has no words: $WORDS" >&2
    exit 2
fi
# \bword\b lines go to the whole-word list without the \b, the others to the anywhere list.
sed -n 's/^\\b\(.*\)\\b$/\1/p' "$ALL" > "$WHOLE"
grep -v '^\\b.*\\b$' "$ALL" > "$ANYWHERE" || true

EXCLUDES=()
PRUNE=()
for name in "${SKIP[@]}"; do
    EXCLUDES+=("--exclude-dir=$name")
    [ ${#PRUNE[@]} -gt 0 ] && PRUNE+=(-o)
    PRUNE+=(-name "$name")
done

FOUND=0
# Lines, then paths relative to <dir> (so that a word in <dir>'s own location does not count),
# once for the words matched anywhere and once for the whole words.
for mode in anywhere whole; do
    if [ "$mode" = anywhere ]; then list="$ANYWHERE"; flags=(-F); else list="$WHOLE"; flags=(-F -w); fi
    [ -s "$list" ] || continue
    if grep -rIn "${flags[@]}" -f "$list" "${EXCLUDES[@]}" "$DIR"; then
        FOUND=1
    fi
    if (cd "$DIR" && find . \( "${PRUNE[@]}" \) -prune -o -print) \
            | grep "${flags[@]}" -f "$list" | sed "s|^\.|path: $DIR|"; then
        FOUND=1
    fi
done

if [ "$FOUND" -eq 1 ]; then
    echo "leftovers found in $DIR (words: $WORDS)" >&2
    exit 1
fi
echo "no leftovers in $DIR"
