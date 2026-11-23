# Transmog

## Purpose

How appearances are changed on this realm: where the window opens, who may change a look, and how
the pending look is previewed.

## Scope

The transmogrifier NPC access, the Journal Appearances tab, apply/remove, and the preview.

## Boundary

Owns the access rule and the preview path. Does not own the appearance catalog, account storage,
costs, or the transmogrifier's gossip menu; those belong to `modules/mod-transmog-plus`. Mount, pet
and toy collections are [collections.md](collections.md).

## Contract

- **Access**: appearance changes require the Warpweaver (creature entry `910012`) within 10 yards.
  The check runs server-side on apply, remove, remove-all, illusion and form.
  `Transmog.OpenAnywhere = 0`, so `/transmog`, the key binding and the Journal tab do not open the
  window away from the NPC.
- **Journal tab**: the Appearances tab is hidden by default. The transmogrifier's gossip sends
  `Open`; the addon shows the tab and opens the window. Closing the window hides the tab. Journal
  API 2 adds `Journal.SetTabVisible(key, visible)`.
- **Collection**: Ctrl+right-click collects an unbound appearance and soulbinds the item anywhere.
  Collecting is not changing an appearance and is not gated by the NPC.
- **Preview**: client-side and UI-only. The model is a `DressUpModel` copy of the real player
  (`SetUnit("player")`). `DressUpModel` has no per-slot `TryOff`, so the model is rebuilt with
  `Undress` and every visible look is tried on again. A hidden appearance is skipped, which leaves
  that slot empty in the preview. No player visible-item field and no server state are written by a
  preview; Apply is the only commit. Illusions preview in their tile.
- **Hand-specific preview items**: 3.3.5 `DressUpModel:TryOn` has no hand-slot argument (added in
  Legion 7.0.3); it picks the hand from the item's `InventoryType`. A generic one-hand weapon
  (`INVTYPE_WEAPON`, 13) always lands in the main hand. The server generates a hidden,
  non-obtainable preview copy of every one-hand weapon at `entry + 2000000` with
  `InventoryType = INVTYPE_WEAPONOFFHAND` (22), and of every thrown weapon with
  `InventoryType = INVTYPE_WEAPONMAINHAND` (21). The addon uses the off-hand copy for the off-hand
  slot and the main-hand copy for a thrown weapon. While a thrown weapon's ranged slot is selected,
  the preview skips the real main hand and off hand so only the thrown weapon is shown; bows, guns
  and wands keep both melee weapons visible. The Sets tab uses the same hand-specific copies for
  its pieces. No client patch is needed.
- **Preview item range**: generated preview items occupy `2000000–2999999`; they are excluded from
  appearance source lists by item ID and are never obtainable, looted, sold, or mailed.

## Errors

- A mutation away from the NPC is refused with the module string "Visit a transmogrifier to change
  your appearance." The addon receives the matching failure result, so its Apply button re-enables.

## Security

- The NPC distance check is server-side; client settings and the tab's visibility are not a gate.
- A preview writes no player visible-item field and no server state; it exists only in the client's
  UI model.

## Observability

- No log lines; refusals are player chat messages.

## References

- [ADR-026](../decisions/ADR-026-transmog-npc-only-and-preview.md)
- [ADR-020](../decisions/ADR-020-collections-transmog-stack.md)
- `modules/mod-transmog-plus/`
