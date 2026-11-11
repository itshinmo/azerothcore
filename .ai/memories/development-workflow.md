---
description: Build, run, worktree, and approval workflow. Read before starting work or opening a PR.
last-verified: 2026-11-12
---

# Development workflow

The canonical flow is [CONTRIBUTING.md](../../CONTRIBUTING.md). Procedures live in
[runbook/development/](../../runbook/development/).

## Local loop

```bash
make doctor        # environment check
make build         # configure, build, install
make test          # unit tests
make start         # auth + world
make status
make logs
make stop
make backup
```

The current build is out-of-source in `build/` with install prefix `env/dist/`. `env/dist/etc/*.conf`
is local configuration and ignored.

## Worktrees

- One task, one branch, one worktree beside the clone.
- Look first: `git worktree list`. If a worktree already holds the task's branch, continue there.
- Never edit, reset, or clean another worktree.
- Remove a worktree or branch only when a human asks, after merge or abandonment.

```bash
git worktree add -b feat/<slug> ../azerothcore-worktrees/feat-<slug> master
```

## Gates

1. Implement and run the matching verification tier.
2. Hand the diff to a human.
3. After human approval, the reviewer agent reviews.
4. Commit, push, and deploy only when a human asks.
5. On a PR, use the pr-shepherd on request; it drafts and waits for confirmation.

Agents never stage, commit, push, or deploy on their own.

## Change sizing

- One logical change per PR.
- Keep docs, SQL, and code in the same change when the behavior requires it.
- Do not mix formatting-only churn with behavior.
- A dependency or schema change needs an ADR.

## When blocked

Ask with concrete options and a recommendation. Use
[ask-the-human](../skills/ask-the-human/SKILL.md). Do not guess.
