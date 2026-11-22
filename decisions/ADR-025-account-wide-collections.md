# ADR-025 — Account-wide collections

- Status: accepted
- Date: 2026-11-22
- Supersedes: the toys-per-character decision in [ADR-020](ADR-020-collections-transmog-stack.md) §3
- Implements: owner decision of 2026-11-22, from a playtest report

## Context

Mounts, pets and toys were character-scoped. `mod-account-bound` copied mount and pet spell rows
between sibling characters and gated mounts on riding and class. A playtest found four faults: an alt
saw none of the account's mounts, deleting the character that earned a mount destroyed it for the
account, a bought toy stayed "Not collected" until the journal asked again, and the Mounts tab could
not be used at all. The owner's reference is retail 7.2.5: the collection is the account's, every
entry is visible, and only use is restricted.

## Decision

1. A mount, pet or toy is owned by the **account**, not by a character.
2. Durable records live in `acore_characters`: `mod_forever_journal_account_mounts`,
   `mod_forever_journal_account_pets`, `mod_forever_journal_account_toys`. Mounts and pets key on the
   spell; toys key on the item. Nothing removes a row.
3. Delivery is `character_spell`. Every character of the account gets the collected spell at
   creation, at login, and when any sibling learns it. The 3.3.5 client builds its companion list
   from known spells, so that is the whole delivery path; no custom UI channel is involved. A
   sibling that is online when another learns it gets the `character_spell` row immediately but
   sees it on its next login; only the learning character gets a live spell packet.
4. The collection does **not** gate on class. Every collected mount and pet is learned and listed.
   Riding and faction gate **use**: the journal shows the requirement on the card, and the server
   refuses the cast. Class mounts are ordinary mounts for this rule; their riding rank comes from
   the spell's level tier, because their spells carry no required skill and they have no teaching
   item: Felsteed 75, Summon Warhorse 75, Dreadsteed 150, Charger 150, Acherus Deathcharger 150.
5. A mount or pet is recorded when it is learned, and a toy when its item enters the inventory — not
   when the addon next requests state.
6. Characters that already knew mounts or pets are backfilled at login.
7. `mod-account-bound` mounts and pets are OFF. It keeps titles and friends. One module owns each
   data set; two writers to `character_spell` is a defect generator.

## Alternatives considered

- Keep `mod-account-bound` and relax its gates: no durable record remains, so deleting the earning
  character still destroys the collection.
- A collection UI that does not learn spells: the 3.3.5 client lists companions from known spells,
  and a spell it does not know cannot be summoned or dragged to an action bar.
- Grant only class- and faction-compatible mounts: entries would vanish from the collection, which
  the owner rejected.
- Per-character storage: rejected by the owner and contradicted by the report.

## Consequences / tradeoffs

- A login may send one `SMSG_LEARNED_SPELL` per missing collection spell. Acceptable at this scale;
  revisit if an account collects hundreds of mounts and login time becomes visible.
- The mount cast gate is new server behavior: `SPELL_FAILED_SPELL_UNAVAILABLE` when the character's
  riding rank is below the requirement, or the mount belongs to another faction. Game masters
  bypass it.
- Class mounts become ordinary riding-gated mounts: any character at the required riding rank can
  summon them, whatever its class. Faction mounts stay faction-gated.
- A character deletion leaves the account rows untouched; the next login rematerializes the spells.
- Transmog appearances keep their own account storage (`mod-transmog-plus`); this ADR does not change
  them.

## References

- [ADR-020](ADR-020-collections-transmog-stack.md), [RFC-002](../rfcs/active/RFC-002-collections-transmog.md)
- [specs/collections.md](../specs/collections.md)
- `modules/mod-forever-journal/`, `modules/mod-account-bound/`
