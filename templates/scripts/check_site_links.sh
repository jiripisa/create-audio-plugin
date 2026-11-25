#!/bin/bash
# Lists every local file the website links that is not there: each src= and href= of the pages
# under docs/ and each url() of their styles (in .css files, <style> blocks and style attributes).
# Links to other sites, mailto:, data: and in-page anchors are not checked.
#
#   scripts/check_site_links.sh [docs-dir]
#
# Prints "site links ok" and exits 0 when every linked file exists; lists "<page>: missing
# <link>" and exits 1 otherwise. A release never ships a page with a missing picture: make the
# picture, or take its figure out of the English and the Czech page alike.

set -euo pipefail

DOCS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs}"
if [ ! -d "$DOCS" ]; then
    echo "no such directory: $DOCS" >&2
    exit 2
fi

MISSING=0
# check <file> <link>...: a link is relative to its file's directory; a query or an anchor after
# the path does not count.
check() {
    local file="$1" dir link path
    dir=$(dirname "$file")
    shift
    for link in "$@"; do
        case "$link" in
            ""|\#*|http:*|https:*|//*|mailto:*|data:*|tel:*) continue ;;
        esac
        path="${link%%[#?]*}"
        [ -z "$path" ] && continue
        if [ ! -e "$dir/$path" ]; then
            echo "${file#"$DOCS"/}: missing $link"
            MISSING=1
        fi
    done
}

while IFS= read -r -d '' file; do
    LINKS=()
    case "$file" in
        *.html)
            while IFS= read -r link; do LINKS+=("$link"); done < <(
                grep -oE "(src|href)=(\"[^\"]*\"|'[^']*')" "$file" | sed -E "s/^(src|href)=.//; s/.\$//" | sort -u || true)
            ;;
    esac
    while IFS= read -r link; do LINKS+=("$link"); done < <(
        grep -oE "url\([^)]*\)" "$file" | sed -E "s/^url\([[:space:]]*//; s/[[:space:]]*\)\$//; s/^[\"']//; s/[\"']\$//" | sort -u || true)
    check "$file" ${LINKS[@]+"${LINKS[@]}"}
done < <(find "$DOCS" -type f \( -name '*.html' -o -name '*.css' \) -print0)

if [ "$MISSING" -ne 0 ]; then
    echo "missing files linked from $DOCS" >&2
    exit 1
fi
echo "site links ok"
