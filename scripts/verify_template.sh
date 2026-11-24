#!/bin/bash
# Render templates/ for a dummy instrument and check that the result builds and its tests pass.
#
#   scripts/verify_template.sh [--quick] [--auval] [--capture]
#
#   (default)  render, swift build, swift test, swift test -c release, ./build.sh release
#   --quick    render and swift build only
#   --auval    also install the component for this run only, run `auval -v aumu Zkus JPis`,
#              and remove the component again (also when something fails); builds the bundle
#              even with --quick
#   --capture  launch the built app by path and capture its window by PID into logs/window.png
#              (scripts/capture_window.swift); builds the bundle even with --quick. Skipped, without
#              failing, unless the default output device is a built-in one: the app opens an audio
#              stream on it. Never changes the default output, never brings the app to the front.
#
# The dummy instrument is a directory named Zkusebnik (identity from scripts/identity.py, subtype
# Zkus). It is rendered into $SCRATCH/verify-<timestamp>/ ($SCRATCH defaults to $TMPDIR) and kept
# there for inspection. Prints TEMPLATE OK last on success. Every run ends by removing the dummy's
# preferences and what the tests and tools wrote outside the scratch folder.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="${SCAFFOLD:-$HOME/.claude/skills/new-macos-app/scripts/scaffold.py}"
SCRATCH="${SCRATCH:-${TMPDIR:-/tmp}}"
NAME="Zkusebnik"
SUBTYPE="Zkus"

QUICK=false
AUVAL=false
CAPTURE=false
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK=true ;;
        --auval) AUVAL=true ;;
        --capture) CAPTURE=true ;;
        *) echo "usage: $(basename "$0") [--quick] [--auval] [--capture]" >&2; exit 2 ;;
    esac
done

OUT="${SCRATCH%/}/verify-$(date +%Y%m%d-%H%M%S)"
PROJ="$OUT/$NAME"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

PREFS="$HOME/Library/Preferences"
SUPPORT="$HOME/Library/Application Support/$NAME"
COMPONENTS="$HOME/Library/Audio/Plug-Ins/Components"
INSTALLED_COMPONENT=""
ls -1 "$PREFS" > "$LOGS/prefs-before.txt"
SUPPORT_EXISTED=false
[ -e "$SUPPORT" ] && SUPPORT_EXISTED=true

# The dummy's own preference domains (always removed) and those of the helper processes the
# tests run in (removed only when the run created them).
dummy_domains() {
    local bundle_id
    bundle_id=$(jq -r .BUNDLE_ID "$OUT/config.json" 2>/dev/null || echo "io.jp4.zkusebnik")
    echo "$bundle_id" "$bundle_id.audiounit"
}
HELPER_DOMAINS="swiftpm-testing-helper xctest ${NAME}PackageTests"

CLEANED=false
clean_up() {
    [ "$CLEANED" = true ] && return
    CLEANED=true
    set +e
    if [ -n "$INSTALLED_COMPONENT" ] && [ -e "$INSTALLED_COMPONENT" ]; then
        rm -rf "$INSTALLED_COMPONENT"
        echo "cleanup: removed $INSTALLED_COMPONENT"
    fi
    local domain
    for domain in $(dummy_domains) $HELPER_DOMAINS; do
        case " $HELPER_DOMAINS " in
            *" $domain "*) grep -qx "$domain.plist" "$LOGS/prefs-before.txt" && continue ;;
        esac
        if defaults read "$domain" >/dev/null 2>&1; then
            defaults delete "$domain" >/dev/null 2>&1
            echo "cleanup: defaults delete $domain"
        fi
        if [ -f "$PREFS/$domain.plist" ]; then
            rm -f "$PREFS/$domain.plist"
            echo "cleanup: removed $PREFS/$domain.plist"
        fi
    done
    if [ "$SUPPORT_EXISTED" = false ] && [ -e "$SUPPORT" ]; then
        rm -rf "$SUPPORT"
        echo "cleanup: removed $SUPPORT"
    fi
    # Anything else that appeared in ~/Library/Preferences during the run is only reported: it
    # may belong to another program running at the same time.
    ls -1 "$PREFS" > "$LOGS/prefs-after.txt"
    local new
    new=$(comm -13 "$LOGS/prefs-before.txt" "$LOGS/prefs-after.txt")
    if [ -n "$new" ]; then
        echo "cleanup: new in $PREFS during the run (left alone, check them):"
        echo "$new" | sed 's/^/  /'
    fi
    set -e
}
trap 'status=$?; clean_up; exit $status' EXIT

# Runs a step with its output in $LOGS/<slug>.log; on failure shows the log's end and stops.
step() {
    local title="$1"; shift
    local log
    log="$LOGS/$(echo "$title" | tr -c 'A-Za-z0-9\n' '-').log"
    echo "== $title"
    if ! "$@" > "$log" 2>&1; then
        echo "FAILED: $title (full log: $log)"
        tail -n 40 "$log"
        exit 1
    fi
    LAST_LOG="$log"
}

warnings() {
    local count
    count=$(grep -c 'warning:' "$1" || true)
    echo "   $count warning lines"
}

tests_summary() {
    grep -E 'Test run with [0-9]+ tests' "$1" | tail -n 1 | sed 's/^/   /' || true
}

echo "Rendering into $PROJ"

