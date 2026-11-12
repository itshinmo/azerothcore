---
name: review-change
description: Use when reviewing a local diff, a commit, or a pull request. Findings only, severity-tagged, with file and line.
---

# review-change

## Prerequisites

- The diff: `git diff`, `git diff master...HEAD`, or a PR.
- The spec, ADR, runbook, and issue the change claims to implement.
- The matching verification evidence.

## Workflow

1. Read the whole diff and every file it touches, not only the changed lines.
2. Check the applicable rules:
   - `.agents/docs/cpp-guidelines.md`, `cpp-scripts.md`, `sql-guidelines.md`
   - `AGENTS.md` (secrets, DB safety, approval)
   - `specs/` and `decisions/` for the contract
   - `specs/security.md` for RBAC, client access, GM API
3. Trace changed control flow into every consumer, including unchanged lines the new flow reaches.
4. Verify claims against code, data, or a source. Do not accept a PR description as fact.
5. Run both linters when the diff touches C++ or SQL.
6. Report findings ordered by severity, each with `path:line`, the problem, why it matters, and the
   fix.
7. State the verdict: approve or request changes.

## Constraints

- Findings only: no summary, no praise, no restating the diff.
- No taste-based findings unless a written rule covers them.
- No secrets in a finding; name the file and line.
- Do not rewrite the change; the author does.
- An approval covers the reviewed diff only.
- A review posted on GitHub is not the approval gate.

## Severity

- **blocker** — crash, data loss, security hole, broken behavior, missing backup for a write.
- **major** — regression risk, spec drift, missing test for new behavior, performance cliff.
- **minor** — maintainability, unclear naming, missing documentation.
- **nit** — only if it changes meaning.

## Expected output

Verdict plus findings, each with file/line, severity, problem, and fix. Open questions when a decision
is not yours.

## References

- [.agents/docs/code-review.md](../../../.agents/docs/code-review.md)
- [.agents/docs/self-review-rules.md](../../../.agents/docs/self-review-rules.md)
- [.ai/agents/reviewer.md](../../agents/reviewer.md)
