# ADR-012 — Progression rates

- Status: accepted (approved by the repository owner on 2026-11-14); revised 2026-11-16 — default
  lowered to 2x and the per-account override removed (approved by the repository owner on
  2026-11-16); revised 2026-11-20 — small-balance bonus XP sources and Ancestral Wisdom added
  (approved by the repository owner on 2026-11-20, [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md) Group A)
- Date: 2026-11-14, revised 2026-11-16, revised 2026-11-20
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

1. **Default experience rate is 2x.** Set it for all experience sources, so the pacing is uniform:

   | Setting | Value |
   |---------|-------|
   | `Rate.XP.Kill` | 2 |
   | `Rate.XP.Quest` | 2 |
   | `Rate.XP.Quest.DF` | 2 |
   | `Rate.XP.Explore` | 2 |
   | `Rate.XP.Pet` | 2 |
   | Battleground kills, one key per battleground | 2 |
   | `Rate.XP.BattlegroundBonus` | 2 |

   The battleground keys are `AV`, `WSG`, `AB`, `EOTS`, `SOTA`, and `IC`, each prefixed
   `Rate.XP.BattlegroundKill`.

2. **Everything that is not experience stays at 1x.** Drop rates, money, reputation, talent points,
   skill discovery, and profession gains are unchanged. Rates are a pacing choice, not an economy
   change.
3. **All players share the same rates.** There is no per-account override. An earlier
   implementation (`modules/mod-xp-override`, `.xp` command, `account_xp_override` table) was
   removed on 2026-11-16 before public launch: every player must see the same pacing, and a
   self-service rate command undercuts that.
4. **Future rule-set rates are an idea, not a decision.** Per-rule-set pacing (for example, a
   hardcore rule-set locked at 1x, applied automatically from membership, with no player command)
   is Phase 2 scope. It needs its own ADR before any implementation.
5. **Rates are configuration, not code.** The default lives in the server configuration template.
   Changing the default is a policy change that updates this ADR and the template together.
6. **Shop policy is out of scope here.** This ADR sets pacing only. The product list in
   [specs/shop.md](../specs/shop.md) stands until shop work starts; a revision is tracked in
   [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).

## Alternatives considered

- **1x default.** Best zone population, highest retention risk, and it makes every unverified
  low-level quest a quit event. Rejected as the default; revisit only as a Phase 2 rule-set rate.
- **5x default.** Closer to Whitemane. Faster to endgame, but leveling content stops being the sell
  and the old world thins out sooner. Rejected.
- **7-10x default.** Turns leveling into a formality, which removes the reason to build a verified
  world. Rejected.

## Consequences

- At 2x, reaching level 80 takes roughly 70-90 hours; low-level zones stay populated.
- Low-level zones stay relevant long enough to be tested by real players.
- The configuration template ships 2x. Existing local, test, and production configuration files
  keep their current values until they are regenerated or edited; check them after pulling.

## Revision 2026-11-20 — bonus XP sources and Ancestral Wisdom

The owner amended this ADR with RFC-003 Group A's XP items under the **small-balance rule**: bonus
XP sources award a small base experience that passes through the global rate above, so at the 2x
default they stay leveling accelerators, never the fastest path. Target feel: slow but not too slow.

1. **Bonus XP sources** (`modules/mod-xp-bonus`), bases x player level, each multiplied by
   `Rate.XP.Kill` (the global rate, 2x at default). Every award routes through the core XP hook
   before `GiveXP`, so Ancestral Wisdom stacks with these sources too (owner decision
   2026-11-20: Wisdom applies to all XP):

   | Source | Base config | Default | Anti-abuse |
   |--------|-------------|---------|------------|
   | Rare / rare-elite kill | `XpBonus.RareKill.PerLevel` | 100 | none needed — rares are scarce; world bosses excluded; paid per credited player (group + pet owners), like normal kill XP |
   | Gathering (herb/mine nodes, skinnable corpses) | `XpBonus.Gathering.PerLevel` | 15 | `XpBonus.Gathering.DailyNodeCap` = 200 gathers/day per character |
   | Battleground win | `XpBonus.BgWin.PerLevel` | 75 | none needed — arena matches, losers and aborted BGs get nothing |

   The gathering award happens at cast time; the core's own CheckCast normally vets the cast
   first, but directly triggered casts skip CheckCast entirely, so the module mirrors the core's
   skill gates (`CanOpenLock` for node locks, the skinning block of `CheckCast` for corpses) — no
   path can earn XP without the required skill. A node taken mid-cast stays a possible small
   overcount, bounded by the cap.
   The gathering cap counter is in-memory and resets on server restart; a documented limit — if
   playtest shows abuse, upgrade it to a persisted counter (own change, revises this ADR again).
   All values are playtest-tuning knobs in `XpBonus.conf.dist`; changing them is configuration,
   not policy.
2. **Ancestral Wisdom** (`modules/mod-ancestral-wisdom`): **+10% experience per max-level
   character on the account**, owner-reduced from Whitemane's +15%, and experience only —
   Whitemane's reputation component is not adopted (owner decision names XP; adopting reputation
   later is its own decision). Multiplies base XP before rested/recruit-a-friend, so it stacks,
   and it applies to every XP source including the bonus sources above (owner decision
   2026-11-20: "all XP").
   `AncestralWisdom.PercentPerChar` = 10, `AncestralWisdom.MaxBonusPercent` = 0 (uncapped per the
   owner decision; the cap is an anti-abuse knob). The account-wide collection tab (RFC-002 /
   ADR-020) is the visible counterpart.
3. **Not affected:** the 2x default, the no-per-account-override rule, and the everything-else-at-1x
   rule stand unchanged. Riding training and the first mount are out of scope by owner decision
   (RFC-003 amendment; the "free mount at 20" item was removed before implementation).

## Revision 2026-11-20 (2) — dungeon XP split

Same owner decision session as the revision above (RFC-003 Group A wrap-up): with the rate
analysis showing repeat dungeon clears at roughly ~260k XP/h — competitive with world questing
(~300k/h) — dungeon spam was the obvious "blast to 80" path. Adopted the retail/Wow-Forever split
(`modules/mod-dungeon-xp`, owner picked "decrease the mob rate more than half"):

1. **Dungeon mob XP reduced:** `DungeonXp.KillFactor = 0.33` — kill XP (mob + boss) inside
   instance maps is a third of normal, putting repeat clears at roughly ~85k XP/h. The gate is
   `Map::IsDungeon()` (instances + raids, `DungeonXp.IncludeRaids`); battleground kills keep
   their per-BG rates, outdoor elites and rares keep full rate.
2. **Dungeon quest XP raised:** `DungeonXp.QuestFactor = 2.0` on top of the global rate —
   dungeon quests pay 4x, one-time per character. Detection is data-driven (quest zone ->
   area -> instance map); quests with no dungeon zone fail open to the world rate. First visit
   through a dungeon now pays more than a repeat ever did.
3. **Intent:** dungeons are story events with loot, not repeatable XP farms; world content stays
   the leveling backbone. Both factors are playtest knobs, configuration not policy (same rule as
   the sources above); the 0.33 depth is the owner's call and tunable in the conf without a
   rebuild.
