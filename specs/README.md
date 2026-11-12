# Specs

Current behavior and contracts: the source of truth. Implementation follows a spec, and a behavior
change updates its spec in the same change.

## Conventions

- One file per concern, kebab-case.
- Start from [the spec template](../.ai/templates/spec.md): purpose, scope, boundary, contract, errors,
  security, observability, references.
- A spec describes accepted behavior, not wishes. Proposals live in [`rfcs/`](../rfcs/).
- Unknowns are `<!-- TODO -->` markers, never invented.
- Link to decisions and runbooks instead of copying them.
- No secrets, production hostnames, credentials, or player data.

## Index

- [`architecture.md`](architecture.md) — system context, runtime, core modules, extension points.
- [`server.md`](server.md) — topology, ports, config, startup, shutdown, health, logging.
- [`database.md`](database.md) — three databases, SQL tree, updater, schema conventions, safety.
- [`content-pipeline.md`](content-pipeline.md) — how content is authored, stored, and verified.
- [`gm-tools.md`](gm-tools.md) — GM handbook, RBAC, audit, GM API, future website, in-game addon.
- [`testing-and-release.md`](testing-and-release.md) — test levels, tiers, test realm, CI, release.
- [`security.md`](security.md) — threat model, database users, client access, GM API, secrets, audit.
- [`shop.md`](shop.md) — shop policy and open trust decision. No implementation yet.
