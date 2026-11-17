# ADR-013 — Base game first, then custom content, then the website

- Status: accepted (2026-11-16); revised 2026-11-17 — Phase 1 exit made measurable, and
  custom-content planning may start in parallel once the gate is met (approved by the repository
  owner on 2026-11-17)
- Date: 2026-11-16, revised 2026-11-17
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

1. Phase 1 is the base game. Exit is **measured evidence, not opinion**:
   - the weekly upstream sync ritual has run several consecutive times without incident;
   - the playerbot test rig (see [ADR-015](ADR-015-playerbot-test-rig.md), when built) clears a
     defined dungeon pool at a success rate the repository owner accepts, and soak sessions stay
     clean;
   - the [base-game verification checklist](../runbook/operation/base-game-verification.md)
     sections A-F pass (F, stability, is cross-checked by the soak criterion above);
   - the player bug-report flow is live and triaged to zero open new reports.
2. Phase 2 is custom content: hardcore rule-sets and other features that make the server unique.
   Planning and the first ADR (hardcore rule-sets) may start **in parallel** once the Phase 1 gate
   above is met; implementation still records each feature in a new ADR.
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
10. Base-game stability is consumed as much as produced: the weekly upstream sync
    ([runbook/development/worktrees-and-branches.md](../runbook/development/worktrees-and-branches.md))
    brings in upstream's continuous fixes, and the player bug-report flow
    ([runbook/operation/bug-reports.md](../runbook/operation/bug-reports.md))
    feeds unique fixes back upstream. Self-auditing stays limited to what upstream cannot see:
    this realm's data, this fork's deltas, and measured stability.

## Alternatives considered

- **Website first, base game after.** Rejected. The game surface is still moving; a website would
  need rework for every server change.
- **Deploy to production before the website.** Rejected. Launch follows the website, not the other
  way around. Early playtests use a test VPS, not the launch deployment.
- **Build custom content and base-game fixes together.** Originally rejected: it hides base-game
  defects behind new content and makes regressions harder to attribute. Revised 2026-11-17: the
  base-game fixes now arrive mostly from upstream and the playerbot rig rather than bespoke
  auditing, so custom-content planning may start once the measured Phase 1 gate is met. New
  content still never mixes into base-game fix changesets.
- **Keep GM API writes on hold until the dashboard.** Rejected. It slowed Phase 1 and left audited
  write paths untested; a local API client removes that blocker.

## Consequences

- The status file, specs, and runbooks now order tasks by these phases.
- Base-game verification runs continuously but cheaply: the sync ritual, the bot rig, and the
  checklist replace wholesale self-auditing as the primary mechanism.
- Phase 1 exit is a recorded measurement against the gate in decision 1, not a feeling.
- Custom-content ADRs can be drafted during Phase 1 once the gate is met; implementations follow
  the normal review gates.
- Website decisions remain open and are not on the current critical path.
- Launch is the final phase; a test VPS may host friends earlier without becoming production.
