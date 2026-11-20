# RFC-002 — Collections: account-wide appearances, mounts, pets (toys per character)

- Status: accepted (implementation gated on the Phase 1 gate release and the owner's go)
- Date: 2026-11-20
- Author: agent session (modernization/realm-cleanup-and-features)
- Decisions: made by the owner on 2026-11-20 (see Decision record below)

## Problem

Players expect a retail-style Collections experience (the owner's screenshots: appearances, sets,
heirlooms, pets, toys tabs). Nothing exists in the fork. Constraints (from the owner + ADRs): tracked
modules only, no core edits, custom SQL in `data/sql/custom/db_*`, no paid tiers, addon-first client
that later embeds into our own MPQ patch so it ships as part of the client, not as an addon drop.

## Proposal

Adopt the buildthehomelab stack (all actively maintained, no core patches, designed to coexist):

1. **wow-mod-transmog-plus** (AGPL-3.0, last commit 2026-11-02) → `modules/mod-transmog-plus`
   (folder name matters). Slot-based transmog, account-wide appearance collection with retail-style
   unlock triggers (loot/bags/mail/AH/guild bank/disenchant/quest rewards/login scan), one-tile-per-
   look, sets browser, illusions, `/transmog` open-anywhere. No client patch needed. Addon included.
   Migration SQL exists from upstream `azerothcore/mod-transmog` (do not run both).
2. **mod-account-bound** (GPL-2.0 in LICENSE vs GPLv3 badge — resolve before vendoring) →
   account-wide mounts, pets, titles, reputations (+ optional achievements, professions, friends).
   Zero custom tables: materializes into core `character_spell` etc., account scope via
   `characters.account`. Login-friendly (INSERT IGNORE batches, no learn-spell burst).
3. **wow-mod-forever-journal** (MIT, last commit 2026-11-06) → the Collections window: Dungeons/
   Raids, Quests, Lore, Mounts, Pets, Toys tabs + Appearances tab from transmog-plus. Toys defined in
   a world table seeded from retail `Toy.db2` (69 toys on 3.3.5 item pool); ownership = item in
   bags/bank.

Storage rule adopted by the stack: appearance/outfit/illusion data in dedicated custom tables keyed
by account id (in the characters DB), mounts/pets materialized into core tables. No `acore_auth`
custom tables. GM API/RBAC/audit untouched — player self-service via addon whisper protocol
(copy transmog-plus's flood/spoof fixes from 2026-10).

Client path: install addons now; at launch embed `Transmog/` + `Journal/` addon folders into our
realm MPQ patch (same files, ships as part of the client). Optional look packs (druid forms, totems,
demons) each need their own client patch — deferred.

Adoption order: transmog-plus → account-bound → journal (Appearances tab auto-registers). Each lands
as its own module commit + verification.

## Alternatives

- azerothcore/mod-transmog (official, very active): Rochet2 lineage, NPC gossip, collection system
  newer and less account-wide-verified; superseded by transmog-plus.
- SoloCollectionsPlatform: full platform, gameplay-changing (ride at level 1), DLL injection,
  does not compose. Rejected.
- Build our own: weeks of work duplicating proven modules.

## Impact

- 3 new tracked modules + their SQL. The upstream default transmog NPC id (190012) sits **below** the
  reserved creature range — remap it into `910000+` per `runbook/database/id-registry.md` at adopt
  time (the registry forbids ids below a reserved range).
- Startup backfill cost on login/boot for large character tables; monitor.
- Licenses: AGPL obligations (keep text + attribution; public repo satisfies network-source rule);
  AccountBound license version must be pinned before vendoring.
- Gated by the Phase 1 gate as read through
  [ADR-019](../../decisions/ADR-019-instance-scope-closed.md) (classic complete + 7 sampled TBC
  dungeons + the zero-error record). First feature in build order per owner decision.

## Open questions

Resolved by the owner on 2026-11-20:

1. ~~AccountBound license: GPL-2.0 or 3.0?~~ → Agent resolves at adoption time (read the LICENSE
   file, keep its text and attribution; copyleft is fine for a public repo).
2. ~~Account-wide or per-character toy collection?~~ → **Per character** (journal behavior as
   shipped).
3. ~~Achievements/professions/friends sharing on or off initially?~~ → **Collections-first plus
   friends**: mounts, pets, titles, and friends shared ON; achievements, professions, and
   reputations OFF (reputations excluded per owner instruction of 2026-11-20).
4. ~~Custom toys list?~~ → **No custom toys yet**; seed only the 69 baseline entries.

## Decision record

Owner decisions, 2026-11-20: adopt the buildthehomelab stack as proposed; AccountBound first-run
config = mounts, pets, titles, friends ON, achievements, professions, reputations OFF; toy
ownership per character; no custom toys yet; license version resolved at adoption time.
Implementation order: transmog-plus → account-bound → journal; addons now, embedded into the
realm MPQ patch at launch. First in build order when the Phase 1 gate releases.

<!-- When accepted, fold the durable content into specs/ or decisions/ and move the RFC to archived/. -->
