# ADR-024 — PvP queueing slice (Group D completion)

- Status: accepted
- Date: 2026-11-20
- Implements: [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md) Group D remaining items (owner instruction, 2026-11-20)

## Decision

1. **3v3 solo queue** — vendored official `azerothcore/mod-arena-3v3-solo-queue`
   (`modules/mod-arena-3v3-solo-queue`, source `5cfecf79ba725db14371ed1d0841546c18e1ce4f`,
   2026-09-29, AGPL-3.0; repo glue/images/tests/cmake template removed, source/conf/data as
   shipped). Players queue rated 3v3 alone with `.qsolo rated` (NPC template `1000003` exists in
   data, spawned nowhere by default). Talent-role matchmaking, separate solo MMR from 1500,
   temporary personal teams. Upstream defaults kept (`Solo.3v3.MinLevel = 80` gates the solo
   bracket). Upstream issue #61 is **open and live in the vendored revision**: the module's fake
   bracket (arena slot 4) writes past `CharacterCache`'s 4-slot array on team joins. The module
   already suppresses the visible player-field writes for that slot; this fork adds bounds
   guards to `CharacterCache` (write and read) so slot 4 simply has no cache entry (the module
   reads its team id from the DB) — silent cache corruption closed at the fork level.
2. **Queue-from-anywhere** — new local module `modules/mod-join-anywhere`: `.queue bg
   <wsg|ab|av|eots|sota|ic|random>` joins a solo BG queue anywhere. The eligibility ladder
   mirrors the core battlemaster path (including the disable-table and no-play-time checks) and
   the same script hook runs, so no queue rule is bypassed — only the walk is removed. Group
   queueing stays battlemaster-only by design. Named `.queue` because `/join` is the client's
   reserved channel command.
3. **Personal arena teams** — new local module `modules/mod-personal-arena-teams`: rated arena
   premades queue without a charter; a leader without a team of that bracket gets one created
   free, named after them, and the group joins it. The hook runs the ensure-members pass on every
   queue attempt (a refused first attempt must not poison later ones — the core's rated-group
   check requires every member's team id to match the leader's), and the team is resolved by
   captain+bracket, not by bare captain. Hook-side creation before the queue handler's team
   checks; premades with real teams and skirmishes untouched. Solo rated 3v3 belongs to the
   solo-queue module.
4. **Deferred (RFC-003):** currency consolidation (Justice/Valor, Honor/Conquest, rolling caps) —
   medium effort, gated behind Group D core settling; its own slice later.

## IDs (ID registry)

- Creature `1000003` — "Arena 3v3 Solo" NPC template from the vendored solo-queue module
  (outside the project ranges; recorded here so future content avoids it).
- npc_text `1000004` — the solo-queue NPC's greeting, same module SQL.
- RBAC `950150` — "Command: queue bg (project)" permission (project range), granted to
  "Role: Player Commands" (199) by `data/sql/custom/db_auth/queue_anywhere_command.sql`.

## Tests and verification

- `make build` + `make test` green; both custom modules and the vendor compile; binary carries
  all three script symbols.
- T3 manual checklist (owner in game):
  1. `.queue bg ab` from a city street → queued without an NPC; `.queue bg random` also works;
     `.queue bg wsg` while already queued → core's standard error.
  2. `.qsolo rated` on a level-80 → solo 3v3 queue starts (the .qsolo command response shows it).
  3. Rated 2v2/3v3/5v5 premade without a team → team named after the leader created free,
     partners added; the queue proceeds. A premade with an existing team behaves unchanged.
  4. Deserter debuff: `.queue bg` refuses (same error as the NPC path).
- Watch at playtest: solo-queue logs for anything resembling issue #61; personal-team names
  colliding with real guild-style names is harmless (separate name space).
