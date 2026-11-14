---
description: Current project status, last verified commit, known issues, open decisions, and next tasks. Read after overview on any task.
last-verified: 2026-11-14 (docs check 139 files / 657 commands; tool tests 42; upstream sync build green)
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

## Built since the last update

- World data export (`make world-export`): 140,650 files, 566 MB, 17.6 s; counts npc 29,945 /
  item 46,096 / quest 9,464 / object 21,580 / 33,318 spawn sets. Read API (`make world-api`) serves
  the artifacts on loopback; 42 tool tests.
- Fork CI now runs tool unit tests and triggers on `local-server-setup`; SQL lint covers
  `data/sql/custom/`. The first GitHub run is pending a push.

## Next tasks

1. Static spawn map page. Blocked on the map imagery decision in `decisions/OPEN-QUESTIONS.md`.
2. Decide the production host and finish the deploy runbook.
3. Decide website auth and write the OpenAPI contract for the GM API, including `X-GM-Actor`.
4. Build the website read-only MVP through the admin BFF.
5. Exercise the remaining GM API branches (`player_busy`, `teleport_failed`, `audit_failed`,
   `writes_disabled`, rate limit, timeout/shutdown) and add the remaining audited writes.
6. Audit v2: map-bounds validation, conditions audit, C-06 phase reachability.
7. Triage the 1,972 minors when content work starts; they are cosmetic or expected data.
8. Confirm the first fork CI run after a push.
9. Shop and new content only after their decisions.

No playerbots work is planned.

## Built and verified

- Content audit v1 (`make content-audit`, read-only): after part 1 triage, 0 blocker, 0 major,
  1,972 minor; coverage 78.89% overall; 20 unit tests pass. Procedure:
  [runbook/operation/content-audit.md](../../runbook/operation/content-audit.md).
- Content audit blocker fixed: three Baron Longshore spawns carried a numeric `ScriptName`.
  Evidence, fix, and verification: [runbook/audits/2026-11-14-content-audit.md](../../runbook/audits/2026-11-14-content-audit.md).
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

1. **Fork CI has not been observed on GitHub.** It now triggers on pushes to `local-server-setup`
   as well as `master`; the first run is pending a push.
2. **GM API write coverage is partial.** `kick` and `unstuck` are audited writes. Item grant, mail,
   ban, RBAC, and server control are not built. Manual branch coverage is partial: successful
   kick/unstuck, `cannot_target_self`, `forbidden_target_security`, `target_not_found`, and the
   401/404/405/409 paths are tested. `player_busy`, `teleport_failed`, `audit_failed`,
   `writes_disabled`, rate limiting, and timeout/shutdown paths are not. The API still uses one shared
   HMAC secret for transport; `X-GM-Actor` identifies the human but the BFF remains the only holder of
   the secret. Audit query uses the shared sync DB pool; audit search is newest-N only; structured
   request logging is planned.
3. **cppcheck suppressions target 2.22.** Local Homebrew has 2.22.0. The GitHub runner may package a
   different version; quote `cppcheck --version` in any CI failure before changing a suppression.
4. **DBeaver production access is read-only via SSH tunnel.** No production host chosen yet.

## Open decisions

- Production provider, region, and budget.
- Per-account experience override mechanism (module command versus GM-only).
- Map imagery source for the public spawn pages.
- Shop product list revision before shop work starts.
- Website web-auth model: passkeys, OAuth, or Argon2id password hash.
- Shop delivery trust model.
- Client patch pipeline and timing for genuinely new zones/assets.
- Windows development path (WSL2 or Docker).

## New session checklist

1. Read `AGENTS.md`.
2. Read `.ai/memories/overview.md`.
3. Read this file.
4. Run `git status`, `git log -3 --oneline`, and `make doctor`.
5. Load the task-specific spec, decision, and runbook.
