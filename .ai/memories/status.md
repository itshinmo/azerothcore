---
description: Current project status, last verified commit, known issues, open decisions, and next tasks. Read after overview on any task.
last-verified: 2026-11-14 (docs check 135 files / 657 commands; upstream sync build green)
---

# Status

## Where we are

- Phase 0–4 are complete for the current scope: foundation, tooling, test realm, backups, DBeaver,
  RBAC presets, command audit, command index, GM API read endpoints, in-game GM addon.
- Phase 5 started: the GM API has audited `kick` and `unstuck` writes behind
  `GmApi.AllowWrites`, a signed `X-GM-Actor`, RBAC, and `gm_audit_log`.
- The long-term visual layer is the future server website. No in-repo web UI exists.
- Branch: `local-server-setup` is the integration branch. Confirm with `git status`.
- Website work has not started. Shop and new content remain out of scope.

## Decisions recorded 2026-11-14

- [ADR-011](../../decisions/ADR-011-world-data-and-content-verification.md): one read-only
  extractor feeds both the public world catalog and the content audit; the audit is a release gate.
  Playerbots were considered and rejected; the rejection and its revisit condition are recorded in
  the ADR.
- [ADR-012](../../decisions/ADR-012-progression-rates.md): default 3x experience, everything else
  1x, per-account override intended but not implemented.
- Branch topology: `master` mirrors upstream and fast-forwards only; `local-server-setup` is the
  integration branch; task branches are created from it. Procedure updated in
  [runbook/development/worktrees-and-branches.md](../../runbook/development/worktrees-and-branches.md).
- Rates applied to `src/server/apps/worldserver/worldserver.conf.dist`. Existing local, test, and
  production configuration files keep their previous values until regenerated or edited.

## Next tasks

1. Triage the baseline content audit: 3 blockers first, then the 167 majors. Waivers only for known
   data, with a reason and an owner.
2. World data export artifacts per `specs/world-data.md`.
3. Public read API and static spawn map page. The live spawn overlay is deferred until a secretless
   public read surface is designed.
4. Coverage metric wired into CI (`make content-audit`).

No playerbots work is planned.

## Built and verified

- Content audit v1 (`make content-audit`, read-only): 2,032 findings against `acore_world`
  (3 blockers, 167 major, 1,862 minor); coverage 74-85% per level band; 15 unit tests pass.
  Procedure: [runbook/operation/content-audit.md](../../runbook/operation/content-audit.md).
- Upstream sync 2026-11-14: `upstream` remote added (official AzerothCore); `master`
  fast-forwarded to `upstream/master` `2948c203f`; merged into `local-server-setup` as `4346c29d2`
  (8 upstream commits). One conflict, `.agents/skills` symlink versus upstream directory; resolved
  by keeping the symlink to `../.ai/skills`. `make verify-docs` and `make build` passed. Safety tag
  `backup/pre-upstream-sync-2026-11-14`.
- Local build and install under `env/dist/`.
- Local databases `acore_auth`, `acore_characters`, `acore_world`; test databases `acore_test_*`.
- Test realm ports 3824/8185; local ports 3724/8085.
- `make doctor`, `make verify-docs`, `make verify-sql`, `make verify-cpp`, `make verify-smoke`,
  `make verify-full`.
- Last gate on this branch: docs 132, command index 657, cppcheck clean, 5985 unit tests, smoke ok
  with ports free afterwards.
- `tools/dev/server.sh` and `tools/dev/test-realm.sh` clear the authserver offline flag after start,
  so the realm shows online. `stop` escalates to `SIGKILL` and `verify-smoke` fails if ports stay
  bound after stop.
- GM API manual checks on the local stack: status/audit reads, successful `kick` and `unstuck`,
  `cannot_target_self`, `forbidden_target_security`, `target_not_found`, and the 401/404/405/409
  paths. Each write produced the intended `pending` + outcome audit rows.
- Client and addon checks on the local stack: GM Helper menu, GM mode toggle, visibility buttons,
  lookups, teleport, and input rendering. Confirmed by the human on 2026-11-13.
- Test realm start verified 2026-11-13: `acore_test_auth.realmlist.flag` is 0 after start, so the
  authserver offline bit is cleared correctly.
- Remaining untested API branches are deferred to the future GM dashboard; see known issues.
- RBAC, audit, and API live/manual checks were performed. See the runbooks and ADRs.

## Known issues

1. **SQL linter does not scan `data/sql/custom/`.** Custom SQL is applied by the updater but not
   linted by `apps/codestyle/codestyle-sql.py`.
2. **Fork CI has not been observed on GitHub.** Push and confirm once.
3. **GM API write coverage is partial.** `kick` and `unstuck` are audited writes. Item grant, mail,
   ban, RBAC, and server control are not built. Manual branch coverage is partial: successful
   kick/unstuck, `cannot_target_self`, `forbidden_target_security`, `target_not_found`, and the
   401/404/405/409 paths are tested. `player_busy`, `teleport_failed`, `audit_failed`,
   `writes_disabled`, rate limiting, and timeout/shutdown paths are not. The API still uses one shared
   HMAC secret for transport; `X-GM-Actor` identifies the human but the BFF remains the only holder of
   the secret. Audit query uses the shared sync DB pool; audit search is newest-N only; structured
   request logging is planned.
4. **cppcheck suppressions target 2.22.** Pin or document the supported version.
5. **DBeaver production access is read-only via SSH tunnel.** No production host chosen yet.

## Open decisions

- Production provider, region, and budget.
- Per-account experience override mechanism (module command versus GM-only).
- Map imagery source for the public spawn pages.
- Shop product list revision before shop work starts.
- Website web-auth model: passkeys, OAuth, or Argon2id password hash.
- Shop delivery trust model.
- Client patch pipeline and timing for genuinely new zones/assets.
- Windows development path (WSL2 or Docker).

## Next tasks, in order

1. Decide production host and finish the deploy runbook.
2. Decide website auth and write the OpenAPI contract for the GM API, including `X-GM-Actor`.
3. Build the website read-only MVP through an admin BFF.
4. Exercise the remaining GM API branches (`player_busy`, `teleport_failed`, `audit_failed`,
   `writes_disabled`, rate limit, timeout/shutdown) through the GM dashboard.
5. Add the remaining audited writes (item grant, mail, ban, RBAC) with caller identity and RBAC.
6. Shop and new content only after their decisions.

## New session checklist

1. Read `AGENTS.md`.
2. Read `.ai/memories/overview.md`.
3. Read this file.
4. Run `git status`, `git log -3 --oneline`, and `make doctor`.
5. Load the task-specific spec, decision, and runbook.
