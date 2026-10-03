#!/usr/bin/env bash
# Wrapper around xcodebuild that treats the log content as the source of truth,
# not the process exit code.
#
# Why: xcodebuild is known to exit 0 even when compilation fails, when test cases
# fail, or when the log contains "** BUILD FAILED **" / "** TEST FAILED **".
# Relying on exit status alone causes `make test` (which chains build-ios →
# build-catalyst → build-tvos → test-unit) to keep running past real failures.
#
# Behavior:
#   1. Run `xcodebuild "$@"` under `script` so it still sees a PTY.
#   2. Normalize the captured transcript into a plain-text log.
#   2.5 Drop the known Xcode 26 Catalyst Metal-toolchain linker warning.
#   3. Replay the normalized log through xcbeautify when available.
#   4. Scan the log for error markers. If any are found, or the xcodebuild
#      invocation itself exited non-zero, exit with a non-zero status so make
#      halts the chain. macOS system-log lines that the test host prints for
#      accessibility bundles missing from the OS are not build errors and are
#      skipped by the scan (they stay in the printed log).
#
# Usage:
#   run_xcodebuild.sh <xcodebuild arguments...>
#   run_xcodebuild.sh --scan-log <log file>   Only normalize and scan an
#                                             existing log; exit 1 on errors.
#
# Env:
#   XCBUILD_LABEL  Optional label (e.g. "build-ios") used in failure messages.

set -u -o pipefail

LABEL="${XCBUILD_LABEL:-xcodebuild}"

# Patterns that must never appear in a successful log.
#   - "** BUILD FAILED **", "** TEST FAILED **", "** ARCHIVE FAILED **"
#   - "error:" lines from clang/swiftc/ld (preceded by space after file:line:col:
#     or at start of line)
ERR_RE='(^|[[:space:]])error:|^\*\* (BUILD|TEST|ARCHIVE|CLEAN|ANALYZE) FAILED \*\*|^Testing failed:|^Failing tests:'

# System-log lines that match ERR_RE but are not build or test failures.
#   - "<date> <time> MuseAmp[pid:tid] [AXLoading] Failed to load item ...
#     error: Error Domain=AXLoading ..." when an accessibility bundle such as
#     RealityFoundation or ScreenTimeUI is missing from /System/iOSSupport.
IGNORED_ERR_RE='[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+[+-][0-9]{4} [^[:space:]]+\[[0-9]+:[0-9]+\] \[AXLoading\] Failed to load item .* error: Error Domain=AXLoading '

# Prints the "line:text" of every error line in the given log, or nothing.
error_lines() {
    grep -En "$ERR_RE" "$1" | grep -Ev "$IGNORED_ERR_RE" || true
}

RAW_LOG=$(mktemp -t "museamp-${LABEL//\//_}.raw.XXXXXX.log")
LOG=$(mktemp -t "museamp-${LABEL//\//_}.XXXXXX.log")
trap 'rm -f "$RAW_LOG" "$LOG"' EXIT

ARGS=("$@")
WORKSPACE_PATH=""
PROJECT_PATH=""

