# ADR-001 — Agent knowledge layer and approval gate

- Status: accepted
- Date: 2026-11-12

## Context

The repository has strong upstream coding rules in `AGENTS.md` and `.agents/docs/`, but no durable
project knowledge layer, no role agents, no skills for this fork's operations, and no approval gate.
Multiple agents and humans will work in the same clone. The work includes database writes and GM tools,
where an unreviewed change can corrupt player data or expose an account.

## Decision

1. **Knowledge layer.** Add `.ai/` with `agents/`, `skills/`, `memories/`, and `templates/`. Add root
   `specs/`, `decisions/`, `rfcs/`, and `runbook/`. Keep `.agents/docs/` as upstream task-scoped
   coding rules; do not duplicate them.
2. **Single source.** `AGENTS.md` is the instruction entry point. Tool adapters are pointer-only
   symlinks: `.claude/{agents,skills}`, `.opencode/{agents,skills}`, `.agents/skills` → `.ai/`.
3. **Roles.** documenter, content-author, implementer, db-admin, reviewer, verifier, server-operator,
   pr-shepherd. Definitions in `.ai/agents/`.
4. **Approval gate.** Agents never stage, commit, push, deploy, or write to production. A change is
   eligible for commit only after a human approves it and then the reviewer agent approves it. An
   approval covers the reviewed diff only. The pr-shepherd drafts and posts only after human
   confirmation; it never approves.
5. **Ask, do not guess.** Blocking questions go to the human with concrete options and a
   recommendation. An answer is not an approval.
6. **Precedence.** Human instruction > code/config > specs > decisions > runbook > memories >
   assumptions. Fix or flag the lower source.

## Alternatives considered

- **Expand only `.agents/`.** Smaller change, but no project specs, ADRs, runbooks, or role agents.
- **Copy the se-client-kit layer verbatim.** Its TypeScript/monorepo skills do not fit a C++/MySQL
  game server.
- **Let agents commit freely and review on the PR.** Faster, but unreviewed DB and GM changes reach
  history.
- **Reviewer agent before human review.** Rejected: the human decides whether the change is wanted;
  the reviewer enforces the rules on an approved direction.

## Consequences

- Slower loop: agents stop for human and reviewer approval.
- History contains only approved changes.
- Every project-specific rule has one home.
- Adapters stay trivial; a new tool adds a symlink, not content.
