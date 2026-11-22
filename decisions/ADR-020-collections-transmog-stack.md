# ADR-020 — Collections and transmog stack

- Status: accepted; revised 2026-11-22 by [ADR-025](ADR-025-account-wide-collections.md) (mounts, pets
  and toys are account-owned; AccountBound mounts/pets off)
- Date: 2026-11-20
- Implements: [RFC-002](../rfcs/active/RFC-002-collections-transmog.md) (owner decisions of 2026-11-20)

## Decision

1. **Adopt the buildthehomelab stack**, vendored as plain source trees under `modules/`
   (upstream `.git` removed; licenses and attribution retained):
   - `mod-transmog-plus` — slot-based transmog, account-wide appearance collection with retail-style
     unlock triggers, addon UI. Source: buildthehomelab/wow-mod-transmog-plus `0ee0aff8f`
     (2026-11-02). License: AGPL-3.0 — modified versions stay AGPL; the public repository satisfies
     the network-source requirement.
   - `mod-account-bound` — account-wide mounts, pets, titles, friends (per-owner decision:
     achievements, professions, reputations OFF). Source: AlsoNotMehh/mod-account-bound
     `a5a89a179` (2026-09-03). License: GPL-2.0 per the LICENSE file (the README badge says GPLv3;
     the file wins and is retained).
   - `mod-forever-journal` — the Collections journal window (Mounts, Pets, Toys, Appearances tabs;
     Appearances comes from transmog-plus). Source: buildthehomelab/wow-mod-forever-journal
     `36d0f1d4c` (2026-11-05). License: MIT — attribution retained.
2. **Storage**: dedicated custom tables in the characters DB keyed by account id (transmog-plus
   pattern) for appearances, outfits, illusions; core character tables materialized for spells the
   client already reads (account-bound pattern for mounts/pets). No custom `acore_auth` tables.
3. **Config**: `Transmog.OpenAnywhere = 1` (addon opens anywhere); retail collection triggers stay
   on; transmog quality rules at module defaults. AccountBound categories per owner decision above.
   Toys stay per character with the journal's 69 baseline seeds; no custom toys.
4. **Transmogrifier NPC**: entry `910012` ("Warpweaver", remapped from the upstream default 190012,
   which sits below the reserved creature range per [the ID registry](../runbook/database/id-registry.md);
   `npc_transmogrifier` is script-name driven, so only the SQL changes). Spawned **next to each
   capital's auction house** — where players gather (owner decision 2026-11-20; Shattrath's stands
   at the Lower City bank, that city has no auction house) — by
   `data/sql/custom/db_world/collections_npc_spawns.sql`, spawn GUID block `5400001–5400010`
   (kept ~100k above the table's max GUID so upstream spawn updates do not land in it). The
   file's re-apply DELETEs every spawn of the template, so test `.npc add` strays do not survive.
   Players without the addon use the NPC gossip; the addon path is primary.
5. **Player-facing access stays addon-first**; at launch the addon folders embed into the shipped
   client MPQ patch ([RFC-002](../rfcs/active/RFC-002-collections-transmog.md)). The GM API, RBAC,
   and audit are untouched — collections is player self-service.
6. **City guards point at the Warpweaver** (owner request, 2026-11-20): each capital's
   direction-giving NPC gets a "The transmogrifier" gossip option with a minimap marker, via the
   server's `points_of_interest` table + `gossip_menu_option.ActionPoiID` → `SMSG_GOSSIP_POI`
   (`GossipDef.cpp` `SendPointOfInterest` — no client data involved). POIs 950110–950119 and the
   shared answer `npc_text` 950120 (misc range, registered). NPCs: Stormwind City Guard,
   Ironforge Guard, Darnassus Sentinel, Exodar Peacekeeper, Orgrimmar Grunt, Undercity Guardian,
   Bluffwatcher (Thunder Bluff's direction NPC), Silvermoon City Guardian, Shattrath City
   Peacekeeper, and Dalaran's Violet Citadel teleport-service NPCs (Dalaran has no guards).

## Consequences

- Startup backfill scans character tables (account-bound) and login scans for retroactive
  collection (transmog-plus); acceptable at our scale, monitor as population grows.
- `azerothcore/mod-transmog` must never be installed alongside transmog-plus (data model conflict).
- The journal answers only its addon; without it, directory content falls back to gossip, and
  collections tabs are addon-only.
- Optional look packs (druid forms, totems, demons, backpacks) each need their own client patch —
  deferred; core transmog needs no client patch.

## References

- [RFC-002](../rfcs/active/RFC-002-collections-transmog.md)
- [ADR-013](ADR-013-server-and-client-before-website.md), [ADR-018](ADR-018-realm-strategy.md),
  [ADR-019](ADR-019-instance-scope-closed.md)
- [runbook/operation/client-bundle.md](../runbook/operation/client-bundle.md)
