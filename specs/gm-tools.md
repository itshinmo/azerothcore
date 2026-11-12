# GM tools

> Status: phase 4 in progress. RBAC role presets are tracked in
> `data/sql/custom/db_auth/gm_rbac_presets.sql`; the command audit module is in
> `modules/mod-gm-audit`; the command index is in `runbook/gm/command-index.md`. The panel and addon
> are not built yet; this spec is the contract for when they land.

## Purpose

Improve the quality and safety of human GM work: findable commands, least-privilege roles, auditable
actions, a web panel, and an in-game addon.

## Scope

- GM command handbook.
- RBAC role presets.
- GM audit.
- Web GM panel and its server API.
- In-game GM addon.

## Boundary

Owns the GM workflow and tooling. Does not own the game commands themselves; they remain in
`src/server/scripts/Commands/` and the RBAC system. Does not own database clients.

## Contract

### Command handbook

- Location: `runbook/gm/command-handbook.md`.
- Each entry: command, syntax, permission constant, danger level, side effects, examples, related
  commands.
- Generated index from `src/server/scripts/Commands/cs_*.cpp` plus curated entries for the top
  workflows. Regenerate with `make command-index`; `make verify-docs` fails when it is stale.
- In-game `.help <command>` remains authoritative for exact argument syntax.

### RBAC roles

| Role | Intended use | Must not |
|------|--------------|----------|
| `support` | lookup, unstuck, mute | grant items, ban, RBAC |
| `content-tester` | teleport, GM mode, temporary spawn, instance inspect | economy grants, bans |
| `economy` | item/mail grants, refunds | bans, RBAC, server control |
| `admin` | bans, RBAC, server commands | — |
| `superadmin` | named human only | shared/service accounts |

- Roles are permission sets, not `gmlevel` aliases.
- Changes are tracked SQL in `data/sql/custom/db_auth/`; presets live in
  `gm_rbac_presets.sql` and are documented in [runbook/gm/rbac-roles.md](../runbook/gm/rbac-roles.md).
- Test each role with a dedicated account on the test realm.

### Audit

- `modules/mod-gm-audit` implements `AllCommandScript::OnTryExecuteCommand`.
- Records actor account, player, command, redacted arguments, and timestamp in
  `acore_auth.gm_audit_log`.
- The command hook records attempts before execution; `result` is `NULL` until a panel or a future
  post-execute hook writes an outcome.
- Password-bearing command forms are redacted. A non-fatal audit write failure aborts the command;
  schema errors are fatal by core policy.
- Panel actions record the outcome directly.
- High/critical actions additionally record before/after state where practical.
- Logs go to a dedicated table or structured file, never to a public channel.
- Procedure and queries: [runbook/gm/audit.md](../runbook/gm/audit.md).

### Web GM panel

- Frontend: `tools/gm-panel/`, Node 26 + vanilla UI, same security model as the panel API.
- Backend: `modules/mod-gm-api/` inside `worldserver`.
- Transport: HTTP on localhost or a private VPN interface; HMAC-signed requests with a nonce and
  timestamp; replay window; rate limit.
- Endpoints are read-only first: account, character, online players, instance info, audit.
- Safe writes: item grant, mail, unstuck, kick.
- Admin writes: ban, RBAC, server control. Human approval required.
- Every endpoint validates input and calls game logic; no direct SQL writes.

### In-game addon

- Location: `tools/gm-addon/`.
- Lua addon with a menu and slash commands; wraps existing commands.
- Does not bypass RBAC; the server remains the gate.
- Install docs for the 3.3.5a client `Interface/AddOns/`.

## Errors and edge cases

- HMAC mismatch or expired timestamp: 401, no detail.
- Replayed nonce: 409.
- Permission denied: 403.
- Target offline: mail or queue where the action supports it; otherwise a clear error.
- Partial failure: report the step and the state; never retry a write blindly.
- Audit write failure: abort the action.

## Security

- Least privilege.
- No direct DB writes from the panel.
- No secrets in the addon or frontend.
- Localhost/VPN only.
- Panel approvals and audit are mandatory for high/critical actions.

## Observability

- Audit table/file.
- Structured API log with request id, actor, endpoint, status, duration; no secrets.
- In-game command audit.

## Test plan

- Unit: HMAC, nonce/replay, input validation, role checks, audit.
- Integration: test realm with each role; read endpoint, safe write, denied write, audit.
- Manual: in-game addon install, command execution, audit review.
- Negative: expired signature, replayed nonce, wrong role, offline target, audit failure.

## References

- [decisions/ADR-005-gm-tools-and-rbac.md](../decisions/ADR-005-gm-tools-and-rbac.md)
- [runbook/gm/command-handbook.md](../runbook/gm/command-handbook.md)
- [runbook/gm/rbac-roles.md](../runbook/gm/rbac-roles.md)
- [runbook/gm/incident-response.md](../runbook/gm/incident-response.md)
- [specs/security.md](security.md)