select_xcode_container() {
    local filtered=()
    local i=0

    while [ $i -lt ${#ARGS[@]} ]; do
        case "${ARGS[$i]}" in
            -workspace)
                if [ $((i + 1)) -lt ${#ARGS[@]} ]; then
                    WORKSPACE_PATH="${ARGS[$((i + 1))]}"
                fi
                i=$((i + 2))
                ;;
            -project)
                if [ $((i + 1)) -lt ${#ARGS[@]} ]; then
                    PROJECT_PATH="${ARGS[$((i + 1))]}"
                fi
                i=$((i + 2))
                ;;
            *)
                filtered+=("${ARGS[$i]}")
                i=$((i + 1))
                ;;
        esac
    done

    if [ -n "$WORKSPACE_PATH" ] && [ -d "$WORKSPACE_PATH" ] && [ -f "$WORKSPACE_PATH/contents.xcworkspacedata" ]; then
        ARGS=(-workspace "$WORKSPACE_PATH" "${filtered[@]}")
        return
    fi

    if [ -n "$PROJECT_PATH" ]; then
        ARGS=(-project "$PROJECT_PATH" "${filtered[@]}")
        return
    fi

    ARGS=("${filtered[@]}")
}

capture_with_script() {
    if script -q "$RAW_LOG" xcodebuild "$@" >/dev/null 2>&1; then
        XC_STATUS=0
    else
        XC_STATUS=$?
    fi
}

capture_direct() {
    : >"$RAW_LOG"
    if xcodebuild "$@" >"$RAW_LOG" 2>&1; then
        XC_STATUS=0
    else
        XC_STATUS=$?
    fi
}

normalize_log() {
    perl -ne '
        s/\r/\n/g;
        s/\x08//g;
        s/\x04//g;
        next if m{Metal\.xctoolchain/usr/lib/swift/maccatalyst};
        next if m{CoreData: error: Failed to create NSXPCConnection};
        next if m{connection to service named com\.apple\.linkd\.autoShortcut};
        print;
    ' "$1" >"$2"
}

if [ "${1:-}" = "--scan-log" ]; then
    if [ $# -ne 2 ] || [ ! -f "$2" ]; then
        echo "usage: $0 --scan-log <log file>" >&2
        exit 2
    fi
    normalize_log "$2" "$LOG"
    SCAN_ERRORS=$(error_lines "$LOG")
    if [ -n "$SCAN_ERRORS" ]; then
        echo "❌ [$LABEL] errors in $2:" >&2
        printf '%s\n' "$SCAN_ERRORS" | head -40 >&2
        exit 1
    fi
    echo "[$LABEL] no errors in $2"
    exit 0
fi

select_xcode_container

capture_direct "${ARGS[@]}"
normalize_log "$RAW_LOG" "$LOG"

if [ "${XCBUILD_FORCE_PTY:-0}" = "1" ] && grep -F "is not a workspace file" "$LOG" >/dev/null 2>&1; then
    capture_with_script "${ARGS[@]}"
    normalize_log "$RAW_LOG" "$LOG"
fi

if [ -n "$PROJECT_PATH" ] && grep -F "is not a workspace file" "$LOG" >/dev/null 2>&1; then
    filtered_args=()
    i=0
    while [ $i -lt ${#ARGS[@]} ]; do
        if [ "${ARGS[$i]}" = "-workspace" ]; then
            i=$((i + 2))
            continue
        fi
        filtered_args+=("${ARGS[$i]}")
        i=$((i + 1))
    done
    ARGS=(-project "$PROJECT_PATH" "${filtered_args[@]}")
    capture_direct "${ARGS[@]}"
    normalize_log "$RAW_LOG" "$LOG"
fi

if command -v xcbeautify >/dev/null 2>&1; then
    xcbeautify --disable-colored-output --disable-logging <"$LOG"
else
    cat "$LOG"
fi

ERROR_LINES=$(error_lines "$LOG")
FOUND_ERRORS=0
if [ -n "$ERROR_LINES" ]; then
    FOUND_ERRORS=1
fi

if [ "$XC_STATUS" -ne 0 ] || [ "$FOUND_ERRORS" -ne 0 ]; then
    echo "" >&2
    echo "❌ [$LABEL] xcodebuild failed (exit=$XC_STATUS, errors_in_log=$FOUND_ERRORS)" >&2
    if [ "$FOUND_ERRORS" -ne 0 ]; then
        echo "---- first 40 error lines from log ----" >&2
        printf '%s\n' "$ERROR_LINES" | head -40 >&2
        echo "---------------------------------------" >&2
    fi
    # Prefer propagating the original xcodebuild exit status when it's non-zero;
    # otherwise fail with 1 because the log says the run is bad.
    if [ "$XC_STATUS" -ne 0 ]; then
        exit "$XC_STATUS"
    fi
    exit 1
fi
