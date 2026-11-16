# ADR-013 — Base game first, then custom content, then the website

- Status: accepted
- Date: 2026-11-16
- Amends: [ADR-010](ADR-010-website-as-visual-interface.md)
- Related: [ADR-011](ADR-011-world-data-and-content-verification.md)

## Context

ADR-010 made the future server website the long-term visual layer and made every GM feature
API-first. A later draft of this ADR put production deployment ahead of the website. The project
vision is different:

1. Make the base game fully functional and stable.
2. Add custom content that makes this server unique.
3. Build the website.
4. Publish the server.

"Production" means the point where the vision is implemented and the server is ready to launch. It is
not a separate gate before the website. Playtests, including a VPS shared with friends, may happen
between phases and are not a roadmap gate.

The base game is not yet fully functional. Scripts, quests, NPC spawns, and NPC behavior still need
verification, and known client and stability issues remain. Custom content built on that surface
would multiply the defects.

## Decision

1. Phase 1 is the base game: every script works, every quest works, every NPC spawns and behaves
   correctly, and the server is stable. No new content is added in this phase.
2. Phase 2 is custom content: hardcore rule-sets and other features that make the server unique.
   The exact scope is discussed when Phase 1 is close to done and is recorded in new ADRs.
3. Phase 3 is the website: the admin BFF/dashboard, website authentication, account and character
   pages, the public catalog, the spawn map page, and the shop frontend.
4. Phase 4 is launch: production host, DNS/TLS, backups, monitoring, and publishing the server.
5. Website-dependent work is deferred until Phase 3. This includes the admin BFF/dashboard,
   website auth, account and character pages, public catalog pages, the static spawn map page, the
   shop frontend, and the loopback `make world-api` serving surface.
6. The world data export and the content audit stay active. The audit is a base-game release gate
   and consumes the same extractor output; only the HTTP serving and page layers wait.
7. The GM API is server work, not website work. It stays API-first and grows during Phase 1. Manual
   testing uses the committed Bruno collection ([ADR-014](ADR-014-bruno-api-test-client.md)); curl
   remains the headless fallback.
8. In-game and CLI tools stay available. No one-off web UI is added while the website waits; ADR-010
   rule 3 still applies.
9. The production host, region, and budget are chosen before launch, not before Phase 1. They do not
   block base-game or custom-content work.

## Alternatives considered

- **Website first, base game after.** Rejected. The game surface is still moving; a website would
  need rework for every server change.
- **Deploy to production before the website.** Rejected. Launch follows the website, not the other
  way around. Early playtests use a test VPS, not the launch deployment.
- **Build custom content and base-game fixes together.** Rejected. It hides base-game defects behind
  new content and makes regressions harder to attribute.
- **Keep GM API writes on hold until the dashboard.** Rejected. It slowed Phase 1 and left audited
  write paths untested; a local API client removes that blocker.

## Consequences

- The status file, specs, and runbooks now order tasks by these phases.
- Base-game verification becomes the primary work: quest chains, scripts, NPC spawns and behavior,
  client behavior, and stability.
- GM API writes and reads can be built and tested during Phase 1.
- Custom content stays out of scope until Phase 1 is done.
- Website decisions remain open and are not on the current critical path.
- Launch is the final phase; a test VPS may host friends earlier without becoming production.
