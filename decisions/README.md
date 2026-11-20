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
| [ADR-012](ADR-012-progression-rates.md) | accepted, revised 2026-11-20 | default 2x experience for all players, everything else 1x; per-account override removed; 2026-11-20 revision adds small-balance bonus XP sources (gathering, rare kills, BG wins via mod-xp-bonus) and Ancestral Wisdom (+10% XP per max-level char via mod-ancestral-wisdom) |
| [ADR-013](ADR-013-server-and-client-before-website.md) | accepted, revised 2026-11-17 | base game (measured exit gate), custom content, website, launch; custom-content planning may start once the gate is met; exit-gate deviations in ADR-017, ADR-019 |
| [ADR-014](ADR-014-bruno-api-test-client.md) | accepted | committed Bruno collection is the manual GM API test path |
| [ADR-015](ADR-015-playerbot-test-rig.md) | accepted (rig built 2026-11-17) | playerbots live only in a throwaway test rig outside the repo; findings port back |
| [ADR-016](ADR-016-bot-driven-verification.md) | accepted, amended by ADR-017 | dungeon clears assumed green, player report triggers a rig replay; raids verified proactively |
| [ADR-017](ADR-017-bot-rig-paused.md) | accepted | bot rig paused; manual verification by the owner is the current content check |
| [ADR-018](ADR-018-realm-strategy.md) | accepted | test realm deleted; local realm reset + renamed `live` at launch; `dev` + `ptr` realms created at launch; e2e dormant until then |
| [ADR-019](ADR-019-instance-scope-closed.md) | accepted | manual instance sweep closed (classic complete + 7 TBC dungeons, TBC zero findings); remaining content assumed functioning, verified via player reports |
| [ADR-020](ADR-020-collections-transmog-stack.md) | accepted | collections stack: mod-transmog-plus + mod-account-bound + mod-forever-journal vendored; licenses, storage, config, and the Warpweaver NPC (910012, ten capitals) recorded |
| [ADR-021](ADR-021-leveling-qol-batch-1.md) | accepted | leveling QoL batch 1: auto-learn class spells via `mod-auto-learn-spells` (core trainer data, no spell list), dual spec at level 30 free, auto flight paths dropped |
| [ADR-022](ADR-022-aoe-looting.md) | accepted | AoE looting via vendored `mod-aoe-loot` (official module, AGPL-3.0, defaults kept; `.aoeloot on/off`, group rules respected) |
| [ADR-023](ADR-023-cross-faction-social-layer.md) | accepted | cross-faction social layer: 7 AllowTwoSide config flips (chat, channels, groups, guilds, arena teams, shared AH, calendar), RBAC already shipped, mod-cfbg vendored (Wintergrasp off), quest/rep access deferred (unvendorable module) |

Open questions: [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).
