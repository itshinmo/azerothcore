# Worktrees and branches

## When to use

Before starting any task.

## Branch topology

| Branch | Role | Rules |
|--------|------|-------|
| `master` | Mirror of upstream AzerothCore | Fast-forward only. No project commits. |
| `local-server-setup` | Integration branch for fork work | All task branches merge here. This is the buildable fork state. |
| `<type>/<slug>` | One task | Created from `local-server-setup`; merges back into it. |
| `spike/<slug>` | Throwaway experiment | Never merges. Delete when the answer is known. |

`master` exists so upstream fixes can be received without touching project work. Keeping project
commits off it is what makes a fast-forward sync possible at any time.

## Steps

1. Look first:

   ```bash
   git worktree list
   git branch --show-current
   git status --short
   ```

2. If a worktree already holds the task's branch, continue there. Do not create a second one.
3. Otherwise create a branch and worktree beside the clone, based on the integration branch:

   ```bash
   git worktree add -b <type>/<slug> ../azerothcore-worktrees/<type>-<slug> local-server-setup
   cd ../azerothcore-worktrees/<type>-<slug>
   ```

   Types: `feat`, `fix`, `docs`, `chore`, `refactor`. Experiments use `spike/<slug>` and never merge.

4. Work only in that directory. Do not edit the main checkout or another worktree.
5. Run the build in the worktree. `build/` and `env/dist/` are per-worktree and ignored; do not reuse
   the main checkout's build directory.
6. When done, hand the diff to a human. Do not commit.

## Upstream sync

Remotes:

```bash
git remote add upstream https://github.com/azerothcore/azerothcore-wotlk.git
git remote -v
```

Procedure, roughly weekly:

```bash
git fetch --all
git checkout master
git merge --ff-only upstream/master
git checkout local-server-setup
git merge master
```

Rules:
- **Merge, do not rebase.** Rebase replays project commits on every sync and re-conflicts each time.
- Enable `git config rerere.enabled true` once per clone; it replays earlier resolutions.
- Sync while the delta is small. A weekly merge conflicts less than a quarterly one.
- Verification after every sync: `make verify-docs`, then the tier that matches the risk. A sync
  touching core code needs `make verify-cpp`.

Conflict surface is small but wider than the code files. The fork modifies or deletes 14 upstream
files; most are docs, config, and agent files that upstream rarely touches. Ask git for the current
set:

```bash
git diff --stat master...local-server-setup
```

Four of them change often enough to expect manual resolution:

| File | Why it conflicts |
|------|------------------|
| `src/server/apps/worldserver/worldserver.conf.dist` | Project settings appended and rate defaults changed |
| `src/server/game/Chat/ChatCommands/ChatCommand.cpp` | Fork edit to permission precedence |
| `src/server/database/Database/DatabaseWorkerPool.{cpp,h}` | Fork edit to `DirectExecute` return value |
| `apps/codestyle/codestyle-sql.py` | Fork edit to the SQL linter |

## Cleanup

Only when a human asks, after merge or abandonment:

```bash
git worktree remove <path>
git branch -d <branch>
```

## Verification

- `make verify-docs` passes on the merged branch.
- `git diff --stat master...local-server-setup` still lists the expected files; a surprise file means
  something merged incorrectly.
- The tier matching the risk runs; a sync that touches core code needs `make verify-cpp`.
- The main checkout and any other worktree are untouched.

## Troubleshooting

- `git merge --ff-only upstream/master` refuses: `master` has a project commit. Move it to a task
  branch, reset `master` to `upstream/master`, and redo the sync.
- `git worktree add` refuses because the branch exists: use the existing worktree instead.
- Docs check fails after a merge: resolve the link or index, do not delete the check.

## Escalation

If a conflict touches a file in the conflict table and the resolution is not obvious, stop and ask.
Do not resolve a permission or database-pool conflict by guessing.

## References

- [CONTRIBUTING.md](../../CONTRIBUTING.md#branches-and-worktrees)
- [.ai/memories/development-workflow.md](../../.ai/memories/development-workflow.md)
