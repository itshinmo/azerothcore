# .ai — agent knowledge layer

Agent-agnostic knowledge for this repository. It consumes and links to the root-level sources
(`specs/`, `decisions/`, `rfcs/`, `runbook/`, `README.md`, `CONTRIBUTING.md`) and never duplicates a
contract or a procedure.

Entry point for agents: [`../AGENTS.md`](../AGENTS.md). Tool adapters are pointer-only:

| Tool | Agents | Skills |
|------|--------|--------|
| Claude Code | `.claude/agents` → `.ai/agents` | `.claude/skills` → `.ai/skills` |
| OpenCode | `.opencode/agents` → `.ai/agents` | `.opencode/skills` → `.ai/skills` |
| Other | read `.ai/agents/` directly | `.agents/skills` → `.ai/skills` |

An adapter never holds content. `AGENTS.md` stays the single instruction source.

## Precedence

```text
explicit human instruction > code/config > specs > decisions > runbook > memories > assumptions
```

If a lower source disagrees, fix it or flag it. Do not invent a fact to fill a gap; ask.

## Placement rules

| Location | Holds | Test question |
|----------|-------|---------------|
| `specs/` | current behavior, contracts, invariants | What must the system do? |
| `decisions/` | accepted decisions and rationale (ADRs) | Why was this chosen? |
| `rfcs/` | proposals (`active/`) and closed ones (`archived/`) | Is it proposed, not accepted? |
| `runbook/` | development, operation, database, GM, troubleshooting | Would a human need it with no AI tooling? |
| `.ai/memories/` | durable orientation for agents | Does it help an agent decide without being a contract or procedure? |
| `.ai/memories/working/` | unresolved or in-flight context | Is it still active? |
| `.ai/skills/` | reusable task workflows | Is it a repeatable class of task? |
| `.ai/agents/` | role behavior and boundaries | Does it apply to one role only? |
| `.ai/templates/` | templates for maintaining this layer | — |
| `.agents/docs/` | upstream AzerothCore coding rules | Is it a code convention from upstream? |

## Index

Load only what the task needs.

### Memories

- [`overview.md`](memories/overview.md) — what this repo is, current state, scope. Read first.
- [`status.md`](memories/status.md) — current phase, known issues, open decisions, next tasks.
- [`architecture.md`](memories/architecture.md) — runtime, core modules, content pipeline. Before
  changing structure.
- [`conventions.md`](memories/conventions.md) — C++, SQL, Node, IDs, secrets, logging. Before writing
  code.
- [`testing.md`](memories/testing.md) — test levels and gates. Before writing tests.
- [`development-workflow.md`](memories/development-workflow.md) — build, run, worktrees, approvals.
- [`database.md`](memories/database.md) — three databases, key tables, updater, safety.
- [`operations.md`](memories/operations.md) — start/stop, logs, backups, health.
- [`security.md`](memories/security.md) — RBAC, DB users, client access, secrets, audit.
- [`working/README.md`](memories/working/README.md) — lifecycle for in-flight memories.

### Agents

Order: documenter → content-author / db-admin / implementer → verifier → human review → reviewer →
commit on request. pr-shepherd on request.

- [`documenter.md`](agents/documenter.md) — requirements to specs, ADRs, RFCs, runbooks.
- [`content-author.md`](agents/content-author.md) — future content design and SQL drafts.
- [`implementer.md`](agents/implementer.md) — C++ and script changes to spec.
- [`db-admin.md`](agents/db-admin.md) — schema, queries, DBeaver, migrations, backups.
- [`reviewer.md`](agents/reviewer.md) — strict gate: correctness, security, regression, spec drift.
- [`verifier.md`](agents/verifier.md) — build, unit/e2e, smoke, manual evidence.
- [`server-operator.md`](agents/server-operator.md) — local/test start-stop, SQL apply, backups, logs.
- [`pr-shepherd.md`](agents/pr-shepherd.md) — GitHub PR review and follow-up, drafts only.

### Skills

Core:

- [`ask-the-human`](skills/ask-the-human/SKILL.md) — raise an open question with options.
- [`worktree-workflow`](skills/worktree-workflow/SKILL.md) — one task, one branch, one worktree.
- [`secrets-and-config`](skills/secrets-and-config/SKILL.md) — safe local config and credentials.
- [`build-and-run-server`](skills/build-and-run-server/SKILL.md) — build, install, start, stop.
- [`server-health-check`](skills/server-health-check/SKILL.md) — ports, DB, logs, login.
- [`log-triage`](skills/log-triage/SKILL.md) — classify and locate server errors.
- [`db-query-and-edit`](skills/db-query-and-edit/SKILL.md) — safe reads and guarded writes.
- [`db-backup-restore`](skills/db-backup-restore/SKILL.md) — dump, verify, restore.
- [`db-migration-safety`](skills/db-migration-safety/SKILL.md) — idempotency and rollback.
- [`pending-sql-import`](skills/pending-sql-import/SKILL.md) — apply pending/custom SQL.
- [`verify-change`](skills/verify-change/SKILL.md) — choose and run the verification tier.
- [`write-unit-test`](skills/write-unit-test/SKILL.md) — Google Test or Node test.
- [`write-e2e-test`](skills/write-e2e-test/SKILL.md) — live-stack Go e2e, only when asked.
- [`review-change`](skills/review-change/SKILL.md) — review a diff or PR.
- [`spec-drift-sync`](skills/spec-drift-sync/SKILL.md) — reconcile code and docs.
- [`prd-to-spec`](skills/prd-to-spec/SKILL.md) — requirement to spec, RFC, or ADR.
- [`generate-pr-description`](skills/generate-pr-description/SKILL.md) — PR title and body.

GM:

- [`gm-command-handbook`](skills/gm-command-handbook/SKILL.md) — find and use a GM command safely.
- [`gm-rbac-management`](skills/gm-rbac-management/SKILL.md) — roles and permissions.
- [`gm-item-grant-refund`](skills/gm-item-grant-refund/SKILL.md) — grant, mail, refund, audit.
- [`gm-incident-response`](skills/gm-incident-response/SKILL.md) — contain, diagnose, restore.

Planned, not created yet: `add-custom-quest`, `add-custom-npc-vendor`, `add-custom-item-mount`,
`add-smartai`, `add-instance`, `client-patch-and-extract`, `add-module`, `shop-entitlement`. Create
them when the corresponding work starts; keep the index in step.

### Templates

[`memory.md`](templates/memory.md), [`working-memory.md`](templates/working-memory.md),
[`skill.md`](templates/skill.md), [`agent.md`](templates/agent.md), [`spec.md`](templates/spec.md),
[`adr.md`](templates/adr.md), [`rfc.md`](templates/rfc.md), [`runbook.md`](templates/runbook.md).

## Rules

- Single source of truth: link, do not copy.
- Memories describe the present, not history.
- No secrets, credentials, internal hostnames, player data, or production values.
- Every new skill or agent gets an entry in this index in the same change.
- A skill with a project-specific rule links to the rule in `.agents/docs/` or `specs/`; it does not
  restate it.
