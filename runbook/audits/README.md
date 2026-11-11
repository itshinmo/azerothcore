# Audits

One-shot repository and operations audits. Findings are ranked, evidence-backed, and either fixed
through the strict gate or left open with an owner.

## Format

```markdown
# <date> — <scope>

## Summary
- P0: <count>
- P1: <count>
- P2: <count>
- P3: <count>

## Findings
### P0 — <title>
- Evidence: file:line, command, log line
- Impact:
- Fix:
- Status: open | fixed <commit> | deferred <owner>

## What was checked
## What was not checked
```

## Severity

- **P0:** data loss, security hole, production outage, broken build/start.
- **P1:** regression risk, broken workflow, missing backup, RBAC over-grant.
- **P2:** maintainability, docs drift, performance risk.
- **P3:** minor cleanup.

## Rules

- No finding without evidence.
- Separate facts from hypotheses.
- Do not fix in the audit change unless the human asked; fixes go through the gate.
- Update the status when a finding is resolved.

## Index

| Date | Scope | Report |
|------|-------|--------|
| — | — | — |
