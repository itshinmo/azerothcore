#!/usr/bin/env bash
# Run the verification tiers. Usage: verify.sh {docs|sql|cpp|smoke|full}
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ensure_dirs

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
VERIFY_BUILD="$ROOT/build-verify"
TEST_WORLD_CONF="$ROOT/env/test/etc/worldserver.conf"

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

    local apply_mode="${VERIFY_SQL_APPLY:-auto}"
    if [ "$apply_mode" = "0" ]; then
        printf 'SQL apply disabled (VERIFY_SQL_APPLY=0); lint only.\n'
        return 0
    fi
    if [ ! -f "$TEST_WORLD_CONF" ]; then
        if [ "$apply_mode" = "1" ]; then
            printf 'VERIFY_SQL_APPLY=1 but %s is missing; set up the test realm first.\n' "$TEST_WORLD_CONF" >&2
            return 1
        fi
        printf 'test realm not configured; SQL lint only. See runbook/operation/test-realm.md.\n'
        return 0
    fi

    local pending_count
    pending_count="$(find "$ROOT"/data/sql/updates/pending_db_* "$ROOT/data/sql/custom" -type f -name '*.sql' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$apply_mode" = "auto" ] && [ "$pending_count" -eq 0 ]; then
        printf 'test realm configured but no pending/custom SQL files; lint only.\n'
        printf 'Set VERIFY_SQL_APPLY=1 to force an update run.\n'
        return 0
    fi

    local local_world local_auth local_char test_world test_auth test_char
    local_world="$(config_value 'WorldDatabaseInfo' "$WORLD_CONF")"
    local_auth="$(config_value 'LoginDatabaseInfo' "$AUTH_CONF")"
    local_char="$(config_value 'CharacterDatabaseInfo' "$WORLD_CONF")"
    test_world="$(config_value 'WorldDatabaseInfo' "$TEST_WORLD_CONF")"
    test_auth="$(config_value 'LoginDatabaseInfo' "$TEST_WORLD_CONF")"
    test_char="$(config_value 'CharacterDatabaseInfo' "$TEST_WORLD_CONF")"

    check_test_db() {
        local label="$1" local_info="$2" test_info="$3" local_db test_db
        local_db="$(db_field "$local_info" 5)"
        test_db="$(db_field "$test_info" 5)"
        if [ -z "$test_db" ] || [ "$local_db" = "$test_db" ] \
            || ! printf '%s' "$test_db" | grep -qi 'test'; then
            printf '%s test database is not distinct: local=%s test=%s\n' "$label" "$local_db" "$test_db" >&2
            return 1
        fi
    }

    check_test_db world "$local_world" "$test_world" || return 1
    check_test_db auth "$local_auth" "$test_auth" || return 1
    check_test_db characters "$local_char" "$test_char" || return 1

    local test_auth_db test_char_db test_world_db
    test_auth_db="$(db_field "$test_auth" 5)"
    test_char_db="$(db_field "$test_char" 5)"
    test_world_db="$(db_field "$test_world" 5)"
    if [ "$test_auth_db" = "$test_char_db" ] || [ "$test_auth_db" = "$test_world_db" ] \
        || [ "$test_char_db" = "$test_world_db" ]; then
        printf 'test auth, characters, and world databases must be distinct\n' >&2
        return 1
    fi

    if [ "$(db_field "$test_world" 1)/$(db_field "$test_world" 3)" != "$(db_field "$test_auth" 1)/$(db_field "$test_auth" 3)" ] \
        || [ "$(db_field "$test_world" 1)/$(db_field "$test_world" 3)" != "$(db_field "$test_char" 1)/$(db_field "$test_char" 3)" ]; then
        printf 'test databases use different hosts or users; extend this check\n' >&2
        return 1
    fi

    local old_umask stamp backup_dir
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$BACKUP_DIR/verify/$stamp"
    old_umask="$(umask)"
    umask 077
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"
    printf 'backing up test databases to %s ...\n' "$backup_dir"
    MYSQL_PWD="$(db_field "$test_world" 4)" mysqldump \
        -h "$(db_field "$test_world" 1)" -P "$(db_field "$test_world" 2)" \
        -u "$(db_field "$test_world" 3)" --single-transaction --routines --triggers \
        --no-tablespaces --databases "$(db_field "$test_auth" 5)" "$(db_field "$test_char" 5)" "$(db_field "$test_world" 5)" \
        >"$backup_dir/test.sql"
    umask "$old_umask"

    printf 'applying SQL updates to the test realm with worldserver -d ...\n'
    "$BIN_DIR/worldserver" -d -c "$TEST_WORLD_CONF" >"$RUN_DIR/worldserver-test-apply.log" 2>&1

    local updates creatures
    updates="$(mysql_from_info "$test_world" "$(db_field "$test_world" 5)" "SELECT COUNT(*) FROM updates")"
    creatures="$(mysql_from_info "$test_world" "$(db_field "$test_world" 5)" "SELECT COUNT(*) FROM creature")"
    if [ "${updates:-0}" -lt 1 ] || [ "${creatures:-0}" -lt 1 ]; then
        printf 'test-realm row checks failed: updates=%s creatures=%s\n' "${updates:-0}" "${creatures:-0}" >&2
        return 1
    fi
    printf 'test-realm apply ok: updates=%s creatures=%s log=%s\n' "$updates" "$creatures" "$RUN_DIR/worldserver-test-apply.log"
    printf 'test backup: %s\n' "$backup_dir/test.sql"

    local retention_days="${VERIFY_BACKUP_RETENTION_DAYS:-7}" old
    while IFS= read -r -d '' old; do
        rm -rf "$old"
    done < <(find "$BACKUP_DIR/verify" -maxdepth 1 -type d -name '20*' -mtime +"$retention_days" -print0)
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
