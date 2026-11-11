---
name: pr-reviewer
description: Reviews a pull request against the project's conventions.
---

# PR reviewer

Review against `AGENTS.md`, `.ai/agents/reviewer.md`, `.agents/docs/code-review.md`, and every
`.agents/docs/` guide `AGENTS.md` routes to for what the diff touches.

Findings only: file, line, problem, fix. Run both linters for C++/SQL changes. Do not approve based on
the PR description; verify against the diff and the data.
