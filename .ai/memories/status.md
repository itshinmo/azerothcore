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

## Session record — 2026-11-20 (collections live + QoL batch 1)

Collections verified in game by the owner; the transmog outfit panel needed two rounds of fixes in
the vendored addon (`outfits.lua`: complete per-slot save snapshot incl. `slot,0`, model undress +
real-item preview on load, pending glows from `RefreshPendingGlows` only — local divergences in
`modules/mod-transmog-plus/README.md`, commit `2603dc2bd`). Cast-bar "delay" diagnosed as missile
travel time, retail-authentic, no fix. Client bundle stays on WoSSilicon; ObjectFade (sets
`objectFade 0`) ships inside Reforged `patch-E.mpq`, harmless.

**RFC-003 Group A batch 1 landed** ([ADR-021](../../decisions/ADR-021-leveling-qol-batch-1.md)):
- `mod-auto-learn-spells` (new local module): class trainer spells learned automatically at
  level-up/each login via the core `Trainer` availability filter; no spell list, no config.
  LEARN_SPELL wrappers (class mounts, druid flight forms) stay trainer visits.
- Dual spec at level 30, free (`MinDualSpecLevel = 30` in `worldserver.conf.dist` + live config).
- Auto flight paths **dropped** by owner decision (players discover FPs; RFC-003 amended).
- Build green, `make test` green, server restarted clean (0 errors). Owner in-game checklist in
  the ADR pending.

**Group C landed** ([ADR-022](../../decisions/ADR-022-aoe-looting.md)): vendored official
`mod-aoe-loot` (AGPL-3.0, glue removed, module_string SQL self-applied). AoE loot is ON by
default per character (upstream default; `.aoeloot off` to toggle); group loot rules respected;
mail for full bags off by default. Upstream companion config `Rate.Corpse.Decay.Looted = 0.01`
recorded in the ADR as a playtest revisit, not set.

**Group D core landed** ([ADR-023](../../decisions/ADR-023-cross-faction-social-layer.md)): 7
AllowTwoSide config flips (chat, channels, groups, guilds, arena teams, shared neutral AH with
15%/25% neutral-cut cost, calendar); RBAC 25/26/27/28/29/51 granted to Player role 195 via
`data/sql/custom/db_auth/crossfaction_player_rbac.sql` (moderator-only before); same-group PvP
suppression is native (group check before FFA). `mod-cfbg` vendored for cross-faction BGs/arenas
(Wintergrasp off; live CFBG.conf required — code defaults would disable the module). aoe-loot
module SQL restructured base→updates for the codestyle gate. Deferred: mod-Faction-Free (core
file replacement, unvendorable). Solo queue/personal teams/queue-anywhere landed the next day
(ADR-024, below); currency consolidation still deferred (RFC sequencing).

**Group D PvP queueing slice** ([ADR-024](../../decisions/ADR-024-pvp-queueing-slice.md),
2026-11-21): `mod-arena-3v3-solo-queue` vendored (`.qsolo rated`, solo MMR from 1500, NPC
template 1000003) — upstream issue #61 (slot-4 character-cache OOB, open upstream) closed at the
fork level with bounds guards in `src/server/game/Cache/CharacterCache.cpp` (write+read; deliberate
fork core change). `mod-join-anywhere`: `.queue bg <name>` solo BG queue from anywhere, full
battlemaster ladder mirrored (disable-table + no-play-time checks included).
`mod-personal-arena-teams`: rated premades auto-create the leader's personal team and re-sync
members on every queue attempt. Owner full-session test list prepared, delivery on request.

