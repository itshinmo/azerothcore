# Rewards

## Purpose

Define the three objective currencies, how each is earned and spent, and the rule that keeps them out
of pay-for-power.

## Scope

Adventure Marks, Mythic Coins and Raider's Commendations; the two reward vendors; the offer table;
the purchase path. The currencies of other systems (honor, arena points, emblems, gold) are outside
this spec.

## Boundary (owns / does not own / consumes)

- Owns: currency balances, earning rules, spend validation and the vendor offer contract.
- Does not own: item balance, the shop ([ADR-006](../decisions/ADR-006-shop-policy.md)), or the
  objective engine ([objectives.md](objectives.md)).
- Consumes: `mod_objectives_task` reward columns, `mod_objectives_offer` world rows, `item_template`,
  the player's level, faction, bags and gold.

## Contract

### Currencies

| Currency | Scope | Table | Earned by |
|----------|-------|-------|-----------|
| Adventure Marks | account | `mod_objectives_account_currency.adventure_marks` | board dailies/weeklies, chronicle |
| Mythic Coins | character | `mod_objectives_character_currency.mythic_coins` | boss, battleground and chronicle tasks |
| Raider's Commendations | character | `mod_objectives_character_currency.commendations` | raid bosses, battleground weeklies, chronicle |

- Balances are unsigned 32-bit. Additions saturate at `UINT32_MAX` and log a warning; they do not
  wrap.
- Adventure Marks key on `account_id`, so deleting a character does not remove them.
- Mythic Coins and Raider's Commendations key on `guid` and are lost with the character.
- The addon shows all three balances; the board and chronicle headers carry them.

### Earning

- The completed task's `reward_marks`, `reward_coins` and `reward_commendations` are awarded once,
  at completion. There is no claim step and no second payout.
- Currency is written through immediately on award and on purchase. It is a balance, not a batched
  progress row.
- A chronicle task awards Adventure Marks to the account and its character currencies to the
  character that completed it.
- The first-slice data uses 15–25 Marks and 2–5 Coins per daily, 50–75 Marks and 10–25 Coins per
  weekly, and 0–10 Commendations on raid/battleground/chronicle tasks. Values are data, not code.
- Currency is not an item, not mailable, not tradable, not auctionable and not convertible.

### Spending

Two NPCs open the reward menu from a gossip option:

| Entry | City | Faction |
|-------|------|---------|
| `910020` | Stormwind, Trade District | Alliance-friendly, neutral to players |
| `910021` | Orgrimmar, Valley of Strength | Horde-friendly, neutral to players |

- The menu lists offers whose `era <= Objectives.Era`, whose level band contains the player's level
  and whose faction is `0` or the player's faction. The list is server-built; the addon is not
  involved.
- An offer row has `currency`, `cost`, `item_id`, `item_count`, `category`, `min_level`, `max_level`,
  `faction`, `era` and `sort`. `category` is 1 gear, 2 material, 3 cosmetic; the menu sorts by
  category then `sort`.
- The server checks, in order: era, level band, faction, bag space, currency balance. Only then
  does it deduct the currency and store the item.
- The currency update is write-through (`DirectExecute`), not batched, so a crash cannot grant an
  item without the deduction.
- A purchase that fails the bag check changes nothing. There is no mail fallback in this slice.
- If the item store fails after the currency charge (for example a race with another inventory
  change), the server refunds the currency, persists the refund and logs one error line.
- The vendor is a gameplay vendor. It is not reachable with real money, it is not the shop, and it
  does not accept gold.

### First-slice offers

| Category | Item | Currency | Cost | Level |
|----------|------|----------|------|-------|
| Gear | Silver Defias Belt (832) | Marks | 40 | 10+ |
| Gear | Smite's Reaver (5196) | Coins | 25 | 17+ |
| Gear | Emberstone Staff (5201) | Coins | 20 | 18+ |
| Gear | Cruel Barb (5191) | Commendations | 10 | 19+ |
| Material | Linen Cloth (2589) ×20 | Marks | 10 | any |
| Material | Medium Leather (2319) ×10 | Coins | 8 | any |
| Material | Silk Cloth (4306) ×10 | Commendations | 4 | any |
| Cosmetic | Red Ribbon Pet Leash (44820) | Marks | 60 | any |
| Cosmetic | Tabard of the Scarlet Crusade (23192) | Commendations | 15 | any |

The vendor does not sell best-in-slot gear, raid-tier gear, gold, experience, reputation or
profession skill. Gear offers are catch-up items from the same band that earns the currency.

### No pay-for-power

- Currency is earned only by playing the objective engine. It is never sold for money, never
  included in a shop product and never granted by a GM command as a purchase.
- Gold buys only board rerolls. It cannot buy currency, items or progress.
- No currency converts to another currency, to honor or to arena points.
- Players cannot trade the currencies or the vendor items for currency.
- The offer table is the whole spend path; adding a pay-for-power item is a data change that this
  ADR forbids without a new decision.

## Errors and edge cases

- Unknown offer id: refused, no state change.
- Player below the offer's `min_level`: refused with the required level in the message.
- Wrong faction: the offer is hidden.
- Insufficient currency: refused; the menu shows the shortfall in the message.
- Full bags: refused before deduction.
- Missing module tables: the module disables both progress and purchases with one warning.
- Missing `item_template` row: the offer is skipped at startup and never shown.
- Two characters of the same account buying at once: account Marks are read and written under the
  module lock; the second purchase sees the first deduction.

## Security

- The client sends only an offer id. It never sends a price, item id, count or currency balance.
- The server resolves the offer from its cached table and re-checks every constraint.
- The addon has no purchase path; purchases are gossip selections.
- No balances, account names or player names in logs. Debug logs use ids only.
- The vendor NPCs are ordinary world creatures with a script; they do not grant GM permissions.

## Observability

- Startup: one line with the number of loaded offers and the number skipped.
- Purchase: one debug line with offer id, currency id and character id; no balance.
- Refusal: one debug line with the reason code.
- A failed write-through currency update is one error line and the item is not granted.

## Performance

- **Expected cost.** Opening the menu filters a cached list (single-digit offers in the first
  slice). A purchase is one indexed update, one bag check and one item store. No world query.
- **Hot path.** None; purchases are player actions.
- **Target.** 5–7k online players. Balances are cached per online character/account; the vendor
  path touches only the buyer.
- **Measurement.** Slow-query log for the currency update; item-store failures in the module debug
  log; a playtest purchase on each vendor.

## References

- [ADR-029](../decisions/ADR-029-objective-reward-currencies.md)
- [ADR-006](../decisions/ADR-006-shop-policy.md)
- [specs/objectives.md](objectives.md)
- `modules/mod-objectives/`, `data/sql/custom/db_world/objectives_engine.sql`