# --- Config: identity of the directory name + fixed values ---
ID=$(python3 -I "$SKILL_DIR/scripts/identity.py" "$PROJ" --no-auval --owner jiripisa)
if [ "$(echo "$ID" | jq -r .AU_SUBTYPE)" != "$SUBTYPE" ]; then
    echo "FAILED: identity.py gave subtype $(echo "$ID" | jq -r .AU_SUBTYPE), expected $SUBTYPE"
    exit 1
fi
echo "$ID" | jq '. + {
    AUTHOR: "Jiří Píša",
    TAGLINE: "A test instrument.",
    TAGLINE_CS: "Zkušební nástroj.",
    LICENSE_KEY: "mit",
    LICENSE_LABEL: "MIT License",
    PUBLIC: true, WEBSITE: true, MANUAL: true, CS: true, SPARKLE: true, PLANNING: true,
    MIN_MACOS: "26.0"
}' > "$OUT/config.json"

# --- Render ---
step "render" python3 -I "$SCAFFOLD" --config "$OUT/config.json" --out "$PROJ" \
    --templates "$SKILL_DIR/templates"
# The manifest is the skill's map of the template (it names the source project), not the project's.
rm -f "$PROJ/MANIFEST.md"
step "leftovers" "$SKILL_DIR/scripts/check_leftovers.sh" "$PROJ"
if grep -rIn -E '\{\{[#^/]?[A-Z_]+\}\}|__APP__' "$PROJ" > "$LOGS/placeholders.log"; then
    echo "FAILED: unrendered placeholders (full list: $LOGS/placeholders.log)"
    head -n 20 "$LOGS/placeholders.log"
    exit 1
fi

cd "$PROJ"

# --- Build and test ---
step "swift build" swift build
warnings "$LAST_LOG"
if [ "$QUICK" = false ]; then
    step "swift test" swift test
    tests_summary "$LAST_LOG"
    step "swift test -c release" swift test -c release
    tests_summary "$LAST_LOG"
fi
if [ "$QUICK" = false ] || [ "$AUVAL" = true ] || [ "$CAPTURE" = true ]; then
    step "build.sh release" ./build.sh release
fi

# --- auval: the component is installed only for this run ---
if [ "$AUVAL" = true ]; then
    case "$NAME" in Fanfrnoch|Brumle|Didgeridoo) echo "refusing to touch $NAME"; exit 1 ;; esac
    SOURCE="$PROJ/build/release/$NAME.app/Contents/PlugIns/$NAME.component"
    TARGET="$COMPONENTS/$NAME.component"
    if [ -e "$TARGET" ]; then
        echo "FAILED: $TARGET already exists; remove it first (it is not this run's)"
        exit 1
    fi
    echo "== install $TARGET (for this run only)"
    mkdir -p "$COMPONENTS"
    INSTALLED_COMPONENT="$TARGET"
    ditto "$SOURCE" "$TARGET"
    # The component registrar picks up a new bundle after a moment.
    for _ in $(seq 1 15); do
        auval -a 2>/dev/null | grep -q "aumu $SUBTYPE JPis" && break
        sleep 2
    done
    step "auval" auval -v aumu "$SUBTYPE" JPis
    if ! grep -q "AU VALIDATION SUCCEEDED" "$LAST_LOG"; then
        echo "FAILED: auval did not report AU VALIDATION SUCCEEDED (full log: $LAST_LOG)"
        tail -n 40 "$LAST_LOG"
        exit 1
    fi
    echo "   AU VALIDATION SUCCEEDED"
    rm -rf "$TARGET"
    INSTALLED_COMPONENT=""
    echo "== removed $TARGET"
fi

# --- capture: the app's window, found by the PID we launched ---
default_output() {
    system_profiler SPAudioDataType 2>/dev/null | awk '
        /^        [^ ].*:$/ { name = $0; sub(/^ +/, "", name); sub(/:$/, "", name) }
        /Default Output Device: Yes/ { print name; exit }'
}

if [ "$CAPTURE" = true ]; then
    OUTPUT_DEVICE=$(default_output)
    case "$OUTPUT_DEVICE" in
        *MacBook*|*Built-in*|*Speakers*|*Headphones*)
            echo "== capture (default output: $OUTPUT_DEVICE)"
            APP="$PROJ/build/release/$NAME.app"
            "$APP/Contents/MacOS/$NAME" > "$LOGS/app.log" 2>&1 &
            APP_PID=$!
            set +e
            swift "$SKILL_DIR/scripts/capture_window.swift" "$APP_PID" "$LOGS/window.png" --wait 15
            CAPTURE_STATUS=$?
            kill "$APP_PID" 2>/dev/null
            for _ in $(seq 1 50); do
                kill -0 "$APP_PID" 2>/dev/null || break
                sleep 0.1
            done
            if kill -0 "$APP_PID" 2>/dev/null; then kill -9 "$APP_PID" 2>/dev/null; fi
            wait "$APP_PID" 2>/dev/null
            BUNDLE_ID=$(jq -r .BUNDLE_ID "$OUT/config.json")
            rm -rf "$HOME/Library/Caches/$BUNDLE_ID" "$HOME/Library/HTTPStorages/$BUNDLE_ID"*
            set -e
            if [ "$CAPTURE_STATUS" -eq 0 ]; then
                echo "   $LOGS/window.png"
            else
                echo "capture: no image (capture_window.swift exit $CAPTURE_STATUS); continuing"
            fi
            ;;
        *)
            echo "capture skipped: default output is ${OUTPUT_DEVICE:-unknown}, not a built-in device"
            ;;
    esac
fi

clean_up
echo "Rendered project and logs: $OUT"
echo "TEMPLATE OK"
