# AGENTS.md

AzerothCore is a C++20 MMORPG server emulator for World of Warcraft 3.3.5a (WotLK), built with CMake
and backed by MySQL.

This repository is a private-server fork. It is not upstream AzerothCore. Current work is
infrastructure, documentation, database tooling, and GM tooling. New game content is out of scope
until the foundation is stable.

## Knowledge layer and precedence

- Agent roles, skills, memories, and templates: `.ai/`.
- Current behavior and contracts: `specs/`.
- Accepted decisions: `decisions/`.
- Proposals: `rfcs/`.
- Procedures: `runbook/`.
- Upstream coding rules: `.agents/docs/`.
- Human entry: `README.md` and `CONTRIBUTING.md`.

Precedence when sources disagree:

```text
explicit human instruction > code/config > specs > decisions > runbook > memories > assumptions
```

Fix or flag the lower source. Do not duplicate a contract in a memory or a runbook; link to it.

## Approval gate

**Agents never stage, commit, push, deploy, or write to production on their own.**

A change is eligible to be staged and committed only after:

1. a human has reviewed and approved it, and then
2. the reviewer agent (`.ai/agents/reviewer.md`) has approved it.

Even then, stage and commit only when a human asks. Open a pull request only after a human confirms
it. An approval covers the reviewed diff only; any further edit needs review again.

Agents may read, build, run tests, and write to local or test databases after a backup. Production
database writes are human-only. The pr-shepherd posts to GitHub only after a human confirms the exact
text and never submits an approval.

## Agent rules

- **Do not configure or build unless the task requires it.** Builds are slow. For verification, use
  the documented commands in `runbook/development/build-and-install.md` or the `make` targets.
- **Never edit SQL files outside `data/sql/updates/pending_db_*/` and `data/sql/custom/db_*/`.**
  `data/sql/base/`, `data/sql/archive/`, and `data/sql/updates/db_*/` are immutable.
- Formatting follows `.editorconfig`: UTF-8, LF, max 120 columns, trailing newline, no trailing
  whitespace; 4-space indent for C++ (tabs forbidden), 2-space for JSON/YAML/sh/ts/js.
- **Do not write or add live-stack e2e tests unless the user explicitly asks.** Do not create
  `e2e/local/` scratch tests to validate a fix. Existing `e2e/` tests that break after a change may
  be updated. Do not mention missing coverage unless the user asked about it.
- Planning docs go in `.agents/plans/<task-slug>/` (gitignored), named `<task-slug>.<TYPE>.md`
  (`PLAN`, `REQUIREMENTS`, `ANALYSIS`, …).
- **Credit upstream authors.** Code, a mechanism, or data mirrored from another core (TrinityCore,
  cMaNGOS, …) is committed with `--author` naming the original commit's author (extra sources as
  `Co-authored-by`), even when rewritten against AC or confirmed by own sniffs; find them in the
  upstream file's commit history.
- **Secrets never enter the repository.** No database passwords, tokens, server keys, player data,
  internal hostnames, or dashboard links in code, docs, tests, logs, commits, or chat. Use `.env`
  files, `env/dist/etc/`, or the database client's own credential store; the repository paths are
  ignored.
- **Ask, do not guess.** A missing contract, an ambiguous requirement, or a decision that is not
  yours goes to the human with concrete options and a recommendation. Procedure:
  `.ai/skills/ask-the-human/SKILL.md`.

## Mandatory reading per task

Read the matching doc(s) BEFORE starting the task:

- Any task → this file, then `.ai/memories/overview.md` and `.ai/memories/status.md`.
- Compiling, configuring, or running the server → `.agents/docs/build.md` and
  `runbook/development/build-and-install.md`.
- Writing or modifying C++ → `.agents/docs/cpp-guidelines.md`.
  - Script work under `src/server/scripts/` → also `.agents/docs/cpp-scripts.md`.
  - Module work under `modules/` → also `modules/how_to_make_a_module.md`.
- Creating or modifying SQL → `.agents/docs/sql-guidelines.md` and
  `runbook/operation/apply-sql-update.md`.
  - SmartAI work (`smart_scripts` data) → also `.agents/docs/cpp-scripts.md`.
- Querying or editing the database → `runbook/database/schema-guide.md` and
  `.ai/skills/db-query-and-edit/SKILL.md`.
- Using a database client (DBeaver) → `runbook/database/dbeaver.md`.
- Backing up or restoring → `runbook/operation/backup-restore.md`.
- Starting, stopping, or monitoring the server → `runbook/operation/start-stop.md`,
  `runbook/operation/health-check.md`, and `runbook/operation/logs-and-monitoring.md`.
- GM tooling or RBAC → `runbook/gm/command-handbook.md` and `runbook/gm/rbac-roles.md`.
- Reviewing a changeset or PR → `.agents/docs/code-review.md` and `.agents/docs/self-review-rules.md`.
- Changing live e2e, and only when the user asked or an existing test broke → `e2e/README.md` and
  `.agents/docs/e2e-policy.md`.
- Capturing a lesson or adding/updating agent docs → `.agents/docs/README.md` and `.ai/README.md`.

## Repository layout

- `src/common/` — networking (Asio), crypto, config, logging, shared utilities.
- `src/server/game/` — core gameplay; compiled into worldserver.
- `src/server/scripts/` — content scripts grouped by region (`EasternKingdoms/`, `Northrend/`, …),
  class (`Spells/spell_mage.cpp`, …), and domain (`Commands/`, `Pet/`, `OutdoorPvP/`, `World/`).
