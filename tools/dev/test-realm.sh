#!/usr/bin/env bash
# Create, reset, and run an isolated test realm.
#
# Required for setup/reset:
#   TEST_DB_PASSWORD   password for the acore_test database user
# Optional:
#   TEST_DB_HOST       default 127.0.0.1
#   TEST_DB_PORT       default 3306
#   TEST_DB_USER       default acore_test
#   TEST_AUTH_PORT     default 3824
#   TEST_WORLD_PORT    default 8185
#   MYSQL_ADMIN_USER   default root
#   MYSQL_ADMIN_PASSWORD
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TEST_ETC="$ROOT/env/test/etc"
TEST_LOGS="$ROOT/env/test/logs"
TEST_WORLD_CONF="$TEST_ETC/worldserver.conf"
TEST_AUTH_CONF="$TEST_ETC/authserver.conf"
TEST_DB_HOST="${TEST_DB_HOST:-127.0.0.1}"
TEST_DB_PORT="${TEST_DB_PORT:-3306}"
TEST_DB_USER="${TEST_DB_USER:-acore_test}"
TEST_AUTH_PORT="${TEST_AUTH_PORT:-3824}"
TEST_WORLD_PORT="${TEST_WORLD_PORT:-8185}"
TEST_PREFIX="acore_test"
TEST_AUTH_DB="${TEST_PREFIX}_auth"
TEST_CHAR_DB="${TEST_PREFIX}_characters"
TEST_WORLD_DB="${TEST_PREFIX}_world"
SCREEN_BIN="$(command -v screen || true)"

mysql_admin() {
    : "${MYSQL_ADMIN_USER:?MYSQL_ADMIN_USER is required}"
    MYSQL_PWD="${MYSQL_ADMIN_PASSWORD:-}" mysql \
        -h "$TEST_DB_HOST" -P "$TEST_DB_PORT" -u "$MYSQL_ADMIN_USER" "$@"
}

mysql_test() {
    MYSQL_PWD="$TEST_DB_PASSWORD" mysql \
        -h "$TEST_DB_HOST" -P "$TEST_DB_PORT" -u "$TEST_DB_USER" "$@"
}

validate_ident() {
    local label="$1" value="$2"
    case "$value" in
        ''|*[!A-Za-z0-9._-]*)
            printf '%s must contain only letters, digits, dot, underscore, or hyphen: %s\n' "$label" "$value" >&2
            exit 1
            ;;
    esac
}

require_admin() {
    if [ -z "${MYSQL_ADMIN_USER:-}" ]; then
        printf 'MYSQL_ADMIN_USER is required (a dedicated admin user, not root).\n' >&2
        exit 1
    fi
    if [ "$MYSQL_ADMIN_USER" = "root" ]; then
        printf 'refusing root for test-realm administration; use a dedicated admin user.\n' >&2
        exit 1
    fi
}

require_password() {
    if [ -z "${TEST_DB_PASSWORD:-}" ]; then
        printf 'TEST_DB_PASSWORD is required for setup/reset.\n' >&2
        printf 'Example: TEST_DB_PASSWORD=change-me bash tools/dev/test-realm.sh setup\n' >&2
        exit 1
    fi
    validate_ident TEST_DB_USER "$TEST_DB_USER"
    validate_ident TEST_DB_HOST "$TEST_DB_HOST"
    validate_ident TEST_DB_PASSWORD "$TEST_DB_PASSWORD"
}

set_config_key() {
    local file="$1" key="$2" value="$3"
    python3 - "$file" "$key" "$value" <<'PY'
import re
import sys

path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as handle:
    lines = handle.readlines()
pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=")
replacement = f"{key} = {value}\n"
found = False
for index, line in enumerate(lines):
    if pattern.match(line):
        lines[index] = replacement
        found = True
        break
if not found:
    lines.append(replacement)
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
PY
}

