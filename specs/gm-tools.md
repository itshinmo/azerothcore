# GM tools

> Status: phase 4 complete for the current scope; phase 5 resumed for the GM API. RBAC role presets,
> the command audit module, the command index, the GM API (read endpoints, the audited write set, the
> request log, and filtered audit paging), and the in-game addon are built. The long-term visual
> layer is the future server website ([ADR-010](../decisions/ADR-010-website-as-visual-interface.md)),
> now sequenced after production ([ADR-013](../decisions/ADR-013-server-and-client-before-website.md));
> no in-repo web UI. Manual API testing uses the Bruno collection
> ([ADR-014](../decisions/ADR-014-bruno-api-test-client.md)).

## Purpose

Improve the quality and safety of human GM work: findable commands, least-privilege roles, auditable
actions, a server website, and an in-game addon.

## Scope

- GM command handbook.
- RBAC role presets.
- GM audit.
- Server website (future, Phase 3) and its GM API.
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
- The command hook records attempts before execution; `result` is `NULL` for command-hook rows.
- Password-bearing command forms are redacted. A non-fatal audit write failure aborts the command;
  schema errors are fatal by core policy.
- GM API write endpoints insert a `pending` row before dispatch and an outcome row after:
  `command` is `api.kick` or `api.unstuck`, and `result` is `success`, `denied`, `target_not_found`,
  `player_busy`, `forbidden_target_security`, `cannot_target_self`, `teleport_failed`,
  `world_unavailable`, or `world_timeout`. A failed pending insert aborts the action; a failed
  outcome insert returns `500` and logs the error after the action ran.
- High/critical actions additionally record before/after state where practical.
- Logs go to a dedicated table or structured file, never to a public channel.
- Procedure and queries: [runbook/gm/audit.md](../runbook/gm/audit.md).

### GM API and website (website future)

- Long-term visual layer: the server website, built in Phase 3 after the base game and custom content
  ([ADR-013](../decisions/ADR-013-server-and-client-before-website.md)). No in-repo web UI exists now;
  see [ADR-010](../decisions/ADR-010-website-as-visual-interface.md).
- Backend: `modules/mod-gm-api/` inside `worldserver`. Read endpoints and the audited write set are
  built. API work does not wait for the website.
- Browser architecture: browser -> admin website BFF -> GM API. Only the admin BFF holds the API
  secret; the public BFF and browser never see it. The website uses its own web identity, not the game SRP6 session.
- Transport: HTTP on localhost or a private VPN interface; HMAC-signed requests with a nonce and
  timestamp; replay window; per-address rate limit.
- Implemented read endpoints: server status, audit rows, account, character, online players, active
  instances. Implemented writes: item grant, mail, account ban, account permission grant/deny/revoke,
  server control, kick, and unstuck. All writes are gated by `GmApi.AllowWrites`, a signed
  `X-GM-Actor` game account id, RBAC, and audit; server control also requires
  `GmApi.AllowServerControl`.
- Live error branches are exercised through the committed Bruno collection on a live stack; the cheap
  branches (`writes_disabled`, `rate_limited`, `audit_failed`) are reachable with the same collection
  or the curl recipe.
- Every endpoint validates input and calls game logic; no endpoint writes game tables directly. The
  module writes its own audit rows.
- Wire contract: [gm-api.openapi.yaml](gm-api.openapi.yaml).
- Procedure: [runbook/gm/gm-api.md](../runbook/gm/gm-api.md).

### In-game addon

- Location: `tools/gm-addon/`. Built; wraps existing commands only.
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
- No direct DB writes from the website.
- No secrets in the addon or frontend.
- Localhost/VPN only.
- Website approvals and audit are mandatory for high/critical actions.

## Observability

- Audit table/file.
- One structured API request log line per request: method, target, status, duration, actor, remote
  address. Bodies, signatures, nonces, and the secret are excluded.
- In-game command audit.

## Test plan

- Unit: HMAC canonicalization/signature (with and without actor), actor validation, player target
  parsing, timestamp window, nonce length, limit parsing, audit query filters and cursor, request
  body parsers and their limits.
- Manual API: Bruno collection (`tools/api-tests/bruno/`) plus the curl recipe for skew, nonce
  replay, rate limit, input validation, actor missing/unknown, RBAC denial, target offline,
  self-target, busy target.
- Integration: test realm with each role; read endpoint, kick/unstuck write, denied write, audit row
  with the outcome.
- Manual: in-game addon install, command execution, audit review.
- Negative: expired signature, replayed nonce, wrong role, offline target, audit failure.

## References

- [decisions/ADR-005-gm-tools-and-rbac.md](../decisions/ADR-005-gm-tools-and-rbac.md)
- [decisions/ADR-013-server-and-client-before-website.md](../decisions/ADR-013-server-and-client-before-website.md)
- [decisions/ADR-014-bruno-api-test-client.md](../decisions/ADR-014-bruno-api-test-client.md)
- [runbook/gm/command-handbook.md](../runbook/gm/command-handbook.md)
- [runbook/gm/rbac-roles.md](../runbook/gm/rbac-roles.md)
- [runbook/gm/incident-response.md](../runbook/gm/incident-response.md)
- [specs/security.md](security.md)
