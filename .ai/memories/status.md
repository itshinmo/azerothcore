---
description: Current project status, last verified commit, known issues, open decisions, and next tasks. Read after overview on any task.
last-verified: 2026-11-13 (tree at 783784eb6; run git log -1 for the current commit)
---

# Status

## Where we are

- Phase 0–4 are complete for the current scope: foundation, tooling, test realm, backups, DBeaver,
  RBAC presets, command audit, command index, read-only GM API, in-game GM addon.
- The long-term visual layer is the future server website. No in-repo web UI exists.
- Branch: `local-server-setup`.
- Working tree: clean at the last verification; confirm with `git status`.
- Website work has not started. Shop and new content remain out of scope.

## Built and verified

- Local build and install under `env/dist/`.
- Local databases `acore_auth`, `acore_characters`, `acore_world`; test databases `acore_test_*`.
- Test realm ports 3824/8185; local ports 3724/8085.
- `make doctor`, `make verify-docs`, `make verify-sql`, `make verify-cpp`, `make verify-smoke`,
  `make verify-full`.
- Last full gate: exit 0. Docs 131, command index 657, cppcheck clean, 5982 unit tests, SQL test-realm
  apply, smoke doctor clean.
- RBAC, audit, API, and addon live/manual checks were performed. See the runbooks and ADRs.

## Known issues

1. **Realm offline after start.** `authserver` sets the offline flag after `worldserver` clears it.
   Clear it after starting:
   `UPDATE acore_test_auth.realmlist SET flag = flag & ~2 WHERE id = 1;`
   Fix belongs in `tools/dev/server.sh` and `tools/dev/test-realm.sh`.
2. **Smoke can leave a local worldserver running.** Seen more than once after `make verify-full`;
   `make status` then `make stop`. Reproduce and fix `verify-smoke`.
3. **SQL linter does not scan `data/sql/custom/`.** Custom SQL is applied by the updater but not
   linted by `apps/codestyle/codestyle-sql.py`.
4. **Fork CI has not been observed on GitHub.** Push and confirm once.
5. **GM API is read-only.** One shared HMAC secret, no caller identity. Write endpoints need signed
   actor identity, RBAC, and audit. Audit query uses the shared sync DB pool; audit search is
   newest-N only; structured request logging is planned.
6. **Addon final UX was not client-tested** after the GM-mode toggle and explicit visibility buttons.
7. **cppcheck suppressions target 2.22.** Pin or document the supported version.
8. **DBeaver production access is read-only via SSH tunnel.** No production host chosen yet.

## Open decisions

- Production provider, region, and budget.
- Website web-auth model: passkeys, OAuth, or Argon2id password hash.
- Shop delivery trust model.
- Client patch pipeline and timing for genuinely new zones/assets.
- Windows development path (WSL2 or Docker).

## Next tasks, in order

1. Fix the realm-flag and smoke-process bugs.
2. Correct stale docs after Phase 4.
3. Decide production host and finish the deploy runbook.
4. Decide website auth and write the OpenAPI contract for the existing GM API.
5. Build the website read-only MVP through an admin BFF.
6. Add audited write endpoints with caller identity and RBAC.
7. Shop and new content only after their decisions.

## New session checklist

1. Read `AGENTS.md`.
2. Read `.ai/memories/overview.md`.
3. Read this file.
4. Run `git status`, `git log -3 --oneline`, and `make doctor`.
5. Load the task-specific spec, decision, and runbook.
