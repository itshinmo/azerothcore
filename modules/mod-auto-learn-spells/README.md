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
  trainers (class mounts, druid flight forms) are taught the way the trainer itself
  teaches them — by casting the wrapper, which keeps their own gating (Riding skill
  for class mounts and flight forms) and their bundled side effects.
- Shamans additionally receive their four totem items (Earth/Fire/Water/Air Totem,
  5175-5178) on login when missing: the totem spells carry a `TotemCategory`
  requirement checked against the bags, and retail grants these items via the
  level 4/10/20/30 class quests. Only shamans have such item-gated abilities in the
  trainer data (checked across all classes).

Config: none. To disable the behavior, exclude the module via
`-DDISABLED_AC_MODULES=mod-auto-learn-spells` (see `modules/how_to_make_a_module.md`).

Deliberately not vendored from `azerothcore/mod-learn-spells`: that module is a
heuristic spell-family scan with a hand-maintained ignore list whose own issue
tracker reports bugged/invalid spell learns (#50, #56 open as of 2026-11-20).
