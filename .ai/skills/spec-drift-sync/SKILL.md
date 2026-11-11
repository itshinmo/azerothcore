---
name: spec-drift-sync
description: Use before handing off or merging a change. Reconciles code, SQL, specs, runbooks, and memories so the documents describe the current system.
---

# spec-drift-sync

## Prerequisites

- The change is implemented and verified.
- You know which behavior, procedure, or decision it changed.

## Workflow

1. Compare the diff with the current `specs/` and `runbook/`. List every statement the change makes
   false.
2. Update the most specific source:
   - behavior or contract → `specs/`
   - procedure → `runbook/`
   - hard-to-reverse choice → a new ADR or an RFC
   - durable agent orientation → `.ai/memories/`
   - repeatable workflow → `.ai/skills/`
3. Do not duplicate. Link to the source of truth.
4. Update every index that lists the changed file: `README.md`, `.ai/README.md`,
   `runbook/README.md`, `specs/README.md`, `decisions/README.md`.
5. Resolve any working memory tied to the branch: promote the durable parts, delete the file.
6. Check that no document now promises behavior the code does not have.

## Rules

- A behavior change updates its spec in the same change.
- A procedure change updates its runbook in the same change.
- An accepted ADR is never rewritten; supersede it.
- An RFC is archived after its durable content moves into a spec or ADR.
- Unknowns stay `<!-- TODO -->`; do not invent.

## Expected output

A short list: what changed, which docs were updated, which docs were checked and left alone, and any
open TODOs.

## References

- [.ai/README.md](../../README.md)
- [CONTRIBUTING.md](../../../CONTRIBUTING.md#knowledge-placement)
- [.ai/templates/spec.md](../../templates/spec.md)
