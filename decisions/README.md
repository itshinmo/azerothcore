# Decisions (ADRs)

Decisions and their rationale, for choices that are hard to reverse. ADRs are never rewritten; a later
decision supersedes one and both link each other.

## Conventions

- File name `ADR-NNN-<slug>.md`, numbered in order.
- Status is `proposed` until a human accepts it, then `accepted`.
- Disagreement with an accepted ADR goes to an RFC, not a review exception.
- No secrets, production hostnames, credentials, or player data.

## Index

| ADR | Status | Decision |
|-----|--------|----------|
| [ADR-001](ADR-001-agent-knowledge-layer.md) | accepted | `.ai` knowledge layer, role agents, strict approval gate, pointer adapters |
| [ADR-002](ADR-002-custom-content-isolation-and-ids.md) | accepted | tracked modules + tracked SQL, reserved ID ranges, client-patch boundary |
| [ADR-003](ADR-003-runtime-topology.md) | accepted | native macOS dev, Ubuntu 24.04 production, native binaries |
| [ADR-004](ADR-004-database-gui.md) | superseded by ADR-008 | custom Node database GUI |
| [ADR-005](ADR-005-gm-tools-and-rbac.md) | accepted | GM handbook, least-privilege RBAC, audit, module API, in-repo addon |
| [ADR-006](ADR-006-shop-policy.md) | accepted (policy); trust model open | cosmetics + convenience only; delivery trust model TODO |
| [ADR-007](ADR-007-verification-gates-and-fork-ci.md) | accepted, test-realm element superseded by [ADR-018](ADR-018-realm-strategy.md) | tiered verification, dedicated test realm, fork CI |
| [ADR-008](ADR-008-database-access-with-dbeaver.md) | accepted | DBeaver for local/test; read-only production via SSH tunnel |
| [ADR-009](ADR-009-rbac-command-permission-precedence.md) | accepted | core RBAC permissions override legacy `command.security` |
| [ADR-010](ADR-010-website-as-visual-interface.md) | accepted | future server website is the long-term visual layer; API-first, separate web auth |
| [ADR-011](ADR-011-world-data-and-content-verification.md) | accepted | one read-only extractor feeds the public catalog and the content audit; playerbots as production infrastructure rejected |
| [ADR-012](ADR-012-progression-rates.md) | accepted, revised 2026-11-21 | default 2x experience for all players, everything else 1x; per-account override removed; 2026-11-20 revision adds small-balance bonus XP sources (gathering, rare kills, BG wins via mod-xp-bonus) and Ancestral Wisdom (+10% XP per max-level char via mod-ancestral-wisdom); 2026-11-20 (2) dungeon XP split; 2026-11-21 mail QoL (no postage, instant delivery) |
| [ADR-013](ADR-013-server-and-client-before-website.md) | accepted, revised 2026-11-17 | base game (measured exit gate), custom content, website, launch; custom-content planning may start once the gate is met; exit-gate deviations in ADR-017, ADR-019 |
| [ADR-014](ADR-014-bruno-api-test-client.md) | accepted | committed Bruno collection is the manual GM API test path |
| [ADR-015](ADR-015-playerbot-test-rig.md) | accepted (rig built 2026-11-17) | playerbots live only in a throwaway test rig outside the repo; findings port back |
| [ADR-016](ADR-016-bot-driven-verification.md) | accepted, amended by ADR-017 | dungeon clears assumed green, player report triggers a rig replay; raids verified proactively |
| [ADR-017](ADR-017-bot-rig-paused.md) | accepted | bot rig paused; manual verification by the owner is the current content check |
| [ADR-018](ADR-018-realm-strategy.md) | accepted | test realm deleted; local realm reset + renamed `live` at launch; `dev` + `ptr` realms created at launch; e2e dormant until then |
| [ADR-019](ADR-019-instance-scope-closed.md) | accepted | manual instance sweep closed (classic complete + 7 TBC dungeons, TBC zero findings); remaining content assumed functioning, verified via player reports |
| [ADR-020](ADR-020-collections-transmog-stack.md) | accepted, revised 2026-11-22 by [ADR-025](ADR-025-account-wide-collections.md) | collections stack: mod-transmog-plus + mod-account-bound + mod-forever-journal vendored; licenses, storage, config, and the Warpweaver NPC (910012, ten capitals) recorded |
| [ADR-021](ADR-021-leveling-qol-batch-1.md) | accepted | leveling QoL batch 1: auto-learn class spells via `mod-auto-learn-spells` (core trainer data, no spell list), dual spec at level 30 free, auto flight paths dropped |
| [ADR-022](ADR-022-aoe-looting.md) | removed | AoE looting was vendored from `mod-aoe-loot`; removed 2026-11-21 — its quest-item collector breaks on solo kills (upstream #44) |
| [ADR-023](ADR-023-cross-faction-social-layer.md) | accepted | cross-faction social layer: 7 AllowTwoSide config flips (chat, channels, groups, guilds, arena teams, shared AH, calendar), RBAC already shipped, mod-cfbg vendored (Wintergrasp off), quest/rep access deferred (unvendorable module) |
| [ADR-024](ADR-024-pvp-queueing-slice.md) | accepted | PvP queueing slice: mod-arena-3v3-solo-queue vendored (.qsolo rated, solo MMR, fork-patched character-cache bounds for slot 4), .queue bg from anywhere (mod-join-anywhere, full battlemaster ladder), personal arena teams for rated premades (mod-personal-arena-teams); currency consolidation deferred |
| [ADR-025](ADR-025-account-wide-collections.md) | accepted | account-wide collections: durable per-account mount/pet/toy tables, spells materialized into character_spell for every alt, riding/faction gate the summon only; AccountBound mounts/pets off |
| [ADR-026](ADR-026-transmog-npc-only-and-preview.md) | accepted | transmogrifier-only appearance changes: server-side NPC gate, Journal tab hidden until the gossip, client-side UI-only preview; hidden hand-specific preview items fix dual-wield, thrown and hidden armor without a client patch |
| [ADR-027](ADR-027-client-patch-pipeline.md) | accepted | client-patch pipeline: MPQ-only, `patch-X/Y/Z` family (item data / white models / map-UI), whole-file replacement, source-of-truth DBC rule, no exe/DLL, third-party pack policy, manifest ledger |
| [ADR-028](ADR-028-objective-engine-board-chronicle.md) | proposed | shared objective engine, Adventure Board and Chronicle: four task types, lazy daily/weekly resets, 7 daily slots, zone focus, gold reroll, character vs account scope, in-memory progress with batched writes |
| [ADR-029](ADR-029-objective-reward-currencies.md) | proposed | three reward currencies (Adventure Marks account, Mythic Coins and Raider's Commendations character); gossip vendors in Stormwind and Orgrimmar; gear first, materials second, cosmetics third; no pay-for-power |
| [ADR-030](ADR-030-era-aware-content-model.md) | proposed | era-aware content model: `era` 0/1/2 plus level bands and faction/zone filters; Classic data first, schema ready for all eras |
| [ADR-031](ADR-031-world-treasures.md) | proposed | hand-placed world treasures: one chest, one unique item via native `maxcount=1`, 30-60 minute shared respawn, iconic open-world placement, 100-item target in batches of 20 |
| [ADR-032](ADR-032-map-poi-layer.md) | accepted | map POI layer: baked `ServerMapPOI` addon in `patch-Z`, stock icons, red PvP overlay, dynamic world-boss/Crow's Cache hooks |
| [ADR-033](ADR-033-pvp-rulesets.md) | proposed | PvP rulesets: per-character PvE/War/High Risk, capital pledge, outdoor XP, High Risk gold-only chest with killer first claim and victim recovery, mercenary FFA, Outlaw 5/+5/cap 60 with no early removal, same-zone status and continent alert, anti-abuse; module with four approved seams; no purchased power; client-patch visual follow-up |
| [ADR-034](ADR-034-mythic-plus-old-content.md) | proposed | Mythic+ for old content: five-player dungeons first, per-era key ladders 1–20 with a 232 dungeon ceiling (284 reserved for raids), pre-generated scaled item copies in `1100000–1899999` (obtainable) and `1900000–1999999` (QA/non-obtainable), Mythic Coins with no cap, no P2W; data-only `Item.dbc` patch required (ADR-027 item-data pipeline); raids deferred; ladder, scope, reset and economy values are recommendations pending owner |
| [ADR-036](ADR-036-client-dll-patches.md) | proposed | client DLL patches: a reviewed `DivxDecoder.dll` proxy whose exports are loader forwarders, plus one in-memory code patch per targeted function at fixed VAs guarded by image base, mapping, prologue bytes and rel32 range; launcher hash pinning, tracked source, reproducible build; narrows ADR-027's no-executable clause for this case only |
| [ADR-035](ADR-035-race-class-combos.md) | proposed | extended race/class combos: technical direction only (client `CharBaseInfo.dbc` + server `playercreateinfo` ship together, existing Blizzard assets, whole-file DBC carrier); the proposed twelve-pair target and five-pair batch are open owner decisions in [OPEN-QUESTIONS](OPEN-QUESTIONS.md) |

Open questions: [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).
