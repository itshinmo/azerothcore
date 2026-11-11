# Decisions (ADRs)

Decisions and their rationale, for choices that are hard to reverse. ADRs are never rewritten; a later
decision supersedes one and both link each other.

## Conventions

- File name `ADR-NNN-<slug>.md`, numbered in order.
- Status is `proposed` until a human accepts it, then `accepted`.
- Disagreement with an accepted ADR goes to an RFC, not a review exception.
- No secrets, production hostnames, credentials, or player data.

## Index

| ADR | Status | Decision |
|-----|--------|----------|
| [ADR-001](ADR-001-agent-knowledge-layer.md) | accepted | `.ai` knowledge layer, role agents, strict approval gate, pointer adapters |
| [ADR-002](ADR-002-custom-content-isolation-and-ids.md) | accepted | tracked modules + tracked SQL, reserved ID ranges, client-patch boundary |
| [ADR-003](ADR-003-runtime-topology.md) | accepted | native macOS dev, Ubuntu 24.04 production, native binaries |
| [ADR-004](ADR-004-database-gui.md) | accepted | custom Node 26 GUI, localhost only, read-only production |
| [ADR-005](ADR-005-gm-tools-and-rbac.md) | accepted | GM handbook, least-privilege RBAC, audit, module API, in-repo addon |
| [ADR-006](ADR-006-shop-policy.md) | accepted (policy); trust model open | cosmetics + convenience only; delivery trust model TODO |
| [ADR-007](ADR-007-verification-gates-and-fork-ci.md) | accepted | tiered verification, dedicated test realm, fork CI |

Open questions: [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).
