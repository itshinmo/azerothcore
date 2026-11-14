#!/usr/bin/env bash
# Start, stop, restart, and inspect the local authserver/worldserver.
#
# The servers read console input from stdin. If stdin is /dev/null they spin on EOF and write
# "AC> " forever, so they run inside a detached `screen` session by default.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_dirs
LOGS="$(log_dir)"
SCREEN_BIN="$(command -v screen || true)"
MAX_CONSOLE_LOG_BYTES="${MAX_CONSOLE_LOG_BYTES:-104857600}"
case "$MAX_CONSOLE_LOG_BYTES" in
    ''|*[!0-9]*)
        printf 'MAX_CONSOLE_LOG_BYTES must be a whole number of bytes.\n' >&2
        exit 1
        ;;
esac

pid_file() { printf '%s/%s.pid' "$RUN_DIR" "$1"; }
session_name() { printf 'ac-%s-%s' "$(basename "$ROOT")" "$1"; }

rotate_console_log() {
    local log="$1" size
    [ -f "$log" ] || return 0
    size="$(wc -c <"$log" 2>/dev/null | tr -d '[:space:]')" || size=0
    if [ "${size:-0}" -ge "$MAX_CONSOLE_LOG_BYTES" ]; then
        printf 'rotating oversized console log %s (%s bytes)\n' "$log" "$size"
        mv -f "$log" "$log.1"
    fi
}

screen_running() {
    local name="$1" session
    session="$(session_name "$name")"
    [ -n "$SCREEN_BIN" ] || return 1
    "$SCREEN_BIN" -wipe >/dev/null 2>&1 || true
    "$SCREEN_BIN" -list 2>/dev/null | grep -F ".${session}" >/dev/null
}

pid_of() {
    local name="$1" file pid
    file="$(pid_file "$name")"
    if [ -f "$file" ]; then
        pid="$(cat "$file")"
        if kill -0 "$pid" 2>/dev/null; then
            printf '%s' "$pid"
            return 0
        fi
    fi
    # Fallback: local server started by this script has exactly one argv element.
    # A test realm passes -c <config>, so it is not matched here.
    ps -axo pid=,command= | awk -v b="$BIN_DIR/$name" 'NF == 2 && $2 == b { print $1; exit }'
}

running() {
    local name="$1" file pid
    if screen_running "$name"; then
        return 0
    fi
    file="$(pid_file "$name")"
    if [ -f "$file" ]; then
        pid="$(cat "$file")"
        kill -0 "$pid" 2>/dev/null
        return $?
    fi
    [ -n "$(pid_of "$name")" ]
}

pid_matches() {
    local name="$1" pid="$2" command
    command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    case "$command" in
        "$BIN_DIR/$name"*) return 0 ;;
    esac
    return 1
}

start_one() {
    local name="$1" port="$2" binary="$BIN_DIR/$1" session pid
    if running "$name"; then
        printf '%s already running (pid %s)\n' "$name" "$(pid_of "$name")"
        return 0
    fi
    if port_listening "$port"; then
        printf 'port %s is already in use; not starting %s\n' "$port" "$name" >&2
        return 1
    fi
    if [ ! -x "$binary" ]; then
        printf 'missing binary: %s\n' "$binary" >&2
        return 1
    fi
    if [ -z "$SCREEN_BIN" ]; then
        printf 'screen is required to run the server in the background.\n' >&2
        printf 'Install it (brew install screen / apt install screen) or run the server in a terminal.\n' >&2
        return 1
    fi
    session="$(session_name "$name")"
    rotate_console_log "$LOGS/$name.console.log"
    printf 'starting %s in screen session %s ...\n' "$name" "$session"
    "$SCREEN_BIN" -dmS "$session" bash -c "cd \"$BIN_DIR\" && exec \"$BIN_DIR/$name\" >>\"$LOGS/$name.console.log\" 2>&1"
    if wait_for_port "$port" 30; then
        pid="$(pid_of "$name")"
        [ -n "$pid" ] && printf '%s\n' "$pid" >"$(pid_file "$name")"
        printf '%s listening on %s (pid %s)\n' "$name" "$port" "${pid:-unknown}"
    else
        printf '%s failed to listen on %s\n' "$name" "$port" >&2
        tail -n 40 "$LOGS/$name.console.log" 2>/dev/null || true
        return 1
    fi
}

realm_flag() {
    local info db realm
    info="$(config_value 'LoginDatabaseInfo' "$AUTH_CONF")"
    db="$(db_field "$info" 5)"
    realm="$(config_value 'RealmID' "$WORLD_CONF")"
    [ -n "$realm" ] || realm=1
    mysql_from_info "$info" "$db" "SELECT flag FROM realmlist WHERE id = $realm" 2>/dev/null | tr -d '[:space:]'
}

