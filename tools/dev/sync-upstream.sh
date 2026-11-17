#!/usr/bin/env bash
# Weekly upstream sync: fast-forward master, merge into the working branch, verify docs.
# Run from the MAIN worktree on a named branch (the checkout hop needs master checked out there).
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

[ -n "$BRANCH" ] || die "detached HEAD; check out a branch first"
[ "$(git status --porcelain | wc -l | tr -d ' ')" = "0" ] || die "working tree is not clean; commit or stash first"
if ! FETCH_ERR="$(git fetch --all 2>&1 >/dev/null)"; then
  die "git fetch --all failed: $FETCH_ERR"
fi

# Return to the caller's branch no matter how the hop fails, so the caller is never stranded.
HOPPED=0
restore_branch() {
  if [ "$HOPPED" = 1 ] && [ "$(git branch --show-current)" != "$BRANCH" ]; then
    git checkout -q "$BRANCH" 2>/dev/null || true
  fi
}
trap restore_branch EXIT

OLD_MASTER="$(git rev-parse "$MASTER")"

if [ "$BRANCH" != "$MASTER" ]; then
  if ! CHECKOUT_ERR="$(git checkout "$MASTER" 2>&1 >/dev/null)"; then
    die "cannot check out $MASTER: $CHECKOUT_ERR
(if master is checked out in another worktree, run the sync from the main worktree)"
  fi
  HOPPED=1
fi

BEHIND="$(git rev-list --count "$MASTER..upstream/master")"
if [ "$BEHIND" -gt 0 ]; then
  printf 'fast-forwarding %s: %s upstream commits\n' "$MASTER" "$BEHIND"
  git merge --ff-only upstream/master
else
  printf '%s already at upstream/master\n' "$MASTER"
fi

restore_branch
trap - EXIT

AHEAD="$(git rev-list --count "$BRANCH..$MASTER")"
if [ "$AHEAD" -gt 0 ]; then
  printf 'merging %s into %s: %s commits\n' "$MASTER" "$BRANCH" "$AHEAD"
  if ! git merge --no-edit "$MASTER"; then
    if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
      printf 'merge conflicts in:\n' >&2
      git diff --name-only --diff-filter=U >&2
      die 'resolve the conflicts, `git commit` the merge, then run the gates: make verify-docs, the risk-tier verification, make backup before restarting the stack'
    fi
    die 'merge failed without conflicts; check the git output above'
  fi
else
  printf '%s already contains %s\n' "$BRANCH" "$MASTER"
fi

make verify-docs
if [ "$OLD_MASTER" != "$(git rev-parse "$MASTER")" ]; then
  printf 'upstream delta from this sync:\n'
  git diff --stat "$OLD_MASTER..$MASTER" | tail -3
fi
printf 'sync done. next: risk-tier verification, and `make backup` before restarting the stack so upstream data SQL applies on a backed-up database.\n'
