# ADR-034 — Mythic+ for old content: dungeons first, scaled items, no P2W

- Status: proposed
- Date: 2026-11-23
- Related: [RFC-004](../rfcs/active/RFC-004-mythic-plus.md), §Contract (proposed)
- Contract status: RFC-004 only. No `specs/mythic-plus.md` exists until the owner accepts this ADR.
- Recommendation status: values marked **recommended, pending owner** are proposals, not decisions.
  They are tracked in [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) and stay open until the owner answers.

## Context

At level 80 the Classic and TBC five-player dungeons are trivial. Their loot is below the level-80
budget, so players have no reason to run them. The owner wants an old-content Mythic+ ladder that
reuses those instances, scales their loot to level 80, and gives a long-tail gearing path without
selling power.

The candidate module `silviu20092/mod-mythic-plus` (MIT) already implements a keystone, affixes, a
timer, group restrictions and run tracking. It does **not** implement scaled loot, a currency, a
vendor, a weekly chest, recycling, per-era progression, or raid support. Its old-content data covers
only Ragefire Chasm and Razorfen Kraul, and its Ragefire Chasm final boss row points at Bazzalan
(11519), not Taragaman the Hungerer (11520). A full audit is in RFC-004.

Two constraints shape the decision:

1. **No runtime item stat mutation.** AzerothCore item templates are shared world data. Changing an
   item's stats at runtime would change every copy of that item for every player, and would make
   loot, mail, auctions and the database disagree.
2. **New item IDs need a client `Item.dbc` row. Confirmed.** A server-only `item_template` row with
   no `Item.dbc` entry shows a red question mark in the bag. Use QA-block item `1900001` for the
   formal probe; the earlier `2050641` collides with the transmog preview copy at
   `50641 + 2000000`, so it is not a safe probe. The transmog preview model still worked because
   `TryOn` uses the server display ID, so that path is separate. Scaled Mythic+ item IDs therefore
   need a generated `Item.dbc` row and a data-only client patch delivered through the accepted
   ADR-027 pipeline: the feature publishes `data/client-patches/item-data/` (`items.json`,
   `source/*.csv`, `generate_items.py`, the whole-file `Item.dbc` and `manifest.json`), and that
   pipeline owns the source-DBC merge and MPQ packaging. No executable client change is needed.

## Decision

1. **Dungeons first.** v1 covers five-player dungeons from all three eras; solo/1–5 versus a
   strict five-player group is **recommended, pending owner**. Raids are out of scope
   until a separate ADR accepts a raid model: raid lockouts, 10/25 difficulties, multi-boss
   completion and raid loot tables do not fit the dungeon model.
2. **Per-era ladders, dungeon ceiling 232.** Each dungeon has an era: Classic, TBC or WotLK. Keys
   run 1–20. The item-level anchors are Classic M10 = 187 (normal WotLK dungeon level), TBC M10 = 200
   (WotLK heroic dungeon level), WotLK M1 = 187 and M10 = 219 (heroic five-player ceiling). The
   WotLK M1 re-anchor avoids compressing 19 keys into 32 item levels; the per-dungeon 200 floor
   handles ToC, FoS, PoS and HoR, and an upgrade whose item level does not change is refused. All
   dungeon ladders stop at 232 (Trial of the Crusader 10 normal) at M20. 232 does not obsolete
   ToC 25 / ICC loot, but it exceeds Naxxramas 25 (213) and Ulduar normal (219/226) and equals ToC
   10 normal. 284 remains the global cap for future raid ladders. The 232 dungeon ceiling is
   **recommended, pending owner** (accept 232, or choose 245/284). The exact table is in RFC-004
   §Contract (proposed).
