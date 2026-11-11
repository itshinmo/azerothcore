---
name: prd-to-spec
description: Use when a requirement, bug report, or audit finding must become a spec, RFC, or ADR before implementation.
---

# prd-to-spec

## Prerequisites

- The raw requirement or finding.
- The existing spec, runbook, and code it touches.

## Workflow

1. Frame the problem: who is affected, what happens today, what should happen, and what is out of
   scope.
2. Write acceptance criteria that a verifier can test. Include failure states and observability.
3. Choose the artifact:
   - current behavior or a contract → `specs/`
   - significant, cross-cutting, or contested → `rfcs/active/`
   - hard-to-reverse choice → `decisions/ADR-NNN-*.md`
   - procedure → `runbook/`
4. For a spec, fill [the spec template](../../templates/spec.md): purpose, scope, boundary, contract,
   errors, security, observability, references.
5. Identify the verification tier and the tests or manual checks.
6. Ask the human about blocking gaps before handoff.
7. Update the index.

## Rules

- A spec describes accepted behavior, not a wish.
- Proposed behavior stays in an RFC until accepted.
- Do not paste a rough PRD wholesale; distill it.
- No secrets, production values, or player data.
- A hard-to-reverse choice needs an ADR, not a paragraph in a spec.

## Expected output

A spec/RFC/ADR diff, acceptance criteria, verification plan, and open questions.

## References

- [.ai/templates/spec.md](../../templates/spec.md)
- [.ai/templates/rfc.md](../../templates/rfc.md)
- [.ai/templates/adr.md](../../templates/adr.md)
- [CONTRIBUTING.md](../../../CONTRIBUTING.md#development-flow)
