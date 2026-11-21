# ADR-022 — AoE looting

- Status: removed (2026-11-21)
- Date: 2026-11-20
- Implements: [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md) Group C (owner go, 2026-11-20)

## Removal (2026-11-21, owner decision)

**Removed.** Owner testing found quest items on nearby unopened corpses could not be looted: the
upstream quest-item collector requires the corpse's allowed-looters set to contain the player,
which solo kills never populate (upstream issue #44, still open). The module's core behavior
cannot be fixed from the module side without forking the loot pipeline, and the feature's value
does not justify maintaining a fork. `modules/mod-aoe-loot` is deleted (it stays in git history
at the commit that vendored it); `mod_aoe_loot.conf.dist` goes with it. [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md)
Group C drops the item. If it is ever wanted back, vendor a fixed fork or ship
`AOELoot.Enable = 0`-safe upstream code with the quest-item path rewritten.

## Decision

Adopt area looting by vendoring the official `azerothcore/mod-aoe-loot` module
(`modules/mod-aoe-loot`, source `957f9a1a686141d96c8b55e9431bfe2a0fb26e46`, 2026-10-31,
AGPL-3.0 — license retained, upstream repo glue removed, source/conf/data as shipped; the
module's `data/sql` seeds only the core `module_string` table and self-applies at startup).

Behavior: **on by default for every character** (upstream default; `.aoeloot off` toggles it off
per character, `.aoeloot on` back). When on, looting one nearby corpse collects the loot of all
corpses in range (`AOELoot.Range`, 55y) into one window, under the group's loot rules when
grouped (`AOELoot.Group`). Items that do not fit the bags are left on the corpse by default;
`AOELoot.MailEnable = 1` mails overflow items (quest items auto-collected from nearby corpses
are never mailed; quest items from the clicked corpse can mail). Defaults kept at upstream
values — no tuning without playtest evidence.

Rationale: leveling mobs die fast on this server; corpse-by-corpse looting is the main
dead-time tax on pack clearing. AoE loot is player-togglable (`.aoeloot off` any time),
does not change drop tables or loot rules, and upstream shipped group-rule handling.

## Tests and verification

- `make build` compiles the module (no fork API changes needed; `Object::CustomData` present).
- T3 manual checklist (owner in game):
  1. Kill a pack → loot one corpse → the window lists the pack's loot (on by default);
     `.aoeloot off` returns single-corpse looting.
  2. In a group: the window respects the group's loot rules; in a party with free-for-all vs
     round-robin, behavior unchanged from normal looting.
  3. Full bags with `MailEnable` off → overflow stays on corpses; nothing is lost.
- Known upstream quirks, kept as shipped (dead `AOELootConfig` struct; the upstream README's
  10-corpses cap does not exist in code — the merge cost is bounded by corpses in range).
- Upstream also recommends the companion config `Rate.Corpse.Decay.Looted = 0.01` (looted
  corpses despawn almost instantly) — deliberately left at default for playtest; revisit with
  the owner if lingering corpses annoy.
