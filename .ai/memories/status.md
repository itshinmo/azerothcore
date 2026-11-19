---
description: Current project status, last verified commit, known issues, open decisions, and next tasks. Read after overview on any task.
last-verified: 2026-11-19 (bot rig paused; manual verification is the current content check)
---

# Status

## Where we are

- Phase 0–4 are complete for the current scope: foundation, tooling, test realm, backups, DBeaver,
  RBAC presets, command audit, command index, GM API read endpoints, in-game GM addon.
- Phase 5 resumed: the GM API has audited writes for item grant, mail, account ban, account
  permissions, server control, `kick`, and `unstuck` behind `GmApi.AllowWrites`, a signed
  `X-GM-Actor`, RBAC, and `gm_audit_log`; server control also needs `GmApi.AllowServerControl`.
  Manual testing uses the committed Bruno collection
  ([ADR-014](../../decisions/ADR-014-bruno-api-test-client.md)); it no longer waits for a dashboard.
- Roadmap for 2026-11-16: base game fully functional and stable, then custom content, then the
  website, then launch ([ADR-013](../../decisions/ADR-013-server-and-client-before-website.md)).
- Website work has not started and is not part of the current phase. Custom content and shop work
  remain out of scope until the base game is done.
- Branch: `local-server-setup` is the integration branch. Confirm with `git status`.

## Decisions recorded 2026-11-19

- Dungeon clears are assumed to work. The classic sweep is the record; the TBC and WotLK 5-man
  batches are cancelled. A player report is the trigger to run a dungeon again in the rig; the rig
  keeps its data, worktree, traces, and ledger for that.
  Policy: [ADR-016](../../decisions/ADR-016-bot-driven-verification.md).
- Raid batches were the work on 2026-11-19: classic raids
  (`mc, bwl, zg, aq20, aq40, ony`) and TBC raids (`gruul, kara, kara-chess`), two parties
  concurrent, 10-bot default. Only `ony` (0/1) and `mc` (0/11) finished, both wipes before speed
  mode; the rest stopped when the rig worldserver vanished, and the owner then paused the rig.
  Results:
  [the ledger](../../runbook/audits/2026-11-17-bot-dungeon-runs.md).
