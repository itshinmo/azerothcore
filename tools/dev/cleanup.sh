#!/usr/bin/env bash
# Remove disposable build, backup, and log artifacts.
# Dry-run by default; pass --yes to delete. See runbook/operation/cleanup.md.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DRY_RUN=1
BACKUPS_KEEP=7
LOGS_DAYS=7
FREED_KB=0

usage() {
    printf '%s\n' \
        'usage: tools/dev/cleanup.sh [options]' \
        '' \
        '  --yes                 delete; without it the script only reports' \
        '  --backups-keep N      keep the N newest dumps per backup type (default 7)' \
        '  --logs-days N         delete main-server logs older than N days (default 7)' \
        '  -h, --help            show this help'
}

fail() {
    printf 'cleanup: %s\n' "$1" >&2
    exit 1
}

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

human_kb() {
    awk -v kb="$1" 'BEGIN {
        if (kb >= 1048576) printf "%.1f GB", kb / 1048576;
        else if (kb >= 1024) printf "%.1f MB", kb / 1024;
        else printf "%d KB", kb;
    }'
}

path_kb() {
    du -sk "$1" 2>/dev/null | awk '{print $1}'
}

remove_item() {
    local path="$1" kb
    [ -e "$path" ] || return 0
    kb="$(path_kb "$path" || true)"
    kb="${kb:-0}"
    FREED_KB=$((FREED_KB + kb))
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'would remove %s (%s)\n' "$path" "$(human_kb "$kb")"
    else
        rm -rf -- "$path"
        printf 'removed %s (%s)\n' "$path" "$(human_kb "$kb")"
    fi
}

prune_backups() {
    local dir="$1" keep="$2" seen=0 entry
    [ -d "$dir" ] || return 0
    while IFS= read -r entry; do
        seen=$((seen + 1))
        [ "$seen" -le "$keep" ] && continue
        remove_item "$entry"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print | sort -r)
}

prune_old_files() {
    local dir="$1" days="$2" pattern="$3" file
    [ -d "$dir" ] || return 0
    while IFS= read -r -d '' file; do
        remove_item "$file"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name "$pattern" -mtime +"$days" -print0)
}

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) DRY_RUN=0 ;;
            --backups-keep)
                [ $# -ge 2 ] || fail '--backups-keep needs a number'
                BACKUPS_KEEP="$2"; shift ;;
            --logs-days)
                [ $# -ge 2 ] || fail '--logs-days needs a number'
                LOGS_DAYS="$2"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; fail "unknown option: $1" ;;
        esac
        shift
    done

    is_uint "$BACKUPS_KEEP" || fail '--backups-keep must be a whole number'
    is_uint "$LOGS_DAYS" || fail '--logs-days must be a whole number'
    [ "$BACKUPS_KEEP" -ge 1 ] || fail '--backups-keep must be at least 1; never delete the newest dump'
    [ "$LOGS_DAYS" -ge 1 ] || fail '--logs-days must be at least 1'

    # Refuse to pull the rug from under an active build.
    if [ "$DRY_RUN" -eq 0 ] && pgrep -f '(cmake|cc1plus|clang\+\+|/bin/make|make).*build-verify' >/dev/null 2>&1; then
        fail 'a verify-cpp build is running; wait for it to finish'
    fi

    printf 'cleanup: %s\n' "$([ "$DRY_RUN" -eq 1 ] && echo 'dry run' || echo 'deleting')"

    # verify-cpp recreates this from scratch on demand.
    remove_item "$ROOT/build-verify"

    # Keep the newest dumps; older ones are reproducible from the live database.
    prune_backups "$BACKUP_DIR/manual" "$BACKUPS_KEEP"
    prune_backups "$BACKUP_DIR/verify" "$BACKUPS_KEEP"

    # Main-server logs only. Rig traces and logs are kept as reproduction material (ADR-017).
    prune_old_files "$ROOT/env/dist/logs" "$LOGS_DAYS" '*.log*'

    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'dry run: %s reclaimable; re-run with --yes to delete\n' "$(human_kb "$FREED_KB")"
    else
        printf 'freed: %s\n' "$(human_kb "$FREED_KB")"
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
