---
description: Current project status, last verified commit, known issues, open decisions, and next tasks. Read after overview on any task.
last-verified: 2026-11-15 (docs 141/657; canal swim measured; test realm survived a client session)
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
  the artifacts on loopback; 43 tool tests.
- GM API wire contract (`specs/gm-api.openapi.yaml`): four implemented endpoints, HMAC signing,
  actor identity, all error codes and statuses.
- Content audit C-13: gossip-menu, gossip-option, and quest-available conditions validated against
  the rows the server loads; 5,931 rows, 0 findings.
- Fork CI now runs tool unit tests and triggers on `local-server-setup`; SQL lint covers
  `data/sql/custom/`. First green run: run `43597124091` on `881b11f19`, 5/5 jobs, 29 minutes total.
- Test realm supervisor logging: `tools/dev/test-realm.sh` now wraps each server and appends
  `start`, `signal=`, and `exit=` lines to `env/test/logs/<name>.supervisor.log`. A normal `stop`
  logs `exit=0` for both, so a silent death is now visible.

## Investigated 2026-11-14

- Stormwind canal swim: server VMap liquid reports type 13, level 95.47, status 8; the character is
  on the canal floor 9.58 yards below the surface. GM mode was off. Refined on 2026-11-15 below: the
  client's swim state fails, not only the animation. See
  [runbook/troubleshooting/stormwind-water.md](../../runbook/troubleshooting/stormwind-water.md).
- Test realm lifecycle: after the client exited, both test servers were stopped and the `screen`
  sessions were dead. The start script does not stop on logout; root cause unconfirmed. See
  [runbook/troubleshooting/test-realm-stops.md](../../runbook/troubleshooting/test-realm-stops.md).
- Client trust: auth checks the client build; `StrictVersionCheck=1` adds an executable SHA1 check;
  MPQs are not checked at login. Warden is runtime anti-cheat with configured checks and is off on
  the test realm. `specs/security.md` updated.

## Investigated 2026-11-15

- Stormwind canal swim, measured on a clean 3.3.5a build 12340 client with god mode on: server
  reports liquid entry 13, surface `95.474075`, floor `85.891525`, status 8 (under water); the
  client reports `IsSwimming()` nil on the floor, sinks straight through when dropped 1 yd under the
  surface, and its camera renders underwater fog. Terrain water (Eastern Strand) swims normally in
  the same client and session. The HD patch set is exonerated; the fault is client-side WMO liquid
  handling. Recipe and data: [stormwind-water.md](../../runbook/troubleshooting/stormwind-water.md).
- Test realm death did not reproduce: one full client session (login 14:19:58, character list
  14:52:51, quit) left both servers running for 40+ minutes, and `wineserver -k` on the CrossOver
  bottle did not stop them either. WoWSilicon's force quit only SIGKILLs Wine-matching PIDs; that
  predicate matched zero processes and none of the server PIDs. The 2026-11-14 death is still
  unexplained. Instrumentation, code reference, and log format:
  [test-realm-stops.md](../../runbook/troubleshooting/test-realm-stops.md).
- `PacketLogFile` writes nothing useful alone: the file is created on the first packet, but packets
  are only logged for sessions that enabled `.packetlog on`. Use the client's `IsSwimming()` and
  `.gps` instead.

## Next tasks

1. Static spawn map page. Blocked on the map imagery decision in `decisions/OPEN-QUESTIONS.md`.
2. Decide the production host and finish the deploy runbook.
3. Decide website auth. The GM API wire contract already exists at
   `specs/gm-api.openapi.yaml`.
4. Build the admin BFF/dashboard and the read-only website MVP through it.
5. After the dashboard: remaining GM API writes (item grant, mail, ban, RBAC, server control) and the
   branches that need an online player. `writes_disabled`, `rate_limited`, and `audit_failed` are
   reachable now with the documented curl recipe.
6. Audit v2 remainder: map-bounds validation (blocked on reference data) and C-06 phase
   reachability.
7. Triage the 1,972 minors when content work starts; they are cosmetic or expected data.
8. Shop and new content only after their decisions.
9. Canal swim: extract `DBFilesClient/LiquidType.dbc` and the Stormwind WMO liquid data from the
   played client's MPQs and compare with `DataDir`. Then repeat the probe in a second WMO water body
   to show whether all WMO liquid fails or only Stormwind.
10. Test realm death: keep the supervisor log; capture it on the next occurrence, with `screen -ls`
   and the unified log, before restarting.
11. Add server-side water movement validation if the cheat risk is accepted: swim flag vs
    `GetLiquidData()` status, swim-speed enforcement, mismatch logging. Not implemented, and it does
    not fix the client.

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

1. **GM API coverage is partial and gated on the dashboard.** `kick` and `unstuck` are the only
   audited writes. Item grant, mail, ban, RBAC, and server control are not built, and several error
   branches (`player_busy`, `teleport_failed`, `audit_failed`, `writes_disabled`, rate limit,
   timeout/shutdown) are untested. The new writes and the branches that need an online player will be
   exercised through the admin BFF/dashboard before they ship; `writes_disabled`, `rate_limited`,
   and `audit_failed` are reachable with the documented curl recipe now. The API still uses one shared
   HMAC secret for transport; `X-GM-Actor` identifies the human but the BFF remains the only holder of
   the secret. Audit query uses the shared sync DB pool; audit search is newest-N only; structured
   request logging is planned.
2. **cppcheck suppressions target 2.22.** Local Homebrew has 2.22.0; the runner's packaged version is
   unrecorded. A green cpp-lint job does not prove the version, because unmatched suppressions are not
   errors. Quote `cppcheck --version` in any CI failure before changing a suppression.
3. **DBeaver production access is read-only via SSH tunnel.** No production host chosen yet.
4. **CI build pins the distribution CMake 3.28 and a system Boost_DIR.** The runner's CMake 3.31 has
   no FindBoost module, and the image's automatic Boost search points at the wrong tree. Configure
   now resolves `/usr/lib/*/cmake/Boost-*/BoostConfig.cmake` explicitly. Revisit when the Boost and
   CMake toolchains on the runner are modernized.
5. **Stormwind canal swim is client-side WMO liquid.** Measured 2026-11-15 on a clean client:
   server reports water entry 13 at level `95.474075` with status 8, the client reports
   `IsSwimming()` nil, sinks to the floor, and refuses to rise, while terrain water swims in the same
   session. The server cannot force swim state. Next step is a client MPQ check of
   `LiquidType.dbc` and the WMO liquid, plus a second WMO water body. See
   [stormwind-water.md](../../runbook/troubleshooting/stormwind-water.md).
6. **Test realm death is unreproduced and instrumented.** The 2026-11-14 double death left no
   shutdown log, no crash report, and no `.dmp`. On 2026-11-15 the realm survived a full client
   session and `wineserver -k`; WoWSilicon's force quit only targets Wine-matching PIDs, which
   excludes the servers. `tools/dev/test-realm.sh` now writes
   `env/test/logs/<name>.supervisor.log` with `start`, `signal=`, and `exit=` lines to name the
   signal on the next occurrence. See [test-realm-stops.md](../../runbook/troubleshooting/test-realm-stops.md).

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
