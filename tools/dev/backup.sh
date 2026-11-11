#!/usr/bin/env bash
# Dump auth, characters, and world databases with a checksum and manifest.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

world_info="$(config_value 'WorldDatabaseInfo' "$WORLD_CONF")"
auth_info="$(config_value 'LoginDatabaseInfo' "$AUTH_CONF")"
char_info="$(config_value 'CharacterDatabaseInfo' "$WORLD_CONF")"

host="$(db_field "$world_info" 1)"
port="$(db_field "$world_info" 2)"
user="$(db_field "$world_info" 3)"
pass="$(db_field "$world_info" 4)"
auth_db="$(db_field "$auth_info" 5)"
world_db="$(db_field "$world_info" 5)"
char_db="$(db_field "$char_info" 5)"

if [ -z "$host" ] || [ -z "$user" ] || [ -z "$world_db" ]; then
    printf 'cannot read database configuration from %s\n' "$WORLD_CONF" >&2
    exit 1
fi

if [ "$(db_field "$auth_info" 1)/$(db_field "$auth_info" 3)" != "$host/$user" ] \
    || [ "$(db_field "$char_info" 1)/$(db_field "$char_info" 3)" != "$host/$user" ]; then
    printf 'the three databases use different hosts or users; extend this script before using it\n' >&2
    exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
out="$BACKUP_DIR/manual/$stamp"
umask 077
mkdir -p "$out"
chmod 700 "$out"

printf 'dumping %s, %s, %s ...\n' "$auth_db" "$char_db" "$world_db"
MYSQL_PWD="$pass" mysqldump \
    -h "$host" -P "$port" -u "$user" \
    --single-transaction --routines --triggers --no-tablespaces \
    --databases "$auth_db" "$char_db" "$world_db" \
    >"$out/acore.sql"

if [ ! -s "$out/acore.sql" ]; then
    printf 'dump is empty: %s\n' "$out/acore.sql" >&2
    exit 1
fi

if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$out/acore.sql" >"$out/acore.sql.sha256"
else
    sha256sum "$out/acore.sql" >"$out/acore.sql.sha256"
fi
{
    printf 'created=%s\n' "$stamp"
    printf 'host=%s\n' "$host"
    printf 'databases=%s,%s,%s\n' "$auth_db" "$char_db" "$world_db"
    printf 'size_bytes=%s\n' "$(wc -c <"$out/acore.sql" | tr -d ' ')"
} >"$out/manifest.txt"

printf 'backup: %s\n' "$out/acore.sql"
printf 'sha256: %s\n' "$(cut -d' ' -f1 "$out/acore.sql.sha256")"
