#!/usr/bin/env bash
# Shared helpers for tools/dev scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# launchd/cron have a minimal PATH; include Homebrew's tools for mysqldump/mysql.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
BIN_DIR="$ROOT/env/dist/bin"
ETC_DIR="$ROOT/env/dist/etc"
RUN_DIR="$ROOT/var/run"
BACKUP_DIR="$ROOT/var/backups"
WORLD_CONF="$ETC_DIR/worldserver.conf"
AUTH_CONF="$ETC_DIR/authserver.conf"

if [ -f "$ROOT/tools/dev/config.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/tools/dev/config.env"
    set +a
fi

config_value() {
    local key="$1" file="$2"
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null \
        | tail -n 1 \
        | sed -E 's/^[^=]*=[[:space:]]*//' \
        | tr -d '"'
}

db_field() {
    local info="$1" index="$2"
    printf '%s' "$info" | cut -d';' -f"$index"
}

mysql_from_info() {
    local info="$1" database="$2" query="$3"
    local host port user pass
    host="$(db_field "$info" 1)"
    port="$(db_field "$info" 2)"
    user="$(db_field "$info" 3)"
    pass="$(db_field "$info" 4)"
    MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -N -B -e "$query" "$database"
}

port_listening() {
    local port="$1"
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

wait_for_port() {
    local port="$1" seconds="${2:-30}" i
    for ((i = 0; i < seconds; i++)); do
        if port_listening "$port"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

log_dir() {
    local dir
    dir="$(config_value 'LogsDir' "$WORLD_CONF" 2>/dev/null || true)"
    if [ -z "$dir" ]; then
        # The server runs with CWD=env/dist/bin, so a relative appender writes there.
        dir="$BIN_DIR"
    fi
    printf '%s' "$dir"
}

ensure_dirs() {
    mkdir -p "$RUN_DIR" "$BACKUP_DIR" "$(log_dir)"
}
