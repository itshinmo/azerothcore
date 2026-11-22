# ADR-026 — Transmogrifier-only appearance changes

- Status: accepted
- Date: 2026-11-22
- Revises: [ADR-020](ADR-020-collections-transmog-stack.md) §3 (OpenAnywhere and addon-first access)

## Context

Appearance changes were allowed from anywhere: `Transmog.OpenAnywhere = 1` let `/transmog`, the key
binding and the Journal's Appearances tab open the window without an NPC. The owner wants them
available only while interacting with the Warpweaver.

A first attempt made the preview server-assisted by writing the pending look into the player's
`PLAYER_VISIBLE_ITEM_*` fields. Those fields drive the character in the world, so the look changed
in game without Apply. That approach was reverted before release.

## Decision

1. `Transmog.OpenAnywhere = 0`. `/transmog`, the key binding and the Journal tab no longer open the
   window away from a transmogrifier.
2. The Journal's Appearances tab is **hidden** unless the transmogrifier's gossip opened it. The
   Journal API gains `Journal.SetTabVisible(key, visible)` (API 2); the transmog addon shows the tab
   on the server's `Open` message and hides it when the window closes.
3. Every appearance mutation is checked **server-side** against the Warpweaver (creature entry
   `910012`) within 10 yards: apply, remove, remove all, illusion and form. A modified client cannot
   change appearance remotely. Collecting an appearance with Ctrl+right-click stays allowed
   anywhere; it collects, it does not change the character.
4. The preview is **client-side and UI-only**. It is a `DressUpModel` copy of the real player
   (`SetUnit("player")`), with staged looks tried on top and **no `Undress`**. No player visible-item
   field and no server state are written by a preview. Illusion previews stay in their tile.
5. A dual-wield preview that puts a pending off-hand appearance on the left hand is limited by the
   3.3.5 client: `DressUpModel:TryOn` has no hand-slot argument (that arrived in Legion 7.0.3). If
   the client-side overlay cannot show it, the fix belongs to the client-patch pipeline, not to the
   server.

## Alternatives considered

- Server-assisted preview through the player fields. Rejected: the same fields drive the world
  model, so the preview looked applied without Apply.
- Keep the client-side rebuild with `Undress`. Rejected: `Undress` removes both weapons first, and
  every one-hand `TryOn` then lands in the main hand.
- Apply on selection. Rejected: the owner wants Apply to be the only commit.
- Broadcast the preview update. Rejected for the same world-model leak.

## Consequences

- Players must visit the Warpweaver. The tab appears while the gossip session is active and
  disappears when the window closes; switching to another Journal tab closes it, so it reopens from
  the NPC.
- The preview never changes the character in the world and never saves anything.
- A pending off-hand weapon preview may still be imperfect on the stock 3.3.5 client; a true
  slot-targeted preview needs a client patch and is tracked for the client-patch pipeline.
- `Journal.API` is 2. An older Journal without `SetTabVisible` shows the tab, but the server gate
  still refuses changes away from the NPC.

## References

- [ADR-020](ADR-020-collections-transmog-stack.md), [RFC-002](../rfcs/active/RFC-002-collections-transmog.md)
- [specs/transmog.md](../specs/transmog.md)
- `modules/mod-transmog-plus/`, `modules/mod-forever-journal/`
