# Collections

## Purpose

Define what a mount, pet and toy collection is on this realm: who owns an entry, how it is recorded,
how it reaches a character, and what still gates use.

## Scope

Mounts, pets and toys; the journal's three collection tabs; the account tables; the grant and cast
paths.

## Boundary

Owns collection ownership and delivery. Does not own the catalog build, the source data, or the UI
layout; those belong to `modules/mod-forever-journal`. Does not own transmog appearances, which stay
with `mod-transmog-plus`.

## Contract

- Ownership is per **account**, in `acore_characters`:
  `mod_forever_journal_account_mounts(account_id, spell_id)`,
  `mod_forever_journal_account_pets(account_id, spell_id)`, and
  `mod_forever_journal_account_toys(account_id, item_id)`.
- A row is written the first time any character of the account learns the spell (mounts, pets) or
  stores the item (toys). Nothing deletes a row, and deleting a character changes nothing.
- Delivery is `character_spell`: every character of the account receives the collected spell at
  creation, at login, and when a sibling learns it. The 3.3.5 client lists companions from known
  spells, so no other channel is used. A sibling that is online at the moment of the learn gets the
  `character_spell` row, not a live packet, so it sees the entry at its next login.
- Login backfills mounts and pets learned before the account tables existed.
- Every collected mount and pet is listed, whatever the character's riding, class or faction.
- Use is gated by the server: a mount cast is refused with `SPELL_FAILED_SPELL_UNAVAILABLE` when the
  character's riding rank is below the requirement, or the mount is another faction's. The rank
  comes from the teaching item; a class mount has no teaching item, so its rank comes from the
  spell's level tier: below 40 gives 75, 40 to 59 gives 150, 60 and above gives 225. On the stock
  data that is Felsteed 75, Summon Warhorse 75, Dreadsteed 150, Charger 150 and Acherus
  Deathcharger 150. Game masters bypass the gate. Class is never a gate.
- Toys are used through their `ON_USE` spell, granted the same way, with the spell's own cooldown.

## Errors

- A missing account table is created by the module SQL the worldserver applies at restart
  ([ADR-018](../decisions/ADR-018-realm-strategy.md)). If the tables are absent at runtime, the
  collection writes disable themselves with one log line instead of querying a missing table;
  MySQL errno 1146 would abort the worldserver.
- A characters-database query must never join a world-database table. MySQL errno 1146 aborts the
  worldserver; resolve world data through `sObjectMgr` or `WorldDatabase` instead.

## Security

- Only the server writes collection rows. Addon messages request state; the `O` request also
  records toys the account already holds in bags or bank. They never record a mount or pet.
- Account ids and item ids from the client are never trusted as record keys. The collect request
  names a bag and slot; the server resolves the item there and validates its class.

## Observability

- `mod-forever-journal: <n> mounts, <n> pets and <n> toys` at startup reports catalog size.
- A refused mount cast is a normal cast failure; nothing is logged.

## References

- [ADR-025](../decisions/ADR-025-account-wide-collections.md)
- [ADR-020](../decisions/ADR-020-collections-transmog-stack.md)
- `modules/mod-forever-journal/`