clear_realm_offline() {
    local info db realm
    info="$(config_value 'LoginDatabaseInfo' "$AUTH_CONF")"
    db="$(db_field "$info" 5)"
    realm="$(config_value 'RealmID' "$WORLD_CONF")"
    [ -n "$realm" ] || realm=1
    mysql_from_info "$info" "$db" "UPDATE realmlist SET flag = flag & ~2 WHERE id = $realm"
}

# The offline bit (2) and version-mismatch bit (1) must both be clear; the realm list query excludes
# rows with flag 3.
wait_for_realm() {
    local flag i
    for ((i = 0; i < 30; i++)); do
        flag="$(realm_flag)"
        if [ -n "$flag" ] && [ $((flag & 3)) -eq 0 ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

stop_one() {
    local name="$1" file pid session i
    file="$(pid_file "$name")"
    session="$(session_name "$name")"
    pid="$(pid_of "$name")"
    if [ -z "$pid" ] && [ -f "$file" ]; then
        pid="$(cat "$file")"
    fi
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        printf '%s is not running\n' "$name"
        rm -f "$file"
        if screen_running "$name"; then
            printf 'screen session %s exists without a matching pid; inspect it\n' "$session" >&2
            return 1
        fi
        return 0
    fi
    if ! pid_matches "$name" "$pid"; then
        printf 'pid %s does not match %s; refusing to signal it\n' "$pid" "$BIN_DIR/$name" >&2
        rm -f "$file"
        return 1
    fi
    printf 'stopping %s (pid %s) ...\n' "$name" "$pid"
    kill -TERM "$pid" 2>/dev/null || true
    for ((i = 0; i < 30; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        printf '%s ignored SIGTERM for 30s; sending SIGKILL\n' "$name" >&2
        kill -KILL "$pid" 2>/dev/null || true
        for ((i = 0; i < 5; i++)); do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 1
        done
    fi
    if kill -0 "$pid" 2>/dev/null; then
        printf '%s did not stop after SIGKILL; pid file and screen session kept\n' "$name" >&2
        return 1
    fi
    rm -f "$file"
    [ -n "$SCREEN_BIN" ] && "$SCREEN_BIN" -S "$session" -X quit >/dev/null 2>&1 || true
    printf '%s stopped\n' "$name"
}

status_one() {
    local name="$1" port="$2" pid
    pid="$(pid_of "$name")"
    if [ -n "$pid" ] || screen_running "$name"; then
        printf '%-12s running  pid %-8s port %s %s\n' "$name" "${pid:-unknown}" "$port" "$(port_listening "$port" && echo listening || echo 'not listening')"
    else
        printf '%-12s stopped  %s\n' "$name" "$(port_listening "$port" && echo "port $port in use by another process" || echo "port $port free")"
    fi
}

case "${1:-status}" in
    start)
        # worldserver clears the realm's version-mismatch flag; authserver refuses to start while
        # every realm has flag 3 (VERSION_MISMATCH | OFFLINE). Wait for worldserver to finish.
        start_one worldserver 8085
        if ! wait_for_realm; then
            printf 'worldserver is listening but the realm flag still has offline or mismatch bits; not starting authserver\n' >&2
            exit 1
        fi
        start_one authserver 3724
        # authserver marks every realm offline on boot. The worldserver is already up, so clear the
        # offline bit for this realm and confirm the realm list accepts it.
        if ! clear_realm_offline; then
            printf 'could not clear the realm offline flag after starting authserver\n' >&2
            exit 1
        fi
        if ! wait_for_realm; then
            printf 'realm flag is still offline after authserver start\n' >&2
            exit 1
        fi
        ;;
    stop)
        stop_one authserver || true
        stop_one worldserver || true
        ;;
    restart)
        "$0" stop || true
        "$0" start
        ;;
    status)
        status_one authserver 3724
        status_one worldserver 8085
        ;;
    logs)
        tail -n "${2:-80}" "$LOGS/Auth.log" 2>/dev/null || true
        tail -n "${2:-80}" "$LOGS/Server.log" 2>/dev/null || true
        tail -n "${2:-80}" "$LOGS/Errors.log" 2>/dev/null || true
        ;;
    console)
        session="$(session_name "${2:-worldserver}")"
        exec "$SCREEN_BIN" -r "$session"
        ;;
    *)
        printf 'usage: %s {start|stop|restart|status|logs [n]|console [authserver|worldserver]}\n' "$0" >&2
        exit 2
        ;;
esac
