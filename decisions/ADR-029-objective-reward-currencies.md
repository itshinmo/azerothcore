# ADR-029 — Objective reward currencies and spend paths

- Status: proposed
- Date: 2026-11-23
- Implements: owner request for three reward currencies and level-appropriate vendors

## Context

The objective engine needs a reward that feels worth doing without turning into a shop, a
pay-for-power path or a trading market. The owner asked for three currencies with different
scopes, earned by different content, and spent at vendors in Stormwind and Orgrimmar. Gear comes
first, materials second, cosmetics third. The currencies must not be buyable with gold or money,
and the vendors must not sell power that skips progression.

Numbering: ADR-027 is allocated on the client-patch branch; see ADR-028's context note.

## Decision

1. **Three currencies, two scopes.**
   - **Adventure Marks** — account scope. Earned by daily and weekly board tasks and by chronicle
     tasks. Stored in `mod_objectives_account_currency`.
   - **Mythic Coins** — character scope. Earned by dungeon and raid boss tasks, battleground tasks
     and chronicle tasks. Stored in `mod_objectives_character_currency`.
   - **Raider's Commendations** — character scope. Earned by raid boss tasks, battleground
     weeklies and chronicle tasks. Stored in `mod_objectives_character_currency`.
   The task row decides the amounts (`reward_marks`, `reward_coins`, `reward_commendations`). A task
   may award more than one currency.
2. **No pay-for-power.** Currencies are not sold for real money, are not purchasable with gold, are
   not items, are not tradable or mailable, and do not convert into each other. Gold is only spent
   on board rerolls. The reward vendors are gameplay vendors, not the shop in
   [ADR-006](ADR-006-shop-policy.md).
3. **Spend path is server-gated gossip.** Two vendor NPCs, entry `910020` in Stormwind and `910021`
   in Orgrimmar, open a gossip menu built by the module. Each offer row names an existing item, a
   count, a currency, a cost, an era and a level band. The server checks the offer's era, the
   player's level, faction, bag space and currency balance, then deducts the currency with a
   write-through update and stores the item. If the item store fails after the charge, the server
   refunds the currency and persists the refund. There is no client DBC and no custom item cost.
4. **Offer order and content.** The offer table sorts gear first, materials second, cosmetics third.
   First-slice offers are Classic only:
   - gear: Silver Defias Belt, Smite's Reaver, Emberstone Staff, Cruel Barb (levels 10–19);
   - materials: Linen Cloth, Medium Leather, Silk Cloth;
   - cosmetics: Red Ribbon Pet Leash, Tabard of the Scarlet Crusade.
   Gear is level-appropriate catch-up gear from the same content band that earns the currency. It is
   not best-in-slot and it does not skip a raid tier.
5. **Earning rates are data.** First-slice dailies award 15–25 Adventure Marks and 2–5 Mythic Coins;
   weeklies award 50–75 Marks and 10–25 Coins; chronicle tasks add Commendations. The exact values
   live in `mod_objectives_task`, not in code, so the owner can tune them without a rebuild.
6. **Currency is not a token.** It is not an item, so it cannot be lost to a full bag, mailed to an
   alt or traded. Account Marks survive character deletion because they key on `account_id`.

## Alternatives considered

- **Currency as items.** Easy to show in the bag, but tradable, mailable and not account-wide without
  a client DBC. Rejected.
- **Stock vendor UI with `item_extended_cost`.** The 3.3.5 client does not know custom extended-cost
  rows, and `item_extended_cost` has no generic currency field. A client patch would be needed for a
  test slice. Rejected; gossip keeps it server-side.
- **Sell gear for real money or gold.** Contradicts ADR-006 and the no-pay-for-power rule.
- **Only cosmetics.** Safe, but the owner asked for gear first and the vendors need a reason to be
  visited while leveling.
- **Mailbox delivery.** A full bag would lose the purchase or need a refund path. The vendor checks
  bag space first and stores directly.

## Consequences / tradeoffs

- The gossip menu is less pretty than the stock vendor frame and shows at most a short list per
  vendor. Acceptable for the first slice.
- Gear offers are existing items; no new item IDs or client assets are introduced.
- A purchase writes through immediately, so it is not covered by the 20 s batch. This is deliberate:
  a crash must not grant an item without deducting the currency.
- The vendor NPCs are custom creature templates and spawns; the ID registry records them.
- Balance is a playtest knob. The ADR records the caps and the order, not the final economy.

## Performance

- **Expected cost.** Gossip open: one in-memory offer filter (a handful of rows). Purchase: one
  indexed currency update, one bag-space check, one item store. No world query.
- **Hot path.** None. Vendors are opened by a player action, not by combat.
- **Target.** 5–7k online players. Currency balances are cached per online character/account; the
  vendor path does not touch other players.
- **Measurement.** The write-through update is visible in the slow-query log if it regresses; the
  gossip path is measured by the number of offers rendered and the item store result in the module
  log at debug level.

## References

- [specs/rewards.md](../specs/rewards.md)
- [specs/objectives.md](../specs/objectives.md)
- [ADR-006](ADR-006-shop-policy.md) (shop policy; this ADR is gameplay, not shop)
- [ADR-028](ADR-028-objective-engine-board-chronicle.md)
