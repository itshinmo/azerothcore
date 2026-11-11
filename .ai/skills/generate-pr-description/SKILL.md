---
name: generate-pr-description
description: Use when the user asks for a PR title and description for the current branch. Produces text only; never creates the PR, pushes, or changes git state.
---

# Generate PR description

Produce a copy-pasteable PR title and body for the current changes, using
[`pull_request_template.md`](../../../pull_request_template.md). Output text only.

## Gather the changes

"The changes" is the union of:

- committed branch work: `git diff <master-ref>...HEAD`, where `<master-ref>` is `origin/master`;
- staged and unstaged changes;
- the branch's commit messages (context only).

If all three are empty, say so and stop.

## Facts, never assumptions

Only the diff and facts stated in the conversation may fill the description. Never invent testing,
sources, issue links, or TODOs. An empty section is correct; a guessed one is wrong.

Ask the user only when unsure about substance: what the change does, the title scope, or contradictory
information. Missing fill-in facts are not a reason to ask.

## Title

`type(Scope/Subscope): short description` — imperative, max 72 characters. Types: `feat`, `fix`,
`refactor`, `style`, `docs`, `test`, `chore`. Scopes: `Core`, `Scripts`, `DB`, `Tools`, `Docs`, `Ops`.

## Body

Fill in `pull_request_template.md`:

- Strip the instructional `<!-- -->` comments; keep the testing footer.
- Describe what the change does and why.
- Check Changes Proposed from the diff paths: `src/server/scripts/` → Scripts; `data/sql/` → Database;
  other `src/` → Core; `tools/` → Tools; `runbook/`/`specs/` → Docs.
- AI disclosure: always tick it; name the agent/model and state whether AI produced the changes or
  only the description.
- Issues, SOURCE, Tests Performed, How to Test, Known Issues: stated facts only.

## Output

Print exactly:

```text
TITLE: <title>

PR DESCRIPTION:
```markdown
<body>
```
```

Remarks go below the block after a `----` line.

## Constraints

- Never create the PR, push, commit, or run a state-changing git command.
- Never include secrets, player data, internal hostnames, or production values.
- Do not claim a test that was not run.

## References

- [pull_request_template.md](../../../pull_request_template.md)
- [CONTRIBUTING.md](../../../CONTRIBUTING.md#commits-and-pull-requests)