**Client crash at character creation (2026-11-21, transient — watch item):** while creating a
female human warrior the client hit ERROR #132 (access violation in a REP MOVS over a BLP2
texture header, i.e. a texture-load failure on the creation screen's preview model). Server-side
clean (no errors, no server involvement — appearance is client-only until Create). The combo
(female human warrior, face 8 / hair 20 / hair color 14 / facial 4 — stored on character `Te`,
guid 9) **did not reproduce** on retry. Likely a one-off texture glitch in the client's Ascension
creation-pack data (the pack swapped `CharSections.dbc` for its expanded options). If it recurs:
suspect a missing/broken BLP for that combo in the pack, workaround = different appearance combo,
real fix = client-patch pipeline (repair the pack's CharSections/texture set). Client Cache purge +
WoSSilicon patch re-apply are the standard first steps.

**Client bundle change (2026-11-21, owner):** `patch-S.mpq` (Reforged v1.5.8) was deleted from
the client — it caused client-side performance issues in Orgrimmar; performance is fine without
it. The bundle spec in `runbook/operation/client-bundle.md` was updated (11 custom MPQs now).
What patch-S contained is unknown (encrypted MPQ — `mpyq` cannot list it); if a future update
needs the Reforged S content, re-test Orgrimmar performance on a fresh client.

**Auto-learn verified by the owner (2026-11-21) for all classes, death knights excluded** (owner
choice: DKs need their starting-quest progression, and the catch-up pass would front-load the
DK trainer spells there — behavior note, not fixed). Shaman totems additionally verified working
via the granted totem items. **Tests 1-7 verified by the owner (2026-11-21):** auto-learn (all classes, DK excluded), dual
spec at 30 free (incl. the 1000g gossip price fix), XP bonuses, Ancestral Wisdom, dungeon XP
split, AoE loot, cross-faction social (say/emotes, groups with groupmate suppression, guilds,
shared AH, mail — also mail QoL verified: no postage, instant), transmog outfits (earlier).
**Tasks 8-11 (BGs, 3v3 solo queue, personal arena teams, and the full queue-pop side of
queue-from-anywhere) move to a dedicated group-content session** — with two clients the owner
cannot join battlegrounds (client limitation; noted 2026-11-21). WSG's MinPlayersPerTeam was
temporarily set to 1 for the test attempt and reverted to 5. Queue-from-anywhere's queue/leave
side remains solo-testable.

**Transmog collection + collections panel rework (2026-11-21, owner decisions; committed and
merged into local-server-setup):**
- Collection unlock now hybrid: soulbound items collect on pickup; unbound items unlock on
  **equip** or on the new **Ctrl+right-click** action, which collects **and soulbinds** the item
  (Ascension's mechanic). **Equipping also soulbinds** (owner: an equipped look can never be
  traded for its appearance). The Ctrl+click hook is `ContainerFrameItemButton_OnClick` +
  `UseContainerItem` with a 2s per-slot throttle: per-button login hooks never fire (3.3.5
  creates bag buttons lazily) and `UseContainerItem` alone did nothing on this client either.
  Visible chat feedback on every collect and every reject. Login scans go bound-only. History
  not purged.
- **Every transmog-able tooltip carries the collection line**: collected = cyan
  (`|cff00ccffAppearance collected|r`, owner picked cyan over green), uncollected = magenta with
  the Ctrl+click hint; ineligible items get no line.
- **Thrown weapon subclass** added to the addon's subclass table (was a TWFERROR on thrown);
  lances and fishing poles mapped too.
- **Dual-wield preview** fix: the preview model applies slots in a fixed order, main hand before
  off-hand (the 3.3.5 model keeps one 1H weapon per hand-pair; random pairs() order made one
  weapon overwrite the other).
- **Armor-type freedom**: `Transmog.AllowMixedArmorTypes = 1` + `Transmog.IgnoreReqClass = 1`
  (ADR-012 revision 2026-11-21); weapon subclasses stay gated (dagger stays dagger).
- **Backpacks fully removed** from mod-transmog-plus (server file, config block, addon tab +
  protocol gone; unlock item 27621 deleted and the world table dropped by the world SQL file,
  the three characters-side tables dropped by the new
  `data/sql/db-characters/updates/mod_transmog_plus_2026_11_21_backpacks_characters.sql` —
  applied live, tables confirmed gone).
  The client models were already absent after patch-S came off.
- **Toys = the pets pattern (account-wide + permanent, spell-granted)**: the journal records a
  held toy on the account (`mod_forever_journal_account_toys`, characters DB) the first time any
  character obtains it, then **grants the toy's use spell** (`spelltrigger_1 = 0`) to every
  character on the account — `character_spell`, live learnSpell + chat announce for new ones,
  `GrantAccountToys` on character creation. Once collected, always collected (deleting the item
  changes nothing). The journal's Use button casts the granted spell (item path kept for toys in
  bags), so cooldowns come from the spell DBC — the "toys have no cooldown" bug is gone. Toy
  rows are now `<item>,<state>,<spell>`.
- **Mounts**: mid-session refresh fixed (COMPANION_UPDATE now refreshes an open Mounts tab);
  the catalog carries each mount's required riding rank (from the teaching item's
  RequiredSkillRank) and the journal greys collected mounts the character cannot ride yet with
  "Requires riding skill (X)" — they never hide, they summon only when the skill suffices.
- **AoE loot removed** (ADR-022 status → removed): the upstream quest-item collector breaks on
  solo kills (issue #44) and the owner dropped the feature. Module directory deleted (lives in
  git history), RFC-003 Group C amended.
- **Instance-card circles removed** (the round portrait icon on journal dungeon/raid cards).
- **White boss models**: open — the journal previews through the client's creature data; broken
  models are the Ascension pack's model replacements missing textures (possibly tied to the
  patch-S deletion). Investigate with the client-patch pipeline; not fixed yet.