prepare_dirs() {
    mkdir -p "$TEST_ETC" "$TEST_LOGS" "$RUN_DIR"
    chmod 700 "$TEST_ETC" "$TEST_LOGS"
}

copy_configs() {
    cp "$ETC_DIR/authserver.conf" "$TEST_AUTH_CONF"
    cp "$ETC_DIR/worldserver.conf" "$TEST_WORLD_CONF"
    chmod 600 "$TEST_AUTH_CONF" "$TEST_WORLD_CONF"
}

patch_configs() {
    local auth_info world_info char_info
    auth_info="$TEST_DB_HOST;$TEST_DB_PORT;$TEST_DB_USER;$TEST_DB_PASSWORD;$TEST_AUTH_DB"
    world_info="$TEST_DB_HOST;$TEST_DB_PORT;$TEST_DB_USER;$TEST_DB_PASSWORD;$TEST_WORLD_DB"
    char_info="$TEST_DB_HOST;$TEST_DB_PORT;$TEST_DB_USER;$TEST_DB_PASSWORD;$TEST_CHAR_DB"

    set_config_key "$TEST_AUTH_CONF" RealmServerPort "$TEST_AUTH_PORT"
    set_config_key "$TEST_AUTH_CONF" LogsDir "\"$TEST_LOGS\""
    set_config_key "$TEST_AUTH_CONF" LoginDatabaseInfo "\"$auth_info\""

    set_config_key "$TEST_WORLD_CONF" RealmID 1
    set_config_key "$TEST_WORLD_CONF" WorldServerPort "$TEST_WORLD_PORT"
    set_config_key "$TEST_WORLD_CONF" LoginDatabaseInfo "\"$auth_info\""
    set_config_key "$TEST_WORLD_CONF" WorldDatabaseInfo "\"$world_info\""
    set_config_key "$TEST_WORLD_CONF" CharacterDatabaseInfo "\"$char_info\""
    set_config_key "$TEST_WORLD_CONF" LogsDir "\"$TEST_LOGS\""
    set_config_key "$TEST_WORLD_CONF" Warden.Enabled 0
    set_config_key "$TEST_WORLD_CONF" Console.Enable 1
}

