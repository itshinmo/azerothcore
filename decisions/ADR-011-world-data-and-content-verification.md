# ADR-011 — World data pipeline and content verification

- Status: accepted (approved by the repository owner on 2026-11-14)
- Date: 2026-11-14
- Related:
  [ADR-010](ADR-010-website-as-visual-interface.md),
  [ADR-002](ADR-002-custom-content-isolation-and-ids.md),
  [ADR-007](ADR-007-verification-gates-and-fork-ci.md)

## Context

The server's promise is that quests, NPCs, spawns, dungeons, and raids work. The project has no
measurement of that promise. A player who hits a broken quest at level 12 does not report it; they
leave.

Two needs point at the same data:

1. A public catalog site, comparable to a database site: items, NPCs, quests, and spawn locations.
2. A content audit that finds broken references and unreachable content before players do.

Both read `acore_world`. Building them separately duplicates queries, drift,
and maintenance.

Behavioural verification at scale was considered. Random bots would exercise questing and dungeons,
but they cannot report what they observed, and the integration cost is not proportional to the
result.

## Decision

1. **One read-only extractor.** A project tool reads `acore_world` read-only and produces two outputs
   from one query layer:
   - static JSON catalog artifacts for the public site;
   - a content audit report with findings and severities.
2. **Static artifacts for the catalog.** The website never queries MySQL directly. Pages are served
   from exported JSON with freshness metadata. This keeps the website a client, per ADR-010. The
   first public pages are the entity catalog and the static spawn map.
3. **Live spawn state is deferred.** "Exists in the database" and "alive on the realm now" are
   different facts and are never merged into one field. The first public version ships static spawn
   data only. A live overlay needs a public read surface that does not carry the GM API secret; until
   that is designed, live state stays on the private GM API path. The public site never holds the GM
   API secret.
4. **The extractor is a project tool, not a module.** It runs offline, uses a read-only database
   user, and produces deterministic, diffable output. It is the single data contract for both
   consumers.
5. **The content audit is a release gate.** It reports findings by severity with a tracked waiver
   file. Unwaived blocker findings block a release; the check catalog lives in
   [specs/content-pipeline.md](../specs/content-pipeline.md).
6. **Publish the coverage number.** The audit defines a content coverage metric. The number is
   public and is the QA scoreboard.
7. **No fork for verification tooling.**
8. **The public catalog is free and requires no login.** Ads and paywalls are not part of it. This is
   a product policy, not a technical constraint.

## Alternatives considered

- **Website reads MySQL directly.** Fastest page implementation, but it bypasses the API boundary,
  exposes the database to a public service, and splits the data contract. Rejected.
- **Live database queries per page.** Always fresh, but couples page latency to the world database
  and makes caching unsafe. Rejected; static export plus an explicit live overlay instead.
- **Playerbots as the verifier.** The maintained module requires a custom AzerothCore fork, not a
  drop-in module: at the time of writing (2026-11-14) the fork carries a small core delta and the
  module is over a thousand source files, and it adds the `acore_playerbots` database. The core
  already carries the headless-session plumbing (`IsHeadless` in
  `src/server/game/Server/WorldSession.h`). Adopting it would mean either rebasing this fork onto
  the playerbots fork or vendoring that core delta and re-checking it on every upstream sync,
  permanently. Bots also cannot self-report failures; their value is log noise under load, which
  static checks and the error log already provide cheaply. Rejected.
  Revisit only if behavioural coverage at scale becomes a hard requirement, and then in a throwaway
  branch that never merges into production.

## Consequences

- The extractor becomes a stable contract. Changing its output is a spec change.
- The audit report and the public site can never disagree about what exists in the database.
- Data freshness must be visible. A stale export must say so on the page.
- The audit will produce a large first report. Reducing it is content work, not tooling work.
- No bot infrastructure, no core fork, no extra database.
