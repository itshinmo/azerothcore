# mod-ancestral-wisdom

Whitemane-style alt bonus, owner-reduced (ADR-012 revision 2026-11-20, RFC-003 Group A):
characters gain **+10% experience per max-level character on their account**, experience only
(no reputation — the owner decision names XP; adding reputation later is its own decision).

- Multiplies base experience in the core's `OnPlayerGiveXP` hook, before rested and
  recruit-a-friend bonuses, so it stacks with them. Covers every XP source the core has
  (kill, quest, quest-DF, explore, battleground).
- Count per account: refreshed at each login and when a cached character reaches the level
  cap. A character deleted mid-session counts until its owner logs in again.
- Config: `AncestralWisdom.PercentPerChar` (default 10), `AncestralWisdom.MaxBonusPercent`
  (default 0 = uncapped, per the owner decision; the cap is an anti-abuse knob).