- Server-side water movement validation is out of scope. It does not fix the client; the root cause
  is external (WoWSilicon#67). Keep `libSiliconPatch` off.
- The bot rig is paused from 2026-11-19. Its processes are stopped; data, traces, ledger, worktree,
  and binaries stay for a future resume. Manual verification by the owner is the current content
  check. Policy: [ADR-017](../../decisions/ADR-017-bot-rig-paused.md).

## Decisions recorded 2026-11-18

- The playerbot sweep runs every 5-man dungeon once, then every raid entry once: classic 27 tokens,
  TBC 16, WotLK 16, classic raids 6, TBC raids 3. Deadmines and Shadowfang Keep are skipped because
  they are already green. All four Maraudon tokens run; `kara-chess` counts as its own token.
  **Superseded by [ADR-016](../../decisions/ADR-016-bot-driven-verification.md) and paused by
  [ADR-017](../../decisions/ADR-017-bot-rig-paused.md).**
- The sweep is gated: one batch at a time, each run reported individually, and the next batch starts
  only on the owner's go. Results go in
  [runbook/audits/2026-11-17-bot-dungeon-runs.md](../../runbook/audits/2026-11-17-bot-dungeon-runs.md),
  which also records the batch scope and the raid sizing rule.
- Concurrency: four dungeon parties, two raid parties. Pool plans force raid entries to the 10-bot
  catalogue default; a failed raid is rerun at the map cap before a finding is filed.
- Measurement integrity: cameras only while a measured batch runs. A GM body may enter an instance
  on a throwaway run, never on a batch run, because a nearby real player can change bot behavior.

## Session record — 2026-11-18 (second session)

One long working session. Everything below is committed with this session; no push.

**Playerbot classic sweep — complete.** Plan `tp-20261118-160918-1` ran all 27 classic 5-man tokens
once: **24 success, 3 fail**, 11,452s wall time, average 1,834s. Full table and findings:
[runbook/audits/2026-11-17-bot-dungeon-runs.md](../../runbook/audits/2026-11-17-bot-dungeon-runs.md).
`Deadmines` and `SFK` remain green from 2026-11-17. Concurrency was raised 4 → 5 → 7 → 8 as the
client closed; the machine held at 8 parties.

- `lbrs` failed `no_progress` at 7/7 and **passed on replay** after the no-progress clock was held
  once every roster boss is credited.
- `brd-db` failed `no_progress` at 3/9 and **passed on replay** after the combat-progress sample
  started reading the whole party instead of only the tank.
- `bfd` is still **open** after four runs. Two defects were fixed in the harness (swim replan,
  portal door exemption); two remain (`F3c` advance/objective livelock on an empty path, `F3d` wave
  gate starvation). Last run reached 8/10 with three of four fires lit before being stopped by hand.

**Rig harness changes** (all in `~/wow/playerbot-rig/core/modules/mod-dungeon-clear`, not this
repository, documented in the ledger): party-wide progress hash, no-progress hold at full boss
credit, swim-leg replan through `SwimPathfinder`, Portal of Aku'mai in `IsNavigationIgnored`.
Rollback binaries: `env/dist/bin/worldserver.pre-20261118` and `worldserver.pre-swimfix`.

**GM API hardening.**
- One structured `module.gm-api` request log line per request: method, target, status,
  `duration_ms`, actor, address. Bodies, signatures, nonces and the secret are excluded.
- Audit read gained exact `account` / `command` / `result` filters and `before_id` id-cursor paging,
  with `invalid_parameter` on malformed values and an `account_name` index in
  `data/sql/custom/db_auth/gm_audit.sql` (idempotent, applied locally and to the test realm).
- Contract bumped to 1.2.0; runbook, `specs/gm-tools.md`, Bruno README and the Audit request docs
  updated.
- Tests: 6,000 pass, 23 of them GM API. New cases cover the audit query parser, cursor bounds and
  filter validation.
- Live local pass: 200 reads and filtered audit, 401 unsigned, 400 malformed filter, 403
  `writes_disabled`, 404, 405. Write success paths and `player_busy`, `inventory_full`,
  `mailbox_full`, `teleport_failed` still need two online clients.

**Developer documentation.** New
[runbook/development/environment-overview.md](../../runbook/development/environment-overview.md):
what the project is, the local/test/rig environments side by side (ports, databases, client copies),
first-day order, where everything lives, first failures, beginner safety. `setup-macos.md` gained a
clear GM-account flow, client checklist and realm-port troubleshooting; `commands.md`, `README.md`,
`CONTRIBUTING.md` and `runbook/README.md` point to it. `playerbot-rig.md` gained prerequisites,
layout, ready checklist, `stdbuf`/`screen -wipe` start commands, an `expect` fallback for console
input, the realm-port/offline-flag fixes, result-file map, rebuild procedure and a troubleshooting
table.

**Rig reachability fixes.** The rig authserver kept advertising world port `8085` after the DB row
said `8086`; restarting it re-read the table. The realm row also needed `flag=0`: the authserver
marks realms offline at boot, and the worldserver clears its own realm only at its own startup, so
the clear has to come after the authserver. Both are now documented in `playerbot-rig.md` and the
overview.

**Whitemane research.** Full analysis (feature inventory, player feedback, copy candidates with
effort/risk, do-not-copy list, decisions for the next session) is stored outside the repository at
`.agents/plans/whitemane-research/whitemane-research.ANALYSIS.md` (gitignored). Headline: copy their
QoL and collections/transmog; do not copy custom Heroic raids, Hardcore, Paragon, Timewalking or
Domination until Phase 1 is done.

**LAN play with a friend.** Plan recorded in the overview runbook and this session's findings: the
local stack is the LAN realm; set `acore_auth.realmlist.localAddress` to the Mac's LAN IP
(`192.168.100.17`, mask `255.255.255.0`) and keep `address=127.0.0.1`, then `make start`; the friend
uses `set realmlist <LAN-IP>:3724`. Do not run a second worldserver against `acore_characters`.

## Decisions recorded 2026-11-16

- [ADR-013](../../decisions/ADR-013-server-and-client-before-website.md): Phase 1 base game, Phase 2
  custom content, Phase 3 website, Phase 4 launch. Website-dependent work is deferred, including the
  admin BFF/dashboard, website auth, account and character pages, the spawn map page, and the `make
  world-api` serving surface. The world export and content audit stay active.
- [ADR-014](../../decisions/ADR-014-bruno-api-test-client.md): the committed Bruno collection in
  `tools/api-tests/bruno/` is the primary manual GM API test path. Curl stays as the headless
  fallback. Secrets live only in the ignored local environment file.
- Base-game verification is now the main work: scripts, quests, NPC spawns and behavior, client
  behavior, and stability.
- Open website questions are deferred, not dropped; see `decisions/OPEN-QUESTIONS.md`.

## Decisions recorded 2026-11-14

- [ADR-011](../../decisions/ADR-011-world-data-and-content-verification.md): one read-only
  extractor feeds both the public world catalog and the content audit; the audit is a release gate.
  Playerbots were considered and rejected; the rejection and its revisit condition are recorded in
  the ADR.
- [ADR-012](../../decisions/ADR-012-progression-rates.md): default 2x experience for every player,
  everything else at 1x; no per-account override, and Phase 2 rule-set pacing is an idea only.
- Branch topology: `master` mirrors upstream and fast-forwards only; `local-server-setup` is the
  integration branch; task branches are created from it. Procedure updated in
  [runbook/development/worktrees-and-branches.md](../../runbook/development/worktrees-and-branches.md).
- Rates applied to `src/server/apps/worldserver/worldserver.conf.dist`. Existing local, test, and
  production configuration files keep their previous values until regenerated or edited.

## Built since the last update

- GM API hardening 2026-11-18: one structured request log line per request (method, target, status,
  duration, actor, address; bodies and secrets excluded); audit reads gained exact
  `account`/`command`/`result` filters and `before_id` id-cursor paging with an
  `account_name` index; contract bumped to 1.2.0. Unit tests 6,000 pass (23 GM API). Live local pass:
  200 reads, filtered audit, 401 unsigned, 400 malformed filter, 403 `writes_disabled`, 404, 405.
  Write success paths and `player_busy`/`inventory_full`/`mailbox_full`/`teleport_failed` still need
  two online clients.
- World data export (`make world-export`): 140,650 files, 566 MB, 17.6 s; counts npc 29,945 /
  item 46,096 / quest 9,464 / object 21,580 / 33,318 spawn sets. Read API (`make world-api`) serves
  the artifacts on loopback (parked until Phase 3); 43 tool tests.
- GM API wire contract (`specs/gm-api.openapi.yaml`): read endpoints and the audited write set
  (item grant, mail, ban, RBAC, server control, kick, unstuck), HMAC signing, actor identity, all
  error codes and statuses.
- Content audit C-13: gossip-menu, gossip-option, and quest-available conditions validated against
  the rows the server loads; 5,931 rows, 0 findings.
- Fork CI now runs tool unit tests and triggers on `local-server-setup`; SQL lint covers
  `data/sql/custom/`. First green run: run `43597124091` on `881b11f19`, 5/5 jobs, 29 minutes total.
- Test realm supervisor logging: `tools/dev/test-realm.sh` now wraps each server and appends
  `start`, `signal=`, and `exit=` lines to `env/test/logs/<name>.supervisor.log`. A normal `stop`
  logs `exit=0` for both, so a silent death is now visible.
- Bruno collection (`tools/api-tests/bruno/`): status, audit, kick, unstuck, item grant, mail, ban,
  RBAC permissions, server cancel, and the four read requests. A collection pre-request script
  computes the HMAC headers; a committed environment example; the real environment file is ignored.
  Every request carries a `docs` block, and new requests must add theirs. Validated on 2026-11-16
  against a mock server that verified the signature independently, in Bruno CLI Safe Mode; a
  real-stack run is still pending.
- Content audit C-06 phase reachability: fixpoint model over SmartAI phase actions and timed action
  lists. 63 tool tests pass; on `acore_world` the real-data phase findings dropped to 16.
- GM API audited writes and reads implemented and merged: item grant, mail, ban, RBAC
  grant/deny/revoke, server control behind `GmApi.AllowServerControl`, plus account, character,
  online players, and instances reads. Contract and runbook updated.
- Live Bruno run on the local stack: status and audit return `200`; unstuck and kick return
  `409 cannot_target_self` because the target is the actor's own account. A test-realm/local port
  collision on GM API 8090 was found and fixed; the runbook records the rule.
- Full GM API live test 2026-11-16, human-driven from the Bruno desktop app against a second
  `SEC_PLAYER` account online in the world: reads (status, audit, account, character, online
  players, instances), writes (item grant, mail, unstuck, kick, offline-target 404s, bad-item 400,
  self-target 409), RBAC grant/deny/revoke incl. `already_granted`/`not_in_list`, ban incl.
  `longer_ban_exists` and unban, server cancel `200` after enabling `GmApi.AllowServerControl`, and
  the rate limit (`120 x 200` then `429`). Audit `pending` + outcome rows confirmed after writes.
  The human edited `worldserver.conf.dist` first; reverted, and the real `env/dist/etc/worldserver.conf`
  was changed instead — the `.dist` file is a build template, never the live config.
- Per-account XP override removed 2026-11-16 before any public promise: ADR-012 revised to 2x for
  all experience sources and one shared rate for all players; `modules/mod-xp-override`, its SQL,
  and its command row deleted; local `account_xp_override` table dropped and `command` row removed.
  The module was live-verified first: with `Rate.XP.Kill = 3`, override on gave base XP and off gave
  the rate-multiplied amount. A one-off worldserver crash during `.xp` testing was not reproduced
  under lldb and has no artifacts (AC has no POSIX crash handler); the lldb recipe lives in
  `/tmp/xp-repro.log` history.

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
  the same client and session. The HD patch set is exonerated; the fault is the client runtime, see
  the `libSiliconPatch` entry below. Recipe and data:
  [stormwind-water.md](../../runbook/troubleshooting/stormwind-water.md).
- Test realm death did not reproduce: one full client session (login 14:19:58, character list
  14:52:51, quit) left both servers running for 40+ minutes, and `wineserver -k` on the CrossOver
  bottle did not stop them either. WoWSilicon's force quit only SIGKILLs Wine-matching PIDs; that
  predicate matched zero processes and none of the server PIDs. The 2026-11-14 death is still
  unexplained. Instrumentation, code reference, and log format:
  [test-realm-stops.md](../../runbook/troubleshooting/test-realm-stops.md).
- `PacketLogFile` writes nothing useful alone: the file is created on the first packet, but packets
  are only logged for sessions that enabled `.packetlog on`. Use the client's `IsSwimming()` and
  `.gps` instead.
- Canal swim root cause: WoWSilicon's `libSiliconPatch.dll` (x87 to SSE2 rewrite) breaks the client's
  WMO liquid lookup. Disabling it restores swimming on the same client and server; the DLL bundled
  with 2.5.3 and 3.2.2 both reproduce. Client data is exonerated: 246 DBCs and 5744 map files from
  the played client are byte-identical to `DataDir`. Reported as
  [WoWSilicon#67](https://github.com/WoWSilicon/WoWSilicon/issues/67). Client-side behaviour is now
  verified on a client without performance DLL mods; see
  [stormwind-water.md](../../runbook/troubleshooting/stormwind-water.md).

## Next tasks

Order follows [ADR-013](../../decisions/ADR-013-server-and-client-before-website.md): base game, custom
content, website, launch. Phase 1 exit is a measured gate; playtests and a friends-only test VPS can
happen between phases.

### Phase 1 — base game (now)

Standing rituals, started 2026-11-17:

- Weekly upstream sync with `make sync-upstream`; first sync executed (31 upstream commits merged).
- Player bug reports: triage `acore_characters.bugreport` per
  [runbook/operation/bug-reports.md](../../runbook/operation/bug-reports.md).

Remaining:

1. Run the Bruno collection once on the local stack: status, audit, kick, unstuck; confirm the audit
   rows and record the result. Procedure: `runbook/gm/gm-api.md`.
2. Live-test the new GM API writes and reads through Bruno on a live stack, including the branches
   that need an online player.
3. Audit v2 remainder: map-bounds validation stays blocked on reference data; C-06 phase
   reachability is implemented.
4. Base-game verification checklist is built
   ([runbook/operation/base-game-verification.md](../../runbook/operation/base-game-verification.md)):
   character flow, leveling path at 2x, quest chains, dungeons, systems, client behavior,
   stability, and the result-recording procedure. Playing through it is the current Phase 1 work.
5. Triage the 1,972 minors when content work starts; they are cosmetic or expected data.
6. Keep `libSiliconPatch` off until WoWSilicon#67 is fixed; re-test after each launcher update and
   keep a second client copy (`~/Games/wotlk-test`) without the mod for client-side behaviour checks.
7. Test realm death: keep the supervisor log; capture it on the next occurrence, with `screen -ls`
   and the unified log, before restarting.
8. Playerbot test rig ([ADR-015](../../decisions/ADR-015-playerbot-test-rig.md),
   [ADR-016](../../decisions/ADR-016-bot-driven-verification.md)): kept as the debugging tool for
   player reports, not a standing sweep. Dungeons are assumed green; when a player reports a bug,
   reproduce it in the rig with `.dc test start <dungeon> [seed=] [trace=1]` and record the run in
   the ledger. Lives in `~/wow/playerbot-rig/` (fork core + mod-playerbots + mod-dungeon-clear,
   ports 8086/3725, databases `acore_pb_*` + `acore_playerbots`, all outside the repository); keep
   its data, worktree, traces, and ledger. User guide:
   [runbook/operation/playerbot-rig.md](../../runbook/operation/playerbot-rig.md). Ledger:
   [runbook/audits/2026-11-17-bot-dungeon-runs.md](../../runbook/audits/2026-11-17-bot-dungeon-runs.md).
   **Paused 2026-11-19** ([ADR-017](../../decisions/ADR-017-bot-rig-paused.md)): no process runs;
   resume only on the owner's explicit request. Gotchas: the driver
   **character name** is exact and case-sensitive (`Dcdriver`); SIGTERM holds the port ~30s, so rig
   restarts need SIGKILL and a free-port check. `bfd` keeps two open harness defects (`F3c`, `F3d`);
   replay it only when a player report needs it.
9. Manual solo verification of dungeons and raids is the current content check, active from
   2026-11-19: the owner runs each instance on a cheated level-80 character (`.cheat god`,
   `.cheat power`, `.cheat cooldown`, `.cheat casttime`, `.modify speed`, best gear and class spells)
   and reports findings per run. The agent correlates `env/dist/logs/` and files or fixes each
   finding. Checklist and results:
   [runbook/audits/2026-11-19-manual-instance-runs.md](../../runbook/audits/2026-11-19-manual-instance-runs.md)
   — bot-green entries are marked there to skip. The GM Helper addon 0.3.0 adds Instances and Self
   tabs for these runs (`tools/gm-addon/`, teleports from
   `tools/dev/gen-instance-manifest.py` output); the new tabs still need a local client test pass
   ([runbook/gm/addon.md](../../runbook/gm/addon.md)).

### Phase 2 — custom content

10. Custom-content planning (first: hardcore rule-sets) may start in parallel once the measured
    Phase 1 gate in [ADR-013](../../decisions/ADR-013-server-and-client-before-website.md) is met.
    Record each feature in a new ADR before implementation. Rule-set pacing (for example, hardcore
    locked at 1x without a player command) needs its own ADR; see
    [ADR-012](../../decisions/ADR-012-progression-rates.md).

### Phase 3 — website

11. Decide website auth (passkeys, OAuth, or Argon2id). Record it in an ADR extending ADR-010.
12. Build the admin BFF/dashboard and the read-only website MVP through it.
13. Static spawn map page, after the map imagery decision.
14. Account and character pages, after their priority decision.
15. Shop frontend, after the shop decisions.

### Phase 4 — launch

16. Choose the production host, region, and budget.
17. Finish the deploy runbook, deploy, verify production health and backups, and publish.

Playerbots exist only in the throwaway test rig ([ADR-015](../../decisions/ADR-015-playerbot-test-rig.md)),
never on a production server and never inside this repository.

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
- Remaining untested API branches are exercised through the Bruno collection on a live stack; see
  known issues.
- RBAC, audit, and API live/manual checks were performed. See the runbooks and ADRs.

## Known issues

1. **GM API live branches are mostly tested.** 2026-11-16 the human ran the full Bruno set live: all
   reads, item/mail/unstuck/kick, RBAC grant/deny/revoke conflicts, ban incl. `longer_ban_exists`,
   server cancel with `GmApi.AllowServerControl=1`, rate limit, and the 401/404/405/409 paths. Still
   untested: `player_busy`, `teleport_failed`, `inventory_full`, `mailbox_full`, `audit_failed`,
   timeout/shutdown — they need a wedged player, full bags/mailbox, or a dying world. `writes_disabled`
   was verified 2026-11-18 (403 with the flag off). The API still uses one shared HMAC secret for
   transport; `X-GM-Actor` identifies the human and the Phase 3 BFF will be the only holder of the
   secret. Audit query and writes use the shared sync DB pool. Audit reads support exact
   `account`/`command`/`result` filters and id-cursor paging; free-text search stays open. Every
   request logs one structured line (method, target, status, duration, actor, address).
2. **cppcheck suppressions target 2.22.** Local Homebrew has 2.22.0; the runner's packaged version is
   unrecorded. A green cpp-lint job does not prove the version, because unmatched suppressions are not
   errors. Quote `cppcheck --version` in any CI failure before changing a suppression.
3. **DBeaver production access is read-only via SSH tunnel.** No production host chosen yet.
4. **CI build pins the distribution CMake 3.28 and a system Boost_DIR.** The runner's CMake 3.31 has
   no FindBoost module, and the image's automatic Boost search points at the wrong tree. Configure
   now resolves `/usr/lib/*/cmake/Boost-*/BoostConfig.cmake` explicitly. Revisit when the Boost and
   CMake toolchains on the runner are modernized.
5. **Test realm death is unreproduced and instrumented.** The 2026-11-14 double death left no
   shutdown log, no crash report, and no `.dmp`. On 2026-11-15 the realm survived a full client
   session and `wineserver -k`; WoWSilicon's force quit only targets Wine-matching PIDs, which
   excludes the servers. `tools/dev/test-realm.sh` now writes
   `env/test/logs/<name>.supervisor.log` with `start`, `signal=`, and `exit=` lines to name the
   signal on the next occurrence. See [test-realm-stops.md](../../runbook/troubleshooting/test-realm-stops.md).
6. **BFD has two open harness defects.** `F3c`: while standing on the fires anchor, `DcAdvanceAction`
   rebuilds an empty path every tick (`segs=0`) and never yields to the objective action — a CPU
   livelock that produced 4,003 identical log lines. `F3d`: after the third fire,
   `KillCreatureEngage(Barbed Crustacean, 1, 90yd)` never pulls the wave, which stood 33–73 yd away,
   so the fourth fire was never clicked. Both live in the rig harness, not this repository.
   Deferred until a player report needs a BFD replay. Details:
   [ledger](../../runbook/audits/2026-11-17-bot-dungeon-runs.md).

## Open decisions

Before launch:

- Production provider, region, and budget.
- Custom content scope (hardcore rule-sets and other unique features) after Phase 1.

Deferred until Phase 3 — website ([ADR-013](../../decisions/ADR-013-server-and-client-before-website.md)):

- Website web-auth model: passkeys, OAuth, or Argon2id password hash.
- Map imagery source for the public spawn pages.
- Account and character page priority.
- Shop delivery trust model.
- Shop product list revision before shop work starts.

Not blocking now:

- Client patch pipeline and timing for genuinely new zones/assets.
- Windows development path (WSL2 or Docker).

## New session checklist

1. Read `AGENTS.md`.
2. Read `.ai/memories/overview.md`.
3. Read this file.
4. Run `git status`, `git log -3 --oneline`, and `make doctor`.
5. Load the task-specific spec, decision, and runbook.
