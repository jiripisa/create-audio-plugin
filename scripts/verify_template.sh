#!/bin/bash
# Render templates/ for a dummy instrument and check that the result builds and its tests pass.
#
#   scripts/verify_template.sh [--quick] [--auval] [--capture]
#
#   (default)  render, swift build, swift test, swift test -c release, ./build.sh release; any
#              `warning:` line in one of the build logs fails the run
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
# Zkus), shown as "Zkušebník Test" (APP_NAME). It is rendered into $SCRATCH/verify-<timestamp>/
# ($SCRATCH defaults to $TMPDIR) and kept there for inspection. Prints TEMPLATE OK last on
# success. Every run ends by removing the dummy's preferences and what the tests and tools wrote
# outside the scratch folder.

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

CAPTURE_PID=""
CAPTURE_REMOVE=()
CAPTURE_PREEXISTING=()

# Quits the launched app (kill, wait up to 5 s, kill -9 only if still alive) and removes what the
# run created next to it: caches, saved state and HTTP storage that did not exist before.
stop_capture_app() {
    local was_set=$-
    set +e
    if [ -n "$CAPTURE_PID" ]; then
        kill "$CAPTURE_PID" 2>/dev/null
        for _ in $(seq 1 50); do
            kill -0 "$CAPTURE_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -0 "$CAPTURE_PID" 2>/dev/null && kill -9 "$CAPTURE_PID" 2>/dev/null
        wait "$CAPTURE_PID" 2>/dev/null
        echo "cleanup: quit the app (pid $CAPTURE_PID)"
        CAPTURE_PID=""
        local path pre skip
        if [ -n "${CAPTURE_BUNDLE_ID:-}" ] && [ "$CAPTURE_BUNDLE_ID" != "null" ]; then
            for path in ${CAPTURE_REMOVE[@]+"${CAPTURE_REMOVE[@]}"} "$HOME/Library/HTTPStorages/$CAPTURE_BUNDLE_ID"*; do
                [ -e "$path" ] || continue
                skip=false
                for pre in ${CAPTURE_PREEXISTING[@]+"${CAPTURE_PREEXISTING[@]}"}; do [ "$pre" = "$path" ] && skip=true; done
                [ "$skip" = true ] && continue
                rm -rf "$path"
                echo "cleanup: removed $path"
            done
        fi
    fi
    case "$was_set" in *e*) set -e ;; esac
}

CLEANED=false
clean_up() {
    [ "$CLEANED" = true ] && return
    CLEANED=true
    stop_capture_app
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

# The template builds without warnings: any `warning:` line in a build step's log stops the run.
warnings() {
    local count
    count=$(grep -c 'warning:' "$1" || true)
    echo "   $count warning lines"
    if [ "$count" -ne 0 ]; then
        echo "FAILED: warnings (full log: $1)"
        grep 'warning:' "$1" | head -n 20
        exit 1
    fi
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
# The display name has diacritics and a space, as a directory name may (Čimbál, Tape Loop): every
# window title, bundle name, menu, MIDI port and page that shows it is built with one.
echo "$ID" | jq '. + {
    APP_NAME: "Zkušebník Test",
    AUTHOR: "Jiří Píša",
    TAGLINE: "A test instrument.",
    TAGLINE_CS: "Zkušební nástroj.",
    LICENSE_KEY: "mit",
    LICENSE_LABEL: "MIT License",
    PUBLIC: true, WEBSITE: true, MANUAL: true, CS: true, SPARKLE: true, PLANNING: true,
    MIN_MACOS: "27.0"
}' > "$OUT/config.json"

# --- Render ---
step "render" python3 -I "$SCAFFOLD" --config "$OUT/config.json" --out "$PROJ" \
    --templates "$SKILL_DIR/templates"
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
    warnings "$LAST_LOG"
    tests_summary "$LAST_LOG"
    step "swift test -c release" swift test -c release
    warnings "$LAST_LOG"
    tests_summary "$LAST_LOG"
fi
if [ "$QUICK" = false ] || [ "$AUVAL" = true ] || [ "$CAPTURE" = true ]; then
    step "build.sh release" ./build.sh release
    warnings "$LAST_LOG"
fi

# --- auval: the component is installed only for this run ---
if [ "$AUVAL" = true ]; then
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
# Reads `system_profiler SPAudioDataType` text on stdin; prints "<name>|<transport>" of the device
# marked "Default Output Device: Yes" (nothing when there is none).
default_output() {
    awk '
        function flush() { if (isdefault) { print name "|" transport; found = 1; exit } }
        /^        [^ ].*:$/ { flush(); name = $0; sub(/^ +/, "", name); sub(/:$/, "", name)
                             transport = ""; isdefault = 0 }
        /Default Output Device: Yes/ { isdefault = 1 }
        /^ +Transport: / { transport = $0; sub(/^ +Transport: /, "", transport) }
        END { if (!found) flush() }'
}

if [ "$CAPTURE" = true ]; then
    OUTPUT_DEVICE=$(system_profiler SPAudioDataType 2>/dev/null | default_output || true)
    case "${OUTPUT_DEVICE##*|}" in
        "Built-in")
            echo "== capture (default output: ${OUTPUT_DEVICE%|*})"
            APP="$PROJ/build/release/$NAME.app"
            CAPTURE_BUNDLE_ID=$(jq -r .BUNDLE_ID "$OUT/config.json")
            # Compile the capture tool first, so the app runs only for the capture itself.
            step "compile capture_window" swiftc -O "$SKILL_DIR/scripts/capture_window.swift" \
                -o "$LOGS/capture_window"
            case "$CAPTURE_BUNDLE_ID" in ""|null) echo "FAILED: no BUNDLE_ID in config"; exit 1 ;; esac
            for leftover in "Library/Caches/$CAPTURE_BUNDLE_ID" \
                            "Library/Saved Application State/$CAPTURE_BUNDLE_ID.savedState"; do
                [ -e "$HOME/$leftover" ] && continue
                CAPTURE_REMOVE+=("$HOME/$leftover")
            done
            for leftover in "$HOME/Library/HTTPStorages/$CAPTURE_BUNDLE_ID"*; do
                [ -e "$leftover" ] && CAPTURE_PREEXISTING+=("$leftover")
            done
            "$APP/Contents/MacOS/$NAME" > "$LOGS/app.log" 2>&1 &
            CAPTURE_PID=$!
            set +e
            "$LOGS/capture_window" "$CAPTURE_PID" "$LOGS/window.png" --wait 15
            CAPTURE_STATUS=$?
            set -e
            stop_capture_app
            if [ "$CAPTURE_STATUS" -eq 0 ]; then
                echo "   $LOGS/window.png"
            else
                echo "capture: no image (capture_window exit $CAPTURE_STATUS); continuing"
            fi
            ;;
        *)
            if [ -n "$OUTPUT_DEVICE" ]; then
                echo "capture skipped: default output is ${OUTPUT_DEVICE%|*} (transport ${OUTPUT_DEVICE##*|}), not a built-in device"
            else
                echo "capture skipped: no default output device found"
            fi
            ;;
    esac
fi

clean_up
echo "Rendered project and logs: $OUT"
echo "TEMPLATE OK"
