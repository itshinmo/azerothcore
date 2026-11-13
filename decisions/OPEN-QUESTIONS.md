# Open questions

Decisions that are not made yet. Do not implement a blocked area until its question is answered. When
answered, record the answer in an ADR or spec and remove the entry.

## Shop delivery trust model

**Question:** How does the website grant a purchase on the server?

Options:

1. Server API module with HMAC-signed requests (preferred in the plan).
2. Website writes entitlement rows directly to MySQL.
3. Manual GM grants until automation exists.

**Blocks:** shop implementation, website contract, entitlement schema.
**Owner:** human.
**Record:** ADR-006 and a new ADR when chosen.

## Production provider and region

**Question:** Which host, region, and budget?

Candidates: Hetzner Cloud CCX (performance/price), OVHcloud Rise, DigitalOcean Premium. Ubuntu 24.04
LTS, 4 vCPU / 16 GB / NVMe target.

**Blocks:** production deploy runbook finalization, DNS/TLS, backups, monitoring.
**Owner:** human.
**Record:** a new ADR that extends ADR-003.

## Client patch timing

**Question:** When do we build the MPQ/DBC and map-extraction pipeline for genuinely new zones?

Current decision: reuse existing assets first. New zones are blocked until the pipeline is documented,
approved, and tested on a copy of the client.

**Blocks:** new maps, new zones, new item visuals, new spell visuals, new area triggers.
**Owner:** human.
**Record:** ADR-002 or a new ADR.

## Per-account experience override

**Question:** How does a player select a lower experience rate?

Options:

1. A project module with an in-game command and a persisted per-account value (preferred).
2. GM-assisted only, with the value stored on the account.
3. No override; the realm runs one rate for everyone.

**Blocks:** publishing the 1x purist option promised by ADR-012.
**Owner:** human + implementer.
**Record:** a new ADR that extends [ADR-012](ADR-012-progression-rates.md).

## Shop product list revision

**Question:** Does the allowed product list in [specs/shop.md](../specs/shop.md) change before shop
work starts?

The current list permits experience and reputation boosts. That is compatible with a paid convenience
model and incompatible with a strict no-progression-sales promise. The question is deferred until the
shop is actually built; no shop code is in scope now.

**Blocks:** shop implementation.
**Owner:** human.
**Record:** a new ADR that extends ADR-006, plus the spec update.

## Map imagery for the world data pages

**Question:** Where do the map images come from?

Options:

1. Minimap tiles derived from client data (what comparable sites use).
2. A licensed or public-domain asset set.
3. A non-asset schematic with spawn markers only.

**Blocks:** the public spawn map page, not the exported data.
**Owner:** human.
**Record:** a new ADR that extends ADR-011, plus the spec update.

## Account and character website pages

**Question:** After the world catalog and the spawn map, which account-facing pages ship first?

Options: account lookup, character summary, online players, instance info, audit search (admin zone
only). The world catalog answer covers public entity pages only; account and admin pages remain open.

**Blocks:** the website phase after the catalog.
**Owner:** implementer + db-admin, confirmed by human.
**Record:** a new ADR that extends ADR-010.

## Windows development path

**Question:** If a Windows developer joins, WSL2 or Docker?

Current decision: WSL2 or Docker; native Visual Studio is not the primary path.

**Blocks:** nothing now.
**Owner:** human.
**Record:** a new ADR that extends ADR-003.