- The research-implementations skill exists at `.ai/skills/research-implementations/SKILL.md`
  (browse prior implementations before building; report findings, then plan).

**Dungeon XP split** ([ADR-012](../../decisions/ADR-012-progression-rates.md) revision 2026-11-20
(2), owner decision from the rate discussion): `mod-dungeon-xp` — dungeon/raid mob XP × 0.33
(owner asked deeper than the proposed 0.5), dungeon quest XP ×2 on top of the global rate (4x
one-time); data-driven detection via QuestSortID → area → instance map; repeat dungeons ≈85k XP/h
vs questing ~300k/h, so spam is no longer the meta. Rate discussion outcome: 2x stays (bonus
sources measured as supplements: rares ~1% of journey, gathering 2-4%, never outruns questing;
real fast paths are rested casuals and DF spam — the latter now closed).

**RFC-003 Group A complete** ([ADR-012](../../decisions/ADR-012-progression-rates.md) revision
2026-11-20): `mod-xp-bonus` (rare kills 100×lvl, gathering 15×lvl with daily cap 200, BG wins
75×lvl — all × `Rate.XP.Kill`, skill gates mirrored from the core so forged casts cannot farm XP)
and `mod-ancestral-wisdom` (+10% XP per max-level account char, owner picked "all XP" so it
multiplies the bonus sources too). Owner in-game checklist pending; values are playtest knobs.

## Session record — 2026-11-19 (manual classic sweep)

One working session continuing the raid batches: the bot rig stayed paused and the owner ran every
classic instance manually on a cheated level-80 mage (god mode, instant casts), with the agent
recording results, sweeping `env/dist/logs/` after each run, and fixing tooling bugs as they
surfaced.

**Classic verification complete.** 26/26 dungeons (25 bot-green + Blackfathom Deeps manual) and the
classic raids (MC, BWL, ZG, AQ20, AQ40 manual; UBRS bot-green). Every run cleared; zero server
errors or exceptions in the logs all day. Results and per-run findings:
[runbook/audits/2026-11-19-manual-instance-runs.md](../../runbook/audits/2026-11-19-manual-instance-runs.md).
Onyxia's Lair is still open (listed under WotLK raids — the 3.3.5 rework is a level-80 entry). TBC
is the next sweep.

**Findings worth keeping (all documented in the checklist, none blocking):**

- BWL Chromaggus: the lever encounter is one-shot by script; a GM `.respawn` of the boss re-applies
  `SetImmuneToAll(true)` and the lever stays flagged unselectable — GM-respawn artifact only, retail
  flow intact. Live workaround: `.gobject add temp 179148`. No code or data change (an early SQL
  "fix" for the portcullises was inverted and reverted before any local apply).
- ZG Edge of Madness: the four summon events share one daily phase (14-day-spaced anchors, 24h
  occurence), so the brazier can only ever pick Gri'lek; and Gurubashi Mojo Madness (19931) has no
  loot/vendor/quest source. Effectively GM-only content as shipped. Candidates for a future data
  pass if the owner wants it player-reachable.
- AQ40 Viscidus: the kill gate requires an auto-attacking attacker, so spell-only kills stall at
  1%. Retail-intended; documented and left untouched per the blizzlike policy.
- Client map gap: pressing M in classic instances shows the world map — the 3.3.5 client's
  DungeonMap.dbc has no classic floors. Client-patch pipeline territory, parked.

**GM Helper 0.4.3** (tools/gm-addon/): tabbed frame (Commands / Instances / Self), two-column
scrollable instance teleport lists (82 entries from LFGDungeons.dbc plus the vanilla sub-wings it
omits, `.go xyz` to the areatrigger entrance), and a Self tab (solo cheat toggles, level 80, revive,
speed, 1k gold, 4x Portable Hole bags, best-gear-per-slot grant generated from item_template for
all 10 classes). Chat echo of every sent command; edit box cleared after send. Combat-guard removed
(chat commands are legal in combat). Two known client quirks handled: no GameTabButtonTemplate
template in the WoWSilicon FrameXML, and a generated middle .toc file silently skipped — both data
tables now ship in the single file GMHelperInstances.lua.

**Offline addon harness** (tools/dev/addon-harness/): extracts the client's real FrameXML
template/font list from its MPQs, loads the addon against a mock of the WoW API, clicks tabs/rows/
Self buttons, asserts the exact self-only command forms, flags text wider than its button. Lua
5.1-parse gate via luajit. New skill `.ai/skills/test-wow-addon` routes every future addon change
through it. Generators merged into tools/dev/gen-addon-manifest.py (instances + gear, one file,
hard-fails on incomplete classes).