create_databases() {
    mysql_admin <<SQL
CREATE USER IF NOT EXISTS '${TEST_DB_USER}'@'${TEST_DB_HOST}' IDENTIFIED BY '${TEST_DB_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${TEST_AUTH_DB}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`${TEST_CHAR_DB}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS \`${TEST_WORLD_DB}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${TEST_AUTH_DB}\`.* TO '${TEST_DB_USER}'@'${TEST_DB_HOST}';
GRANT ALL PRIVILEGES ON \`${TEST_CHAR_DB}\`.* TO '${TEST_DB_USER}'@'${TEST_DB_HOST}';
GRANT ALL PRIVILEGES ON \`${TEST_WORLD_DB}\`.* TO '${TEST_DB_USER}'@'${TEST_DB_HOST}';
FLUSH PRIVILEGES;
SQL
}

bootstrap_databases() {
    printf 'bootstrapping test auth database ...\n'
    if ! "$BIN_DIR/authserver" -d -c "$TEST_AUTH_CONF" >"$TEST_LOGS/bootstrap-auth.log" 2>&1; then
        if ! mysql_test "$TEST_AUTH_DB" -e "SELECT 1 FROM realmlist LIMIT 1" >/dev/null 2>&1; then
            printf 'auth bootstrap failed; see %s/bootstrap-auth.log\n' "$TEST_LOGS" >&2
            tail -n 40 "$TEST_LOGS/bootstrap-auth.log" >&2 || true
            return 1
        fi
        printf 'auth bootstrap exited nonzero after importing the base schema; continuing\n'
    fi

    mysql_test "$TEST_AUTH_DB" <<SQL
INSERT INTO realmlist
  (id, name, address, localAddress, localSubnetMask, port, icon, flag, timezone, allowedSecurityLevel, population, gamebuild)
VALUES
  (1, 'AzerothCore Test', '127.0.0.1', '127.0.0.1', '255.255.255.0', ${TEST_WORLD_PORT}, 0, 0, 1, 0, 0, 12340)
ON DUPLICATE KEY UPDATE
  name = VALUES(name), address = VALUES(address), localAddress = VALUES(localAddress),
  port = VALUES(port), flag = 0, gamebuild = VALUES(gamebuild);
SQL

    printf 'bootstrapping test world and character databases ...\n'
    if ! "$BIN_DIR/worldserver" -d -c "$TEST_WORLD_CONF" >"$TEST_LOGS/bootstrap-world.log" 2>&1; then
        printf 'world bootstrap failed; see %s/bootstrap-world.log\n' "$TEST_LOGS" >&2
        tail -n 40 "$TEST_LOGS/bootstrap-world.log" >&2 || true
        return 1
    fi
    local updates
    updates="$(mysql_test "$TEST_WORLD_DB" -N -B -e "SELECT COUNT(*) FROM updates;")"
    if [ "${updates:-0}" -lt 1 ]; then
        printf 'world bootstrap left no updates rows; see %s/bootstrap-world.log\n' "$TEST_LOGS" >&2
        return 1
    fi
    printf 'bootstrap complete: %s updates; logs: %s/bootstrap-*.log\n' "$updates" "$TEST_LOGS"
}

pid_file() { printf '%s/test-%s.pid' "$RUN_DIR" "$1"; }
session_name() { printf 'ac-test-%s-%s' "$(basename "$ROOT")" "$1"; }

pid_of_test() {
    local name="$1" flag="$2" file pid
    file="$(pid_file "$name")"
    if [ -f "$file" ]; then
        pid="$(cat "$file")"
        if kill -0 "$pid" 2>/dev/null; then
            printf '%s' "$pid"
            return 0
        fi
    fi
    ps -axo pid=,command= | awk -v b="$BIN_DIR/$name" -v f="$flag" '$2 == b && index($0, f) { print $1; exit }'
}

ensure_stopped() {
    local pid
    for name in authserver worldserver; do
        if [ "$name" = "authserver" ]; then
            pid="$(pid_of_test authserver "$TEST_AUTH_CONF")"
        else
            pid="$(pid_of_test worldserver "$TEST_WORLD_CONF")"
        fi
        if [ -n "$pid" ]; then
            printf 'test %s is running (pid %s); stop it before setup/reset\n' "$name" "$pid" >&2
            exit 1
        fi
    done
    if [ -n "$SCREEN_BIN" ] && "$SCREEN_BIN" -list 2>/dev/null | grep -F "ac-test-$(basename "$ROOT")-" >/dev/null; then
        printf 'test screen sessions are still present; stop them before setup/reset\n' >&2
        exit 1
    fi
    if port_listening "$TEST_AUTH_PORT" || port_listening "$TEST_WORLD_PORT"; then
        printf 'test ports %s/%s are in use; stop the test realm before setup/reset\n' "$TEST_AUTH_PORT" "$TEST_WORLD_PORT" >&2
        exit 1
    fi
}

start_one() {
    local name="$1" port="$2" conf="$3" session pid
    if [ -n "$(pid_of_test "$name" "$conf")" ]; then
        printf '%s already running (pid %s)\n' "$name" "$(pid_of_test "$name" "$conf")"
        return 0
    fi
    if port_listening "$port"; then
        printf 'port %s is already in use; not starting %s\n' "$port" "$name" >&2
        return 1
    fi
    if [ -z "$SCREEN_BIN" ]; then
        printf 'screen is required to run the test realm in the background.\n' >&2
        return 1
    fi
    session="$(session_name "$name")"
    printf 'starting test %s in screen session %s ...\n' "$name" "$session"
    "$SCREEN_BIN" -dmS "$session" bash -c "cd \"$BIN_DIR\" && exec \"$BIN_DIR/$name\" -c \"$conf\" >>\"$TEST_LOGS/$name.console.log\" 2>&1"
    if wait_for_port "$port" 30; then
        pid="$(pid_of_test "$name" "$conf")"
        [ -n "$pid" ] && printf '%s\n' "$pid" >"$(pid_file "$name")"
        printf 'test %s listening on %s (pid %s)\n' "$name" "$port" "${pid:-unknown}"
    else
        printf 'test %s failed to listen on %s\n' "$name" "$port" >&2
        tail -n 40 "$TEST_LOGS/$name.console.log" 2>/dev/null || true
        return 1
    fi
}

stop_one() {
    local name="$1" conf="$2" pid session i
    pid="$(pid_of_test "$name" "$conf")"
    if [ -z "$pid" ]; then
        printf 'test %s is not running\n' "$name"
        return 0
    fi
    session="$(session_name "$name")"
    printf 'stopping test %s (pid %s) ...\n' "$name" "$pid"
    kill -TERM "$pid" 2>/dev/null || true
    for ((i = 0; i < 30; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        printf 'test %s did not stop within 30s\n' "$name" >&2
        return 1
    fi
    rm -f "$(pid_file "$name")"
    [ -n "$SCREEN_BIN" ] && "$SCREEN_BIN" -S "$session" -X quit >/dev/null 2>&1 || true
    printf 'test %s stopped\n' "$name"
}

status_one() {
    local name="$1" port="$2" conf="$3" pid
    pid="$(pid_of_test "$name" "$conf")"
    if [ -n "$pid" ]; then
        printf 'test %-12s running pid %-8s port %s %s\n' "$name" "$pid" "$port" "$(port_listening "$port" && echo listening || echo 'not listening')"
    else
        printf 'test %-12s stopped %s\n' "$name" "$(port_listening "$port" && echo "port $port in use" || echo "port $port free")"
    fi
}

case "${1:-status}" in
    setup)
        require_admin
        require_password
        ensure_stopped
        prepare_dirs
        create_databases
        copy_configs
        patch_configs
        bootstrap_databases
        printf 'test realm ready: auth :%s, world :%s\n' "$TEST_AUTH_PORT" "$TEST_WORLD_PORT"
        printf 'start with: bash tools/dev/test-realm.sh start\n'
        ;;
    reset)
        require_admin
        require_password
        ensure_stopped
        if [ "$TEST_AUTH_DB" = "acore_auth" ] || [ "$TEST_CHAR_DB" = "acore_characters" ] || [ "$TEST_WORLD_DB" = "acore_world" ]; then
            printf 'refusing to reset non-test database names\n' >&2
            exit 1
        fi
        mysql_admin -e "DROP DATABASE IF EXISTS \`$TEST_AUTH_DB\`; DROP DATABASE IF EXISTS \`$TEST_CHAR_DB\`; DROP DATABASE IF EXISTS \`$TEST_WORLD_DB\`;"
        "$0" setup
        ;;
    start)
        [ -f "$TEST_WORLD_CONF" ] || { printf 'missing %s; run setup first\n' "$TEST_WORLD_CONF" >&2; exit 1; }
        start_one worldserver "$TEST_WORLD_PORT" "$TEST_WORLD_CONF"
        start_one authserver "$TEST_AUTH_PORT" "$TEST_AUTH_CONF"
        ;;
    stop)
        stop_one authserver "$TEST_AUTH_CONF" || true
        stop_one worldserver "$TEST_WORLD_CONF" || true
        ;;
    status)
        status_one authserver "$TEST_AUTH_PORT" "$TEST_AUTH_CONF"
        status_one worldserver "$TEST_WORLD_PORT" "$TEST_WORLD_CONF"
        ;;
    *)
        printf 'usage: %s {setup|reset|start|stop|status}\n' "$0" >&2
        exit 2
        ;;
esac
