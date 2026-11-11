# Contributing

This is the onboarding and workflow guide for the private AzerothCore workspace. It is written for
humans and agents. Binding rules live in [AGENTS.md](AGENTS.md); procedures live in
[runbook/](runbook/README.md). When this file and a linked source disagree, the linked source wins.

## Scope

Current work is infrastructure, documentation, database tooling, and GM tooling. New game content is
out of scope until the foundation is stable. The content policy and custom ID ranges are documented in
[decisions/ADR-002-custom-content-isolation-and-ids.md](decisions/ADR-002-custom-content-isolation-and-ids.md).

## Prerequisites

- macOS with Homebrew
- CMake 3.16+
- C++20 compiler (Apple clang is supported)
- MySQL 8.4
- Boost, OpenSSL 3, readline
- Optional: Go 1.26+ for live e2e, Node 26 for the database GUI

```bash
brew install cmake openssl@3 readline boost mysql@8.4 ccache jq screen
brew install go node
```

## Quickstart

```bash
# Build and install
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSCRIPTS=static -DMODULES=static \
  -DCMAKE_INSTALL_PREFIX="$PWD/env/dist"
cmake --build build -j"$(sysctl -n hw.ncpu)"
cmake --install build

# Databases (once)
mysql -u root -p < data/sql/create/create_mysql.sql

# Run (worldserver first: it clears the realm's version-mismatch flag)
cd env/dist/bin
./worldserver
# in a second terminal:
./authserver
```

Full setup: [runbook/development/setup-macos.md](runbook/development/setup-macos.md).

## Development flow

```text
requirement / bug / audit finding
        |
        v
  spec or runbook update          specs/, runbook/, decisions/
        |
        v
  implementation + tests          code, SQL, tools
        |
        v
  tiered verification             make verify-* / manual checklist
        |
        v
  human review
        |
        v
  reviewer agent
        |
        v
  commit / push / deploy          only when a human asks
```

Small, well-understood changes may skip a new spec but must update the runbook or code comment that
explains the current behavior. A hard-to-reverse decision gets an ADR. A significant or contested
change gets an RFC first.

## Gates

| Change | Must pass |
|--------|-----------|
| Documentation | link check, reviewer |
| SQL, RBAC, schema | SQL lint; auto test-realm apply, row checks, backup when configured; `VERIFY_SQL_APPLY=0` disables |
| C++ or scripts | codestyle, cppcheck, `-Werror` build, unit tests |
| Player-visible or critical | the C++ gate plus startup smoke and a manual checklist; live e2e when asked |
| Production | all of the above plus backup, staging, rollback plan, human approval |

Agents never stage, commit, push, or deploy on their own. A change is eligible for commit only after a
human approves it and then the reviewer agent approves it. See
[AGENTS.md](AGENTS.md#approval-gate).

## Branches and worktrees

`master` tracks upstream AzerothCore. One task gets one branch and one worktree beside the clone:

```bash
git worktree add -b feat/<slug> ../azerothcore-worktrees/feat-<slug> master
cd ../azerothcore-worktrees/feat-<slug>
```

The main checkout stays on `master`. Never edit, reset, or clean another worktree. A worktree and its
branch are removed only when a human asks, after the work is merged or abandoned.

## Roles

| Role | Responsibility |
|------|----------------|
| documenter | requirements to specs, ADRs, RFCs, runbooks |
| content-author | future content design and SQL drafts |
| implementer | C++ and script changes to spec |
| db-admin | schema, queries, GUI, migrations, backups |
| reviewer | correctness, security, regression, spec drift |
| verifier | build, unit/e2e, smoke, manual evidence |
| server-operator | local/test start-stop, SQL apply, backups, logs |
| pr-shepherd | GitHub PR review and follow-up, drafts only |

Role definitions: [.ai/agents/](.ai/agents/). Invoke a role by name or by pointing the agent at its
file.

## Commits and pull requests

Commit titles follow `type(Scope/Subscope): imperative subject`, at most 72 characters. Types:
`feat`, `fix`, `refactor`, `style`, `docs`, `test`, `chore`. Scopes: `Core`, `Scripts`, `DB`, `Tools`,
`Docs`, `Ops`. One logical change per pull request.

The PR template is [pull_request_template.md](pull_request_template.md). Check the AI disclosure box
honestly. Credit upstream authors with `--author` or `Co-authored-by` when code, data, or a mechanism
comes from another core.

## Knowledge placement

| Location | Holds | Question it answers |
|----------|-------|---------------------|
| `specs/` | current behavior and contracts | What must the system do? |
| `decisions/` | accepted decisions and rationale | Why was this chosen? |
| `rfcs/` | proposals | What is proposed? |
| `runbook/` | procedures | How do I do it? |
| `.ai/memories/` | durable agent orientation | How do I orient quickly? |
| `.ai/skills/` | repeatable workflows | How do I perform this task? |
| `.ai/agents/` | role behavior | Who owns this work? |
| `.agents/docs/` | upstream coding rules | What are the code conventions? |

Precedence: explicit human instruction > code/config > specs > decisions > runbook > memories >
assumptions. Fix or flag the lower source.

## Security

- No credentials, DB passwords, tokens, or player data in commits, docs, logs, or chat.
- Local configuration lives in `env/dist/etc/` and `.env` files; both are ignored.
- Use least-privilege database users. Never use `root` for the GUI, scripts, or agents.
- Production writes are human-only. Agents may write to local and test databases after a backup.

## Asking for help

If a requirement is ambiguous or a decision is not yours, ask with concrete options and a
recommendation. Do not guess. See [.ai/skills/ask-the-human/SKILL.md](.ai/skills/ask-the-human/SKILL.md).