**Policies recorded:** development targets the local realm only (test realm unused until deploy;
`dev` and `ptr` realms get created at launch); verification runs confirm blizzlike behavior —
retail-intended mechanics get documented, not changed.

## Decisions recorded 2026-11-20

- The test realm was deleted: `acore_test_*` databases, `acore_test`/`acore_admin` users,
  `tools/dev/test-realm.sh`, the `make test-realm` target, `verify-sql`'s apply step, and the
  test-realm runbooks. Development runs on the local realm only. At launch, the local realm is fully
  reset and renamed **live**; a **dev** and a **ptr** realm are created then; e2e stays dormant until
  they exist. Policy: [ADR-018](../../decisions/ADR-018-realm-strategy.md).
- The manual instance sweep closed: classic complete (2026-11-19) + 7/16 TBC dungeons (2026-11-20),
  zero findings, zero server errors all day. Remaining TBC/WotLK instances are assumed functioning
  until a player ticket or bug report triggers a run. Policy:
  [ADR-019](../../decisions/ADR-019-instance-scope-closed.md).
- The 5-instances-per-hour account limit (retail rule) was hit during the sweep; mechanism
  documented in the audit record (`acore_characters.account_instance_times`, per account, re-saved
  at logout — a delete only sticks while logged out). Owner cleared it themselves.
- Modernization planning done; RFCs 001–003 drafted with the owner's decisions recorded (client
  bundle = Reforged + Ascension Character Customization + mod-forever-ui; collections =
  transmog-plus + account-bound + forever-journal; QoL/social slate with small-balance bonus XP,
  Ancestral Wisdom at +10%, and an extended cross-faction scope including shared guilds and mail).
  RFC-002/003 wait for the owner's go, with collections first in build order. (Later 2026-11-20:
  the RFC-001 downloads landed and its first step — bundle verification — completed; see the
  verified-bundle entry below.)
- **Client bundle verified 2026-11-20** (owner in-game, 120 FPS): the supported client is the
  WoWSilicon exe + its d3d9 + Ascension patch-A (client MPQ + 8 server DBCs) + Reforged patches
  B–U + the Transmog/Journal/GM Helper addons on `~/Games/wotlk-clean`. The St0ny exe measured 14
  FPS (x87 emulation) and was reverted; St0ny's patcher and ForeverUIPatcher are incompatible in
  either order; mod-forever-ui was removed entirely by owner decision (its glue conflicted with
  the Ascension glue). Record:
  [runbook/operation/client-bundle.md](../../runbook/operation/client-bundle.md).
- Branch: `modernization/realm-cleanup-and-features` (worktree) carries the removal plus the
  modernization research/RFCs; `local-server-setup` is untouched until merge.

## Decisions recorded 2026-11-19 (second session)

- Verification runs exist to confirm blizzlike behavior, not to change it. When a mechanic turns
  out to work as retail intended (even if it inconveniences a solo GM run — e.g. Viscidus's
  melee-only kill gate), it is documented as intended and left untouched. Only non-blizzlike or
  broken behavior becomes a fix.
- Development targets the **local realm only**. The e2e test realm stays as-is and unused until
  deploy; at launch we create two more realms named **dev** and **ptr**. Do not run `make
  verify-sql`'s test-realm apply or other test-realm writes during development; lint SQL directly
  (`python apps/codestyle/codestyle-sql.py`) and let the local worldserver apply pending updates on
  restart.

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
  `runbook/troubleshooting/test-realm-stops.md` (removed 2026-11-20, ADR-018).
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
  `runbook/troubleshooting/test-realm-stops.md` (removed 2026-11-20, ADR-018).
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
7. ~~Test realm death instrumentation.~~ Moot: the test realm was deleted on 2026-11-20
   ([ADR-018](../../decisions/ADR-018-realm-strategy.md)).
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
9. Manual solo verification of dungeons and raids ran from 2026-11-19 and **closed 2026-11-20**
   ([ADR-019](../../decisions/ADR-019-instance-scope-closed.md)): classic complete (26/26 dungeons,
   classic raids all clear, findings documented in the checklist) plus 7/16 TBC dungeons with zero
   findings and a zero-server-error record for both days. Remaining TBC/WotLK instances are assumed
   functioning; a player ticket or bug report triggers a run.
   Checklist and results:
   [runbook/audits/2026-11-19-manual-instance-runs.md](../../runbook/audits/2026-11-19-manual-instance-runs.md).
   Onyxia's Lair (the level-80 rework) is verified on a player report like the rest.

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
   signal on the next occurrence. See `runbook/troubleshooting/test-realm-stops.md` (removed 2026-11-20, ADR-018).
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
