---
name: worktree-workflow
description: Use before starting any task in this repository. One task, one branch, one worktree; never edit another worktree.
---

# worktree-workflow

## Prerequisites

- Clean or understood `git status` in the current checkout.
- The task has a short slug (`feat/gm-panel`, `fix/log-triage`, `docs/runbooks`).

## Workflow

1. Look first:

   ```bash
   git worktree list
   git branch --show-current
   git status --short
   ```

2. If a worktree already holds the task's branch, continue there. Do not create a second one.
3. Otherwise create a branch and worktree beside the clone:

   ```bash
   git worktree add -b <type>/<slug> ../azerothcore-worktrees/<type>-<slug> master
   cd ../azerothcore-worktrees/<type>-<slug>
   ```

4. Work only in that directory. Keep the main checkout on `master`.
5. Record the worktree path in the hand-off.

## Constraints

- Changes you did not make belong to someone else: leave them and ask.
- Never reset, clean, or delete another worktree.
- Never delete a branch with unmerged work.
- Remove a worktree or branch only when a human asks, after merge or abandonment.
- Creating a branch and worktree is not staging or committing.

## Useful commands

```bash
git worktree list
git worktree add -b <type>/<slug> ../azerothcore-worktrees/<type>-<slug> master
git worktree remove <path>
git branch -d <branch>
```

## Expected output

A single worktree for the task, with the main checkout untouched, and a note of its path.

## References

- [CONTRIBUTING.md](../../../CONTRIBUTING.md#branches-and-worktrees)
- [.ai/memories/development-workflow.md](../../memories/development-workflow.md)
