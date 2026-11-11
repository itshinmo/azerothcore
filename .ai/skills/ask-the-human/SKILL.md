---
name: ask-the-human
description: Use when an open question, ambiguous requirement, missing contract, or decision that is not yours blocks progress. Asks with concrete options and a recommendation instead of guessing.
---

# ask-the-human

## Prerequisites

Look it up first, in this order: code/config, `specs/`, `decisions/`, `runbook/`, `.ai/memories/`.
Ask only what they cannot answer.

## Workflow

1. **Decide whether to ask.**
   - Ask when the spec is missing or ambiguous; code and spec disagree; two valid designs have
     different consequences; scope or acceptance criteria are unclear; an action is hard to reverse
     or outward-facing; work belongs to someone else.
   - Do not ask when the repository answers it, a convention gives an obvious default, or it is a
     permission ping already covered by the approval gate.
2. **Collect first.** Gather every open question and ask them in one batch. Ask blocking questions
   first; do not drop the rest.
3. **Shape each question.** One decision, self-contained, ending in `?`, short header. A few mutually
   exclusive options. Each option has a short label and a concrete consequence. Recommend an option
   only when a spec, ADR, convention, or the code favors it; cite the source. Otherwise recommend
   nothing.
4. **Ask through the host's structured-question tool.** The user's language is respected; technical
   terms stay verbatim. If the host has no such tool, print a numbered list with lettered options and
   stop.
5. **Act on the answer.** Apply it and record where it belongs: behavior in `specs/`, a decision in
   `decisions/`, a procedure in `runbook/`, in-flight context in a working memory. A deferred item
   becomes `<!-- TODO -->`, never a guess.

## Constraints

- An answer is not an approval. It does not replace human review or the reviewer agent.
- One round of questions; do not ask the same question twice.
- No secrets, credentials, hostnames, or player data in questions or options.
- Show exact outward-facing text before posting anything.

## Expected output

The answers applied, and a short list: question, answer, where recorded. Open items listed as TODOs.

## References

- [AGENTS.md](../../../AGENTS.md#approval-gate)
- [.ai/README.md](../../README.md)