- `src/server/database/` — DB abstraction and schema updater.
- `src/server/shared/` — code shared by auth and world servers.
- `src/server/apps/{authserver,worldserver}/` — entry points (ports 3724 and 8085).
- `src/test/` — unit tests and mocks.
- `e2e/` — live-stack Go e2e (AzerothGhost harness); see `e2e/README.md`.
- `data/sql/` — `base/` (historical schema), `updates/db_*/` (merged), `updates/pending_db_*/`
  (in-flight), `custom/db_*/` (project-specific, re-applicable).
- `modules/` — external modules; project modules live in `modules/mod-*`.
- `apps/` — upstream helper scripts; `apps/codestyle/` holds the lint scripts.
- `conf/dist/` — build and shell templates; `conf/*.conf` is gitignored.
- `src/server/apps/{authserver,worldserver}/*.conf.dist` — server config templates.
- `env/dist/` — local install prefix, binaries, configs, logs (gitignored).
- `tools/` — project tooling: dev scripts, GM addon. The long-term visual layer is the server
  website.
- `runbook/`, `specs/`, `decisions/`, `rfcs/`, `.ai/` — knowledge layer.

## Commands

Use the documented wrappers instead of ad-hoc equivalents. The `make` targets are thin wrappers over
`tools/dev/` and preserve the correct working directory and environment.

```bash
make doctor          # check binaries, config, DB, data dirs, ports, pending SQL, logs
make build           # configure, build, install into env/dist
make test            # build the test target and run unit tests
make command-index   # regenerate the GM command index
make verify-docs     # markdown link check and generated command index check
make verify-sql      # SQL lint; auto-applies pending/custom SQL to test realm when configured
make verify-cpp      # codestyle, cppcheck, -Werror build, unit tests
make verify-smoke    # start the local stack, health-check, stop
make verify-full     # all applicable tiers
make start           # start authserver and worldserver
make stop            # stop both
make status          # show process and port status
make logs            # tail server logs
make console         # attach to the worldserver screen console
make backup          # dump auth, characters, and world
make test-realm CMD=setup|start|stop|status|reset
make backup-schedule CMD=install|remove|status
```

If a wrapper does not exist yet, use the procedure in `runbook/`; do not invent a new one-off command
and leave it undocumented.

## Custom content policy

New content is currently out of scope. When it returns:

- C++ systems live in tracked `modules/mod-*`; do not add to `src/server/scripts/Custom/`.
- Project SQL lives in tracked `data/sql/custom/db_*/`; it must be re-applicable
  (`CREATE TABLE IF NOT EXISTS`, `DELETE` + `INSERT`, `REPLACE`, idempotent updates).
- Upstream-shaped fixes that could be proposed upstream use `data/sql/updates/pending_db_*/`.
- Custom IDs follow `runbook/database/id-registry.md`: items `900000–909999`, creatures
  `910000–919999`, quests `920000–929999`, gameobjects `930000–939999`, spells `940000–949999`,
  misc `950000–959999`, maps `1000+`.
- Reuse existing maps, areas, and client assets until the client-patch pipeline is documented and
  approved. A genuinely new zone needs a client MPQ/DBC patch plus map/vmap/mmap extraction.

## Database safety

- The three databases are `acore_auth`, `acore_characters`, and `acore_world`.
- Use `PreparedStatement` and the typed helpers in C++; never concatenate player input into SQL.
- Before any write batch, run `make backup` or the procedure in
  `runbook/operation/backup-restore.md`.
- Test SQL on the test realm first. Production writes are human-only.
- Direct database clients use least-privilege users and a read-only production connection. Never use
  `root`. Back up before a write batch; DBeaver has no audit or pre-write backup.
- `smart_scripts` edits rewrite the full `(entryorguid, source_type)` block with `DELETE` + `INSERT`.
  Never a partial `UPDATE`, not even for a comment-only fix.

## GM tools

- GM commands are RBAC-gated. Use the least-privilege role that can do the job; see
  `runbook/gm/rbac-roles.md`.
- Every GM action must be auditable. Prefer a wrapped command now; the future website will use the
  same API and audit rules. Never bypass server-side checks with raw SQL.
- The in-game addon wraps existing commands; it must not bypass server-side permission checks.
- Never grant items, gold, or account changes from untrusted input without validation and audit.

## Visual interface

- The long-term visual layer is the future server website. See
  `decisions/ADR-010-website-as-visual-interface.md`.
- Build features API-first. Keep the command/API path, RBAC checks, and audit; add the website page
  later.
- Do not add one-off in-repo web UIs. The local GM panel was removed.
- Browser talks to an admin website BFF. Only the admin BFF holds the GM API secret; the browser
  never does.
- Web auth is separate from game SRP6. Link a web identity to a game account; do not reuse game
  session keys.
- Public, account, and GM dashboard zones are separate. The read-only API uses one shared HMAC
  secret. Write endpoints must add caller identity, RBAC, and audit before shipping.
- Visuals use basic HTML/CSS/JS first. New local JavaScript servers may use Bun after a pinned pilot.

## Modules

External modules live in `modules/`, each a subdir with its own `CMakeLists.txt`. Disable with
`-DDISABLED_AC_MODULES="mod1;mod2"`. See `modules/how_to_make_a_module.md`.

Project modules are tracked under `modules/mod-*`. They must build with the documented CMake
configuration and must not require edits to upstream core files.

## Persisting lessons

When a user correction reveals a lesson that generalizes, offer to persist it into these docs
(placement per `.ai/README.md` and `.agents/docs/README.md`): use the `/self-improve` skill if
installed, otherwise suggest the user install it and read
https://www.azerothcore.org/wiki/agentic-engineering
