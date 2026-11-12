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
**Record:** ADR-003 update or a new ADR.

## Client patch timing

**Question:** When do we build the MPQ/DBC and map-extraction pipeline for genuinely new zones?

Current decision: reuse existing assets first. New zones are blocked until the pipeline is documented,
approved, and tested on a copy of the client.

**Blocks:** new maps, new zones, new item visuals, new spell visuals, new area triggers.
**Owner:** human.
**Record:** ADR-002 or a new ADR.

## GM panel first scope

**Question:** Which read-only endpoints ship first?

Proposed: account lookup, character summary, online players, instance info, audit search. Writes
follow after the read path is proven.

**Blocks:** phase 4 implementation detail.
**Owner:** implementer + db-admin, confirmed by human.
**Record:** ADR-005 update.

## Windows development path

**Question:** If a Windows developer joins, WSL2 or Docker?

Current decision: WSL2 or Docker; native Visual Studio is not the primary path.

**Blocks:** nothing now.
**Owner:** human.
**Record:** ADR-003 update.
