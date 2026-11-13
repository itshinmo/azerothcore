# ADR-012 — Progression rates

- Status: accepted (approved by the repository owner on 2026-11-14)
- Date: 2026-11-14
- Related: [ADR-006](ADR-006-shop-policy.md), [ADR-011](ADR-011-world-data-and-content-verification.md)

## Context

Leveling is the product. The intended experience is players meeting each other in leveling zones and
working through old-world and expansion content, not racing to the level cap.

At the same time, the large WotLK servers surveyed for this decision use a raised default and offer a
slower option, or let players lower the rate themselves:

| Server | WotLK rate | Adjustable |
|--------|-----------|------------|
| TheraWoW | 7x, 10x on weekends | Yes, per account |
| Whitemane | 5x | Yes, in game |
| Wowzone | Not published | Unknown |
| Ascension | Not verifiable; realms closed September 2026 | — |

Only the TheraWoW and Whitemane rows were read from those servers' own documentation. Wowzone
publishes no rate, and Ascension's realms are closed, so those two rows are evidence of silence, not
of a number.

At 1x, reaching level 80 costs roughly 140-180 hours. Old-world content alone is 80-100 hours. That
is a retention bet taken before the content has been verified.

## Decision

1. **Default experience rate is 3x.** Set it for all experience sources, so the pacing is uniform:

   | Setting | Value |
   |---------|-------|
   | `Rate.XP.Kill` | 3 |
   | `Rate.XP.Quest` | 3 |
   | `Rate.XP.Quest.DF` | 3 |
   | `Rate.XP.Explore` | 3 |
   | `Rate.XP.Pet` | 3 |
   | Battleground kills, one key per battleground | 3 |
   | `Rate.XP.BattlegroundBonus` | 3 |

   The battleground keys are `AV`, `WSG`, `AB`, `EOTS`, `SOTA`, and `IC`, each prefixed
   `Rate.XP.BattlegroundKill`.

2. **Everything that is not experience stays at 1x.** Drop rates, money, reputation, talent points,
   skill discovery, and profession gains are unchanged. Rates are a pacing choice, not an economy
   change.
3. **Per-account override is intended.** A player may select a lower rate, including 1x, and 1x is
   advertised as the purist option. Stock AzerothCore has no per-account experience command, so this
   requires a project module or command. The mechanism is an open question; the product intent is
   decided.
4. **Rates are configuration, not code.** The default lives in the server configuration template.
   Changing the default is a policy change that updates this ADR and the template together.
5. **Shop policy is out of scope here.** This ADR sets pacing only. The product list in
   [specs/shop.md](../specs/shop.md) stands until shop work starts; a revision is tracked in
   [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).

## Alternatives considered

- **1x default.** Best zone population, highest retention risk, and it makes every unverified
  low-level quest a quit event. Rejected as the default, kept as an option.
- **5x default.** Closer to Whitemane. Faster to endgame, but leveling content stops being the sell
  and the old world thins out sooner. Rejected.
- **7-10x default.** Turns leveling into a formality, which removes the reason to build a verified
  world. Rejected.

## Consequences

- Expected time to level 80 is roughly 45-60 hours.
- Low-level zones stay relevant long enough to be tested by real players.
- A per-account override needs implementation before it can be promised publicly.
- The configuration template ships 3x in this change. Existing local, test, and production
  configuration files keep their current values until they are regenerated or edited.
