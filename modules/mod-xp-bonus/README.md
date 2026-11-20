# mod-xp-bonus

Small-balance XP bonus sources (ADR-012 revision 2026-11-20, RFC-003 Group A): gathering,
rare kills and battleground wins award a small base experience that passes through the
server's global rate (`Rate.XP.Kill`, 2x per ADR-012), making non-quest leveling paths viable.

| Source | Base | Anti-abuse |
|--------|------|------------|
| Rare / rare-elite kill | `XpBonus.RareKill.PerLevel` x level (100) | none — rares are naturally scarce; world bosses excluded |
| Gathering (herb/mine nodes, skinnable corpses) | `XpBonus.Gathering.PerLevel` x level (15) | `XpBonus.Gathering.DailyNodeCap` gathers/day (200), in-memory, resets on restart |
| Battleground win | `XpBonus.BgWin.PerLevel` x level (75) | none — matches are self-limiting; arena matches, losers and aborted BGs get nothing |

Values are deliberately small (the owner's small-balance rule) and tuned at playtest — the
config keys are the tuning knobs, changing them needs no recompile.

Implementation notes:

- Every award routes through the core XP hook (`OnPlayerGiveXP`) before `GiveXP`, so
  Ancestral Wisdom (mod-ancestral-wisdom) stacks with these sources, per the owner's
  2026-11-20 decision that Wisdom applies to all XP.
- Rare kills use the `OnPlayerRewardKillRewarder` hook, which fires per credited player
  (killer plus group members at reward distance, pet owners included) — group kill parity
  with the normal kill XP.
- The gathering gates mirror the core's own checks (`CanOpenLock` for herb/mine node locks,
  the skinning block of `CheckCast` for skinnable corpses): triggered casts bypass the core's
  CheckCast, so the mirror keeps the bonus gated on the required skill in every path. A node
  taken by another player mid-cast remains a possible small overcount, bounded by the daily cap.
- Gathering passes no victim to `GiveXP`, so rested experience does not double-dip on it;
  rare kills pass the victim, so they behave exactly like a normal kill.
- Winner detection uses the player's battleground team id against the winner team id; the
  hook runs per player at battleground end.
