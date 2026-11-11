# Worktrees and branches

## When to use

Before starting any task. One task, one branch, one worktree.

## Steps

1. Look first:

   ```bash
   git worktree list
   git branch --show-current
   git status --short
   ```

2. If a worktree already holds the task's branch, continue there.
3. Otherwise create a branch and worktree beside the clone:

   ```bash
   git worktree add -b <type>/<slug> ../azerothcore-worktrees/<type>-<slug> master
   cd ../azerothcore-worktrees/<type>-<slug>
   ```

   Types: `feat`, `fix`, `docs`, `chore`, `refactor`.

4. Work only in that directory. Keep the main checkout on `master`.
5. Run the build in the worktree. `build/` and `env/dist/` are per-worktree and ignored; do not reuse
   the main checkout's build directory.
6. When done, hand the diff to a human. Do not commit.

## Cleanup

Only when a human asks, after merge or abandonment:

```bash
git worktree remove <path>
git branch -d <branch>
```

Never delete a branch with unmerged work.

## Rules

- Changes you did not make belong to someone else: leave them and ask.
- Never reset, clean, or delete another worktree.
- Never edit files in the main checkout while working in a worktree.
- A worktree shares the database and client data with the main checkout; do not run two servers
  against the same databases at once.

## Verification

- `git worktree list` shows exactly the expected worktrees.
- `git status` in the worktree shows only your changes.
- The main checkout is untouched.

## References

- [CONTRIBUTING.md](../../CONTRIBUTING.md#branches-and-worktrees)
- [.ai/skills/worktree-workflow/SKILL.md](../../.ai/skills/worktree-workflow/SKILL.md)
