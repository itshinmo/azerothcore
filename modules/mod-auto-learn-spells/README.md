# mod-auto-learn-spells

Teaches class trainer spells automatically when their level requirement is met
(Cataclysm-style), instead of requiring a trainer visit. Local module for this fork
(RFC-003 Group A; see `decisions/ADR-021-leveling-qol-batch-1.md`).

- Learn set = everything the player's class trainers would sell at the current
  level: driven by the server's `trainer`/`trainer_spell` data through the core
  `Trainer` availability filter (level, skill, ability, rank-chain requirements).
  No hand-maintained spell list, nothing to drift out of sync.
- Runs on every login (cheap catch-up: known spells are skipped; closes the gap for
  pre-existing characters) and on every level-up. Learning is free; the trainer UI is
  unchanged.
- Class spells only: mount, pet and tradeskill trainers are not touched, and
  talents stay talent-point purchases. LEARN_SPELL wrapper entries taught by class
  trainers (class mounts, druid flight forms) stay normal trainer visits: they are
  cast, not learned, and their side effects (Riding skill steps) belong to the trainer.

Config: none. To disable the behavior, exclude the module via
`-DDISABLED_AC_MODULES=mod-auto-learn-spells` (see `modules/how_to_make_a_module.md`).

Deliberately not vendored from `azerothcore/mod-learn-spells`: that module is a
heuristic spell-family scan with a hand-maintained ignore list whose own issue
tracker reports bugged/invalid spell learns (#50, #56 open as of 2026-11-20).
