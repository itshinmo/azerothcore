#!/usr/bin/env bash
# Run the verification tiers. Usage: verify.sh {docs|sql|cpp|smoke|full}
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ensure_dirs

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
VERIFY_BUILD="$ROOT/build-verify"

run_docs() {
    printf '\n== docs ==\n'
    node "$ROOT/tools/dev/check-docs.mjs"
    python3 "$ROOT/tools/dev/command-index.py" --check
}

run_tools() {
    printf '\n== tools ==\n'
    python3 -m unittest discover -s "$ROOT/tools/dev/tests"
}

run_sql() {
    printf '\n== sql ==\n'
    python3 "$ROOT/apps/codestyle/codestyle-sql.py"
    printf 'SQL lint only; the local worldserver applies pending/custom updates on restart (ADR-018).\n'
}

run_cpp() {
    printf '\n== cpp ==\n'
    python3 "$ROOT/apps/codestyle/codestyle-cpp.py"
    if ! command -v cppcheck >/dev/null 2>&1; then
        printf 'cppcheck is required for the C++ gate; install it (brew install cppcheck / apt install cppcheck)\n' >&2
        return 1
    fi
    cppcheck --force --inline-suppr --suppressions-list="$ROOT/.suppress.cppcheck" \
        "$ROOT/src" --output-file="$RUN_DIR/cppcheck.txt"
    if [ -s "$RUN_DIR/cppcheck.txt" ]; then
        printf 'cppcheck findings in %s\n' "$RUN_DIR/cppcheck.txt" >&2
        cat "$RUN_DIR/cppcheck.txt" >&2
        return 1
    fi
    (cd "$ROOT" && make configure-verify)
    cmake --build "$VERIFY_BUILD" -j"$JOBS"
    "$VERIFY_BUILD/src/test/unit_tests"
    cmake --install "$VERIFY_BUILD"
}

stop_stack() {
    "$ROOT/tools/dev/server.sh" stop >/dev/null 2>&1 || true
    local i
    for ((i = 0; i < 5; i++)); do
        if ! port_listening 3724 && ! port_listening 8085; then
            return 0
        fi
        sleep 1
    done
    return 1
}

run_smoke() {
    printf '\n== smoke ==\n'
    local started=0 status
    status="$("$ROOT/tools/dev/server.sh" status)"
    if printf '%s\n' "$status" | grep -q '^authserver.*running' \
        && printf '%s\n' "$status" | grep -q '^worldserver.*running'; then
        printf 'servers are already running; stop them first so smoke tests the fresh binary\n' >&2
        return 1
    elif printf '%s\n' "$status" | grep -q running; then
        printf 'partial server stack; run `make stop` then `make start` before smoke\n' >&2
        return 1
    else
        trap 'stop_stack || true' EXIT
        "$ROOT/tools/dev/server.sh" start
        started=1
    fi
    if ! port_listening 3724 || ! port_listening 8085; then
        printf 'smoke failed: authserver and worldserver ports must both be listening\n' >&2
        return 1
    fi
    "$ROOT/tools/dev/doctor.sh" --expect-running
    if [ "$started" -eq 1 ]; then
        if ! stop_stack; then
            printf 'smoke cleanup failed: ports 3724 and 8085 must be free after stop\n' >&2
            return 1
        fi
        trap - EXIT
    fi
}

case "${1:-}" in
    docs) run_docs ;;
    tools) run_tools ;;
    sql) run_sql ;;
    cpp) run_cpp ;;
    smoke) run_smoke ;;
    full)
        run_docs
        run_tools
        run_cpp
        run_sql
        run_smoke
        ;;
    *)
        printf 'usage: %s {docs|tools|sql|cpp|smoke|full}\n' "$0" >&2
        exit 2
        ;;
esac
