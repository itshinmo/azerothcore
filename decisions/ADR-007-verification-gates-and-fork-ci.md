# ADR-007 — Verification gates and fork CI

- Status: accepted
- Date: 2026-11-12

## Context

Upstream CI is guarded to `azerothcore/azerothcore-wotlk`; this fork gets no automated gate. The
project wants minimum bugs, but not a full build and live e2e for every documentation edit. Live e2e
needs a running stack and `Warden.Enabled=0`.

## Decision

1. **Tiered gate.**
   - T0 docs: link check, reviewer.
   - T1 SQL/tooling: SQL lint, dry-run, test-DB apply, row checks, backup.
   - T2 C++/scripts: codestyle, cppcheck, build `-Werror`, unit tests, startup smoke.
   - T3 player-visible: T2 + live e2e + manual checklist + clean `Errors.log`.
   - T4 production: T3 + backup + staging + rollback plan + human approval.
2. **Dedicated test realm.** Separate databases or a documented reset, Warden off, GM accounts per
   role, unique character prefixes.
3. **Fork CI.** Add `.github/workflows/fork-ci.yml` with docs, SQL lint, C++ lint, build, unit tests,
   and dry-run. E2E smoke on label or manual dispatch. No upstream workflow edits.
4. **No new e2e unless asked.** Existing tests that break may be updated. The e2e policy remains.
5. **Evidence.** The verifier records exact commands, exit codes, relevant log lines, backup paths,
   and manual observations.
6. **Approval.** Verification does not replace human and reviewer approval.

## Alternatives considered

- **Always full.** Safest, slow; docs and SQL changes would wait on a full build.
- **Light gate.** Fast, more regressions.
- **No fork CI.** Local-only, but drift and missing prerequisites go unnoticed.
- **Use upstream CI as-is.** It skips on forks, so it is not a gate.

## Consequences

- Fast path for docs and SQL; stronger gate for player-visible and production changes.
- Fork CI costs GitHub Actions minutes.
- The test realm must be maintained and reset.
- Every change has an explicit evidence trail.