3. **Pre-generated scaled copies.** For every source item and key level, the build generates a new
   `item_template` row with scaled armor, weapon damage and stats. Stats aim for **budget parity, not
   power parity**: a target item-level budget derived from native items, not a raw ratio. Items whose
   budget is dominated by dead stats, an unscaled proc or on-use effect, or a set bonus are excluded
   or flagged and are not claimed to be equivalent to a native item. The module never mutates item
   stats at runtime. Generated copies keep the source item's name (plus a key suffix), display,
   class, subclass, inventory type, sheath and quality. They are bind-on-pickup, have no random
   suffix or random property, have `RequiredLevel = 80` and `ItemLevel` equal to the effective
   target (ladder value or the per-dungeon floor, whichever is higher). `Flags` keeps the allowlisted
   `ITEM_FLAG_UNIQUE_EQUIPPABLE`, `ITEM_FLAG_NOT_USEABLE_IN_ARENA`, `ITEM_FLAG_NO_DURABILITY_LOSS`
   and `ITEM_FLAG_USE_WHEN_SHAPESHIFTED` bits; `FlagsExtra` keeps only the Horde/Alliance bits; `AllowableClass`,
   `AllowableRace`, `RequiredSkill`, `RequiredSkillRank`, `ArmorDamageModifier`, `RangedModRange`,
   `ammo_type` and `flagsCustom` are preserved. Legendary items are excluded. A set ID is kept only
   when every piece of that set is in the same era pool and the set is curated as allowed.
4. **New item ID ranges.** Obtainable generated copies use `1100000–1899999`; the block starts above
   registered creature `1000003` and npc_text `1000004`. Non-obtainable and QA copies use
   `1900000–1999999` and never appear in loot, a vendor or the weekly vault. Preview items keep
   `2000000–2999999`; that range is real on `local-server-setup` (ADR-026 revision,
   `transmog_preview_items.sql`), and this branch base predates that merge. A preview copy is
   `2000000 + source_entry`, so a seven-digit source lands above that block; reserve
   `3000000–3999999` for previews of source entries `1000000+` and make the transmog generator
   refuse any id outside the two preview blocks. Today every preview source is below 1,000,000,
   which is the only reason `2000000–2999999` still holds; a Mythic+ source in `1100000–1899999`
   would otherwise produce a preview at `3100000–3899999`. Generated rows are
   immutable and soft-retired (`active = 0`), never deleted, because a player may still own one. The
   registry records all four ranges as proposed; acceptance must update `AGENTS.md` custom-content
   reserved ranges. The generator owns a committed manifest so IDs are stable across regeneration.
5. **Loot sources.** On an active run, dungeon bosses drop scaled copies through the existing loot
   tables; a Mythic+ capable map with no active run is unchanged. The final boss additionally grants
   one personal scaled item. A weekly vault grants one item at the week's best effective reward,
   ranked by `max(ladder, min_item_level)`, then key, then earliest completion.
   A currency vendor sells a deterministic weekly stock from quartermaster creature `910013`.
   Players can upgrade an owned scaled item up to their highest completed key (`highest_key` in §7)
   and recycle a scaled item for coins. Command permissions are `950160`–`950163` (info, start,
   abandon, admin status/reload).
6. **Mythic Coins.** Coins are a per-character database balance (**recommended, pending owner**;
   account-wide is the alternative), not a tradeable item. They are
   earned only from boss kills, final-boss kills and timed completions. There is no cap, no
   real-money purchase, no gold-to-coin conversion, no auction-house listing and no player trade.
7. **Progression is earned, no carries.** Each character has a highest **completed** key per era.
   A group leader or solo player can start any dungeon in that era at a key up to
   `highest_key + 1`, and every member must satisfy that ceiling at start. A timed completion sets
   `highest_key = max(highest_key, key)`, so the next startable key becomes `highest_key + 1`; a
   completion never skips a key, because the ceiling only advances one past the highest key
   finished. Progression scope (per character versus account-wide) is **recommended, pending
   owner**.
   A failed timer gives no unlock and no final-boss personal item, but still counts as a completion
   for the weekly vault. Eligibility requires being in `member_guids` at start, never leaving the
   instance, and being present at the final boss; late joiners and leave/rejoin get no unlock, coins
   or vault credit. There is no physical keystone item in v1; starting the run inside the instance
   avoids a custom item, a buy timer and keystone trading.
