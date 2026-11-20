# ADR-021 — Leveling QoL batch 1 (auto-learn class spells, cheap dual spec)

- Status: accepted
- Date: 2026-11-20
- Implements: [RFC-003](../rfcs/active/RFC-003-qol-social-slate.md) Group A (owner decisions of 2026-11-20)

## Decision

1. **Auto-learn class spells** — new local module `modules/mod-auto-learn-spells`
   (PlayerScript on `OnPlayerLogin` + `OnPlayerLevelChanged`): every spell the player's
   class trainers would sell at the current level is learned automatically, free, Cataclysm-style.
   The learned set is driven by the server's `trainer`/`trainer_spell` data through the core
   `Trainer` availability filter (`Trainer::CanTeachSpell`), the exact logic the trainer UI uses,
   so there is no hand-maintained spell list. Mount, pet and tradeskill trainers are untouched;
   talents stay talent-point purchases; the trainer NPC UI stays as-is (players may still use it).
   Every login doubles as a cheap catch-up pass for pre-existing characters (known spells are
   skipped by the filter). LEARN_SPELL wrapper entries (class mounts, druid flight forms) stay
   normal trainer visits: they are cast, not learned, and their side effects (Riding skill steps)
   belong to the trainer.
   No config: disabling goes through `DISABLED_AC_MODULES`.
   Deliberately not vendored from `azerothcore/mod-learn-spells`: that module is a heuristic
   spell-family scan with a hand-maintained ignore list whose own tracker reports bugged/invalid
   learns (issues #50, #56, open 2026-11-20); our filter reuses core-owned data instead.
2. **Dual spec at level 30, free** (owner decision 2026-11-20): `MinDualSpecLevel = 30` in
   `worldserver.conf.dist` (fork default) and the live `env/dist/etc/worldserver.conf`. Verified
   before deciding: this core's dual-spec learn (trainer gossip casting spells 63680/63624) and
   spec switching cost nothing, so "cheap" is satisfied on cost and the level gate is the only knob.
   Retail parity minus the 10 gold.
3. **Auto flight paths dropped** (owner decision 2026-11-20, amending RFC-003 Group A): players
   must discover flight paths. The core `AllFlightPaths` config stays off (upstream default).
   If this ever returns, the config is the zero-code path and should be revisited then.

## Tests and verification

- `make build` compiles the module into the worldserver; no SQL, no config schema changes.
- Unit tests: none — the module is a thin loop over core-owned data and the core-owned
  availability filter; the meaningful checks are behavioral (T3 below).
- T3 manual checklist (owner in game):
  1. A character below 30 levels up → new class spells appear without visiting a trainer
     (spot-check a rank gained at that level; the spellbook shows it).
  2. A pre-existing character logs in once after the module lands → catch-up learns any
     trainer spells its level allows but it had not bought (the login pass).
  3. Level 30 character talks to a class trainer → "Learn dual spec" offered; learning and
     switching cost nothing; a level-29 character is not offered it.
  4. Spell ranks respect prerequisites (e.g. no rank-3 without rank-2) — automatic, since the
     filter is the trainer UI's, but spot-check one chain.
  5. Wrapper-taught spells still need the trainer visit: a druid's Flight Form and a warlock's
     Felsteed are not auto-learned (they are cast by the trainer and carry side effects).
- Failure mode to watch: a spell missing from `trainer_spell` for a class trainer is simply
  never auto-learned — same spell stays purchasable from the trainer, so gaps surface as
  normal trainer visits, not as broken characters.
