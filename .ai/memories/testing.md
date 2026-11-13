---
description: Test levels, the test realm, live e2e, static checks, and the tiered verification gate. Read before writing tests or claiming a change is done.
last-verified: 2026-11-12
---

# Testing

The contract is [specs/testing-and-release.md](../../specs/testing-and-release.md). Procedure:
[.ai/skills/verify-change/SKILL.md](../skills/verify-change/SKILL.md).

## Levels

- **Unit** — Google Test under `src/test/`, isolated C++ with mocks. Fast, deterministic. Use for pure
  calculations, parsers, flags, spell/proc helpers, and extracted logic.
- **In-process integration** — Google Test with multiple components; no client login.
- **Live e2e** — Go under `e2e/`, `//go:build e2e`, AzerothGhost bots against a running auth+world+
  MySQL stack. Use only when the user asked or an existing test broke.
- **SQL/data checks** — apply to a test database, verify row counts and sample rows. No e2e for
  static data.
- **Static content** — the content audit against `acore_world`: dangling references, quest chain
  integrity, SmartAI validity, and script registry cross-checks. Read-only, no server. Contract:
  [specs/content-pipeline.md](../../specs/content-pipeline.md#verification).
- **Manual in-game** — GM commands and a real client. Required for player-visible behavior the
  automated suites cannot express.

## Static checks

- `python apps/codestyle/codestyle-cpp.py`
- `python apps/codestyle/codestyle-sql.py`
- `cppcheck --force --inline-suppr --suppressions-list=./.suppress.cppcheck src/`
- Build with `-Werror`.
- `make verify-docs` for markdown links, structure, and the generated command index.
- Content audit (planned): checks C-01 to C-12, run before a release and after any incoming data
  merge. It gates T1 for content data, not the default local loop.

## Test realm

- Separate databases or a documented reset. Never point tests at production.
- `Warden.Enabled=0` for AzerothGhost. Keep it on in production.
- Dedicated GM accounts; do not reuse player accounts.
- Unique character prefixes and cleanup after each e2e test.

## Tiers

| Tier | Applies to | Must pass |
|------|------------|-----------|
| T0 | docs | link check, command index check, reviewer |
| T1 | SQL/tooling | SQL lint; content audit clean or waived once the tool exists; auto apply when configured; row checks, backup; `VERIFY_SQL_APPLY=0` disables |
| T2 | C++/scripts | codestyle, cppcheck, `-Werror` build, unit tests |
| T3 | player-visible | T2 + startup smoke + manual checklist + clean errors; live e2e when asked |
| T4 | production | T3 + backup + staging + rollback plan + human approval |

## Rules

- Never weaken a test or skip a check to go green.
- Never invent an e2e suite unless the user asked.
- A test that needs a live stack is not part of the default local gate.
- Capture exact commands and results in the hand-off.
- A failure is a product bug, a test bug, an environment bug, or a missing prerequisite. Classify it;
  do not call it a flake without evidence.