8. **No P2W.** No power is sold for money. The shop policy in ADR-006 is unchanged. Carries are not
   allowed: the start check enforces each member's key ceiling, and eligibility is fixed at start.
9. **Compatibility.** AutoBalance and Mythic+ must not scale the same creature. Refusing to start
   while AutoBalance is on is **recommended, pending owner** (the alternative is disabling
   AutoBalance on Mythic+ capable maps). If the AutoBalance module is
   installed, read its module key `AutoBalance.Enable.Global` (not a core key in this repo) and
   refuse when it is on; if the module is absent, skip the check. One module owns the scale.
10. **Module disposition.** Do not vendor the candidate unchanged. Fork it at commit `e2a487d`
    (MIT), keep its licence and attribution, and refactor it in slices. The audit and the exact
    gaps are in RFC-004. No module code is written until the owner accepts this ADR and the RFC
    contract.
11. **Client boundary.** No new maps, models, icons or spells. v1 reuses existing assets. Scaled item
    IDs require a generated `Item.dbc` row; a server-only probe shows a red question mark without
    one. QA-block item `1900001` is the formal probe; `2050641` collides with the transmog preview
    copy. The client patch is data-only; ADR-027's pipeline owns the source-DBC merge and MPQ
    packaging. The transmog preview/TryOn path is separate: it works from the server display ID and
    is not evidence that bag entries work. The first slice must include one custom item in a bag,
    not only a TryOn sample.

## Alternatives considered

- **Vendor the module unchanged and add a companion loot module.** Rejected: two modules would own
  the same instance state, the candidate still writes per death and per boss per player, and its
  standings reload the whole table every ten minutes. The companion would have to patch around the
  same problems the fork can fix once.
- **Rewrite from scratch.** Rejected for v1: the timer, affix interface, gossip skeleton and run
  state are usable. A rewrite spends the budget on plumbing rather than on the loot and economy the
  feature actually needs.
- **Runtime item stat scaling.** Rejected: shared templates, cache inconsistency, and every copy of
  an item would change for every player.
- **Reuse existing item IDs only.** Rejected: one ID cannot hold twenty different key levels, and
  repurposing unused client IDs does not provide enough entries. It remains the fallback only if no
  client data patch is allowed at all.
- **Raids first.** Rejected: raid lockouts, 10/25 difficulties, multi-boss completion and raid loot
  need their own contract. Dungeons prove the model first.
- **Sell keys or gear for money.** Rejected by the no-P2W rule and ADR-006.

## Consequences

- The world database gains roughly 60,000–100,000 generated item rows plus a mapping table. This is
  loaded once, not a per-tick cost. Memory is not claimed: slice 1 measures the module map, the
  `ItemTemplate` cache and `sItemStore` separately.
- Scaled item IDs require a data-only `Item.dbc` patch, delivered through the accepted ADR-027
  item-data pipeline. The preview/TryOn path is separate and already works from the server display ID.
- Loot replacement is one hash lookup per loot item on an **active run**, not merely a Mythic+ map.
  No per-kill database writes and no per-tick creature scans are allowed.
- Raids, seasonal affixes, account-wide progression and a web leaderboard are deferred. Each needs
  its own decision.
- The fork carries an upstream maintenance cost. The licence permits it; the attribution rule
  applies to the vendored commit.

## References

- [RFC-004 §Contract (proposed)](../rfcs/active/RFC-004-mythic-plus.md#contract-proposed)
- [ADR-002 — custom content isolation and IDs](ADR-002-custom-content-isolation-and-ids.md)
- [ADR-006 — shop policy](ADR-006-shop-policy.md)
- [ADR-009 — RBAC command permission precedence](ADR-009-rbac-command-permission-precedence.md)
- [runbook/database/id-registry.md](../runbook/database/id-registry.md)
- Candidate module: <https://github.com/silviu20092/mod-mythic-plus> (MIT), commit `e2a487d`
