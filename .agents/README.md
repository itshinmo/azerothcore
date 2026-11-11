# .agents

Upstream AzerothCore task-scoped coding docs, plus pointer adapters to the project agent layer.

- `docs/` — task-scoped coding rules (`build.md`, `cpp-guidelines.md`, `cpp-scripts.md`,
  `sql-guidelines.md`, `code-review.md`, `self-review-rules.md`, `e2e-policy.md`).
- `skills/` — symlink to `../.ai/skills` (project skills).
- `plans/` — per-task planning docs, gitignored.

Project-level knowledge lives in `.ai/`, `specs/`, `decisions/`, `rfcs/`, and `runbook/`. `AGENTS.md`
is the entry point and routes to both layers. Do not duplicate a project contract here.

## Hooking up your agent

- **Claude Code** — reads `CLAUDE.md`, which imports `AGENTS.md`. Agents and skills are exposed by
  relative symlinks: `.claude/agents -> ../.ai/agents`, `.claude/skills -> ../.ai/skills`.
- **OpenCode** — `.opencode/agents -> ../.ai/agents`, `.opencode/skills -> ../.ai/skills`.
- **GitHub Copilot** — reads `AGENTS.md` natively. Code review also reads
  `.github/copilot-instructions.md`; custom agent profiles live in `.github/agents/`.
- **Any other agent** — point it at `AGENTS.md` through its own entry file (`GEMINI.md`,
  `.cursorrules`, …), using that agent's include syntax or, where includes are unsupported, a line
  telling it to read `AGENTS.md` first.

An adapter never holds content. To add a skill, create it in `.ai/skills/<name>/SKILL.md` and add it
to the index in `.ai/README.md`; the symlinks expose it to every tool. Docs need no symlinks;
`AGENTS.md` references them by path.

On Windows, symlinks need `git config core.symlinks true` plus Developer Mode or an elevated shell;
without them git checks the links out as plain text files.

The upstream skills this repository started from build on
[agent-toolkit](https://github.com/eai-org/agent-toolkit/), invoking them when available. Installing
the toolkit at user level is recommended for upstream-style self-review and conversation skills.
