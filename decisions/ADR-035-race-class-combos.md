# ADR-035: Extended race/class combinations

- Status: proposed
- Date: 2026-11-23
- Related: [ADR-002](ADR-002-custom-content-isolation-and-ids.md),
  [ADR-013](ADR-013-server-and-client-before-website.md),
  [ADR-020](ADR-020-collections-transmog-stack.md),
  [ADR-026](ADR-026-transmog-npc-only-and-preview.md),
  [RFC-007](../rfcs/active/RFC-007-race-class-combos.md)
- Open owner decisions: [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) — canonical target list, first batch
  scope, Gnome Priest racials, Troll Warlock quest shape, `patch-V` carrier approval

## Context

Project Ascension's Bronzebeard realm unlocks race/class pairs that 3.3.5 does not allow. The
proposed target and the recommended first batch are recorded in
[OPEN-QUESTIONS.md](OPEN-QUESTIONS.md); they are not owner decisions and this ADR does not adopt them.
This ADR records only the technical direction that applies once the owner approves a list.

The 3.3.5 client gates character creation with `CharBaseInfo.dbc` (RaceID, ClassID). The server does
not read that DBC. Its gate is `playercreateinfo`; `Player::Create` refuses a pair with no
`PlayerInfo` row. A pair therefore needs **both** a client DBC row and a server row, and they must
ship together.

The installed `CharBaseInfo.dbc` is supplied by `Data/enUS/locale-enUS.MPQ`: 62 rows, 145 bytes. Stock
3.3.5a has 61 rows; the extra row is `(8, 8)` Troll Mage. The source is an Ascension-modified locale
archive, not a clean stock client. It is still the effective source and is the basis for the patch.

The Ascension character-customization pack (`patch-A.MPQ`) is not a class-combo pack. It replaces
eight customization DBCs. The assets the deferred pairs need are not present: there are no Troll
druid form models, and there is no Ascension undead paladin charger wiring.

## Decision

1. **Target is proposed, not adopted.** The twelve-pair target and the recommended five-pair first
   batch are open owner decisions tracked in [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md). This ADR does
   not claim the owner approved either.
2. **Two gates, one release.** A `CharBaseInfo.dbc` row is added only in the same release as the
   matching `playercreateinfo` row. The client patch is a late-loading whole-file MPQ; the server
   data is re-applicable custom SQL.
3. **Reuse client assets.** Do not extract or redistribute Ascension custom models, textures, forms,
   mounts, or totems. The client change is the character-creation DBC set, built from the effective
   installed archive.
4. **Technical gate for a pair.** A pair is eligible only when the client assets (models, forms,
   mounts, totems, animations), a reachable class trainer, the starting outfit/action bar, weapon
   skills, and the class quest chain exist or are filled by the batch. Pairs that fail the gate stay
   out regardless of the target list.
5. **Client patch carrier.** Character-creation DBCs have no slot in the `patch-X/Y/Z` family defined
   by the client-patch branch's ADR-027; that branch is not merged here. RFC-007 proposes a new
   late-loading `patch-V` carrying `CharBaseInfo.dbc` and, because the creation preview may read it,
   `CharStartOutfit.dbc`. The client-patch owner must approve the carrier before the patch ships.
6. **Whole-file DBC replacement.** Both DBCs ship whole, based on their effective installed source.
   The build recipe is [runbook/development/client-dbc-patch.md](../runbook/development/client-dbc-patch.md);
   the artifact and manifest are in
   [data/client-patches/race-class-combos/](../data/client-patches/race-class-combos/README.md).
   Never ship a row fragment.
7. **Server DBC consistency.** `CharStartOutfit.dbc` is deployed to `DataDir/dbc` with the same bytes
   as the client patch, so the server starting kit and the client preview cannot drift.
   `CharBaseInfo.dbc` remains client-only.
8. **Minimal class-progression fixes.** The recommended batch needs only the Blood Elf Warrior
   weapon-skill rows and the Troll eligibility update for the Orc Voidwalker chain. No new creatures,
   items, spells, or quests are part of the technical direction.
9. **Reserved DBC override IDs.** `CharStartOutfit.dbc` rows use `950400-950407`;
   `skillraceclassinfo_dbc` rows use `950410-950413`. No other custom IDs are used.
10. **Verification gate.** A batch is accepted only after the client and server row sets match, each
    pair creates and spawns, the starting kit and trainer work, one class-specific ability works, the
    creation preview is checked, and the logs are clean.

## Alternatives considered

- **Client patch only.** The class button appears, but the server has no `PlayerInfo` and refuses
  creation. Rejected.
- **Server data only.** The client hides the class button; players cannot reach the pair through the
  supported UI. Rejected.
- **Ship the whole proposed list at once.** Druid forms, paladin mounts, shaman totems, and hunter pet
  quests are not ready; shipping them would produce visibly incomplete characters. Rejected.
- **Extract Ascension assets.** The Ascension pack is third-party and does not contain the needed
  class forms or mounts; licensing and the missing client-patch pipeline block it. Rejected.
- **Reuse the stock `CharacterCreate.lua.extracted` as evidence.** It is not the file the bundle
  runs; the measured winner is `patch-I.mpq`. Rejected.
- **New races or classes.** Out of scope; this decision only unlocks existing race/class pairs.

## Consequences

- The owner must answer the open list/batch questions before any client patch or SQL is applied.
- Once a pair is approved, the client patch is mandatory for creating it. A stock client can still
  play existing characters, but cannot create a new pair.
- `CharBaseInfo.dbc` is based on 62 effective rows, not a clean stock 61; the patch keeps the
  pre-existing Troll Mage row.
- `CharStartOutfit.dbc` is patched in both client and server DataDir; the server
  `charstartoutfit_dbc` table stays empty. If a deployment cannot replace DataDir, the DB override is
  a fallback, but the client preview still needs the DBC.
- Pairs that need missing forms, mounts, totems, or quest chains stay out until those are built; the
  technical gate, not an owner decision, decides eligibility.
- Blood Elf Warrior still depends on the server-side `SkillRaceClassInfo` rows for swords, axes,
  two-handed axes, and daggers. If the client skill UI also needs the rows, they join the client
  patch.
- Balance changes are limited to the new racial/class synergies; no spell or talent tuning is part of
  this decision.

## References

- [RFC-007](../rfcs/active/RFC-007-race-class-combos.md) (durable contract and evidence)
- [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) (owner decisions)
- [specs/content-pipeline.md](../specs/content-pipeline.md)
- [runbook/development/client-dbc-patch.md](../runbook/development/client-dbc-patch.md)
- [runbook/database/id-registry.md](../runbook/database/id-registry.md)
- [runbook/operation/client-bundle.md](../runbook/operation/client-bundle.md)
- [decisions/ADR-002](ADR-002-custom-content-isolation-and-ids.md)
- [decisions/ADR-013](ADR-013-server-and-client-before-website.md)
- `feat/map-poi`: `decisions/ADR-027-client-patch-pipeline.md` (parallel branch, not merged here)
