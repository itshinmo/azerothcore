---
name: research-implementations
description: Use when asked to implement a feature or mechanic for the project — before writing code, research how retail, Ascension-class servers, other emulators, and published modules already solve it; report findings and gaps to the owner, then plan with those findings.
---

# research-implementations

## Prerequisites

Know the stack first: the vendored modules in `modules/`, the server hooks they use, and what
the client bundle already carries (`runbook/operation/client-bundle.md`). A mechanic our client
cannot render cannot be implemented server-side alone.

## Workflow

1. **State the mechanic in one sentence.** If it cannot be stated, ask the owner first.
2. **Research retail behavior** — warcraft.wiki.gg, Blizzard support articles, patch notes. Note
   the exact rules and the patch that changed them.
3. **Research at least two private-server implementations** — Ascension-class servers (their
   wikis/guides describe player-facing mechanics), other emulator forks' modules (GitHub, forum
   threads), and any module we already vendor. Note the exact mechanics: triggers, data model,
   edge cases, restrictions, and anything player-visible.
4. **Report to the owner** in one block: who does it, how, coverage, gaps, and what fits our
   stack (our client bundle, our module layout, our ADRs). Cite sources.
5. **Plan with the findings**: options become concrete; an implementation nobody has solved is
   named as original work. Owner decisions are recorded in the feature's ADR.
6. **Cite, don't paste**: read others' code for mechanics, never copy code without the vendoring
   rules (license, attribution, git-repo removal — see ADR-020).
