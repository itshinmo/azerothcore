#!/usr/bin/env bash
# Weekly upstream sync: fast-forward master, merge into the working branch, verify docs.
# Conflicts stop the script; resolve them by hand (see runbook/development/worktrees-and-branches.md),
# commit the merge, then run the verification tier that matches the risk and back up before
# restarting the stack, because upstream data SQL applies on worldserver start.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
BRANCH="$(git branch --show-current)"
MASTER=master

die() { printf '%s\n' "$*" >&2; exit 1; }

# One-time per clone: replay earlier conflict resolutions.
git config rerere.enabled true

[ "$(git status --porcelain | wc -l | tr -d ' ')" = "0" ] || die "working tree is not clean; commit or stash first"
git fetch --all >/dev/null 2>&1 || die "git fetch --all failed"

STASHED=0
if [ "$BRANCH" != "$MASTER" ]; then
  # Keep the caller on their branch; hop away and back for the fast-forward.
  git checkout "$MASTER" >/dev/null 2>&1 || die "cannot check out $MASTER"
  STASHED=1
fi

BEHIND="$(git rev-list --count "$MASTER..upstream/master")"
if [ "$BEHIND" -gt 0 ]; then
  printf 'fast-forwarding %s: %s upstream commits\n' "$MASTER" "$BEHIND"
  git merge --ff-only upstream/master
else
  printf '%s already at upstream/master\n' "$MASTER"
fi

if [ "$STASHED" = "1" ]; then
  git checkout "$BRANCH" >/dev/null 2>&1 || die "cannot return to $BRANCH"
fi

AHEAD="$(git rev-list --count "$BRANCH..master")"
if [ "$AHEAD" -gt 0 ]; then
  printf 'merging %s into %s: %s commits\n' "$MASTER" "$BRANCH" "$AHEAD"
  if ! git merge --no-edit "$MASTER"; then
    printf 'merge conflicts in:\n' >&2
    git diff --name-only --diff-filter=U >&2
    die 'resolve the conflicts, `git commit` the merge, then run the gates: make verify-docs, the risk-tier verification, make backup before restarting the stack'
  fi
else
  printf '%s already contains %s\n' "$BRANCH" "$MASTER"
fi

make verify-docs
printf 'delta since the last sync:\n'
git diff --stat "$(git rev-parse upstream/master^$BEHIND)" upstream/master 2>/dev/null | tail -3 || true
printf 'sync done. next: risk-tier verification, and `make backup` before restarting the stack so upstream data SQL applies on a backed-up database.\n'
