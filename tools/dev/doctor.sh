#!/usr/bin/env bash
# Check the local environment: binaries, config, databases, data, ports, logs.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

fail=0
warnings=0
expect_running=0
[ "${1:-}" = "--expect-running" ] && expect_running=1
ok()   { printf '  ok   %s\n' "$*"; }
warn() { printf '  warn %s\n' "$*"; warnings=$((warnings + 1)); }
bad()  { printf '  fail %s\n' "$*"; fail=$((fail + 1)); }

printf 'AzerothCore doctor\n'
printf 'root: %s\n\n' "$ROOT"

printf 'Binaries\n'
for binary in authserver worldserver; do
    if [ -x "$BIN_DIR/$binary" ]; then ok "$BIN_DIR/$binary"; else bad "missing $BIN_DIR/$binary"; fi
done

printf '\nConfiguration\n'
for file in "$AUTH_CONF" "$WORLD_CONF"; do
    if [ -f "$file" ]; then ok "$file"; else bad "missing $file"; fi
done

printf '\nClient data\n'
data_dir="$(config_value 'DataDir' "$WORLD_CONF" 2>/dev/null || true)"
if [ -z "$data_dir" ]; then
    bad "DataDir is empty in $WORLD_CONF"
else
    ok "DataDir=$data_dir"
    for sub in dbc maps vmaps mmaps; do
        if [ -d "$data_dir/$sub" ] && [ -n "$(ls -A "$data_dir/$sub" 2>/dev/null)" ]; then
            ok "$sub ($(find "$data_dir/$sub" -type f | wc -l | tr -d ' ') files)"
        else
            bad "missing or empty $data_dir/$sub"
        fi
    done
fi

printf '\nDatabases\n'
auth_info="$(config_value 'LoginDatabaseInfo' "$AUTH_CONF" 2>/dev/null || true)"
world_info="$(config_value 'WorldDatabaseInfo' "$WORLD_CONF" 2>/dev/null || true)"
char_info="$(config_value 'CharacterDatabaseInfo' "$WORLD_CONF" 2>/dev/null || true)"
for pair in "auth:$auth_info" "world:$world_info" "characters:$char_info"; do
    name="${pair%%:*}"
    info="${pair#*:}"
    db="$(db_field "$info" 5)"
    if [ -z "$db" ]; then
        bad "$name database string is empty"
        continue
    fi
    if mysql_from_info "$info" "$db" "SELECT 1" >/dev/null 2>&1; then
        ok "$name -> $db"
    else
        bad "$name -> $db (cannot connect as $(db_field "$info" 3))"
    fi
done

printf '\nPorts\n'
for port in 3724 8085; do
    if port_listening "$port"; then
        if [ "$expect_running" -eq 1 ]; then
            ok "port $port listening (expected)"
        else
            warn "port $port is in use (server may be running)"
        fi
    else
        ok "port $port free"
    fi
done

printf '\nSQL updates\n'
pending="$(find "$ROOT/data/sql/updates" -maxdepth 1 -type d -name 'pending_db_*' -exec sh -c 'ls -1 "$1"/*.sql 2>/dev/null | wc -l' _ {} \; | awk '{s+=$1} END {print s+0}')"
if [ "$pending" -eq 0 ]; then ok "no pending SQL files"; else warn "$pending pending SQL file(s)"; fi
custom="$(find "$ROOT/data/sql/custom" -type f -name '*.sql' 2>/dev/null | wc -l | tr -d ' ')"
ok "$custom project SQL file(s)"

printf '\nLogs\n'
logs="$(log_dir)"
for log in Server.log Errors.log Auth.log; do
    if [ -f "$logs/$log" ]; then ok "$logs/$log ($(wc -l < "$logs/$log" | tr -d ' ') lines)"; else warn "missing $logs/$log"; fi
done
if [ -f "$logs/Errors.log" ] && [ -s "$logs/Errors.log" ]; then
    warn "Errors.log is not empty; last line: $(tail -n 1 "$logs/Errors.log")"
fi

printf '\nDisk\n'
df -h "$ROOT" | tail -n 1

printf '\n'
if [ "$fail" -eq 0 ]; then
    printf 'doctor: ok (%s warning(s))\n' "$warnings"
else
    printf 'doctor: %s failure(s), %s warning(s)\n' "$fail" "$warnings"
    exit 1
fi
