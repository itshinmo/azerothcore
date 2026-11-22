---
description: Dual-wield transmog preview cannot put a pending off-hand appearance on the left hand on 3.3.5
owner: implementer + client-patch pipeline
status: blocked
related: local-server-setup, ADR-026
created: 2026-11-22
---

# Dual-wield transmog preview

## Context

The transmog window previews a pending look on a `DressUpModel` copy of the player. Armor and a
main-hand weapon preview correctly. An off-hand weapon appearance still lands in the main hand (or
leaves the off hand empty), so a rogue cannot see both pending weapons at once. The world character
is unaffected; the server preview that wrote player fields was reverted (ADR-026).

## Findings / hypotheses

- 3.3.5 `DressUpModel:TryOn` accepts only an item ID, name, or link. The hand-slot argument
  (`TryOn(link, handSlotName, illusionID)`) arrived in Legion 7.0.3 (warcraft.wiki); this client
  does not have it.
- `Undress` was the first culprit and is gone: the model starts from `SetUnit("player")` with both
  real weapons. A one-hand `TryOn` still lands in the main hand; Lua cannot target the off hand.
- 3.3.5 addons (DressMe, MogIt and the AzerothCore fork) preview one item per model; none builds a
  dual-wield composite.
- A server-side preview through `PLAYER_VISIBLE_ITEM_*` changes the world model, because the same
  fields drive it. Tried and reverted; not a fix.

## Open questions

- Can the client-patch pipeline add a slot-targeted `TryOn` (or a transmog preview API) to the
  3.3.5 client? That is the only path to a true 7.2.5-like preview.
- Until then: preview the selected weapon only in the tile, or accept the main-hand limitation on
  the character model?

## To promote on resolution

- `specs/transmog.md` and [ADR-026](../../../decisions/ADR-026-transmog-npc-only-and-preview.md).
- Client-patch pipeline runbook and a `client-patch-and-extract` skill.
