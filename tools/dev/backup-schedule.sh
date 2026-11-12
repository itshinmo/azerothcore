#!/usr/bin/env bash
# Install, remove, or inspect a daily backup schedule.
#
# macOS: launchd user agent.
# Linux: user crontab entry.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

LABEL="com.azerothcore.backup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$BACKUP_DIR/schedule.log"
CRON_TAG="# azerothcore-backup"

install_launchd() {
    mkdir -p "$(dirname "$PLIST")" "$BACKUP_DIR"
    cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/tools/dev/backup.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>4</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST
    chmod 600 "$PLIST"
    launchctl unload "$PLIST" >/dev/null 2>&1 || true
    launchctl load "$PLIST"
    printf 'installed launchd job: %s\n' "$PLIST"
    printf 'schedule: daily 04:00; log: %s\n' "$LOG"
}

install_cron() {
    mkdir -p "$BACKUP_DIR"
    local entry current clean
    entry="0 4 * * * /bin/bash $ROOT/tools/dev/backup.sh >>$LOG 2>&1 $CRON_TAG"
    current="$(crontab -l 2>/dev/null || true)"
    clean="$(printf '%s\n' "$current" | grep -Fv "$CRON_TAG" || true)"
    { printf '%s\n' "$clean"; printf '%s\n' "$entry"; } | crontab -
    printf 'installed/updated cron entry: daily 04:00; log: %s\n' "$LOG"
}

remove_schedule() {
    if [ "$(uname -s)" = "Darwin" ]; then
        launchctl unload "$PLIST" >/dev/null 2>&1 || true
        rm -f "$PLIST"
        printf 'removed launchd job: %s\n' "$PLIST"
    else
        local current
        current="$(crontab -l 2>/dev/null || true)"
        printf '%s\n' "$current" | grep -Fv "$CRON_TAG" | crontab -
        printf 'removed cron entry\n'
    fi
}

status_schedule() {
    if [ "$(uname -s)" = "Darwin" ]; then
        if [ -f "$PLIST" ]; then
            printf 'launchd job installed: %s\n' "$PLIST"
            launchctl list | grep -F "$LABEL" || true
        else
            printf 'no launchd job installed\n'
        fi
    else
        crontab -l 2>/dev/null | grep -F "$CRON_TAG" || printf 'no cron entry installed\n'
    fi
}

case "${1:-status}" in
    install)
        if [ "$(uname -s)" = "Darwin" ]; then install_launchd; else install_cron; fi
        ;;
    remove)
        remove_schedule
        ;;
    status)
        status_schedule
        ;;
    *)
        printf 'usage: %s {install|remove|status}\n' "$0" >&2
        exit 2
        ;;
esac
