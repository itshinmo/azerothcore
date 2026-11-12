# ADR-005 — GM tools and RBAC

- Status: accepted
- Date: 2026-11-12

## Context

The server has extensive GM commands and 601 RBAC permission constants, but human workflow is weak:
no searchable handbook, broad `gmlevel` accounts, incomplete audit visibility, no out-of-game panel,
and no client addon. GM actions can grant items, ban accounts, and alter state, so every improvement
must reduce risk, not add a new bypass.

## Decision

1. **Handbook.** `runbook/gm/command-handbook.md` with syntax, permission, danger level, side effects,
   examples, and related commands. In-game `.help` remains authoritative for exact syntax.
2. **Least-privilege roles.** `support`, `content-tester`, `economy`, `admin`, `superadmin`, implemented
   as `rbac_*` permission sets in tracked SQL. No shared accounts.
3. **Audit.** `modules/mod-gm-audit` uses `AllCommandScript::OnTryExecuteCommand` to log command
   attempts. Website actions log outcomes directly. High/critical actions record before/after state where
   practical. Audit failure aborts the action.
4. **Web panel.** Superseded by [ADR-010](ADR-010-website-as-visual-interface.md): the future
   server website is the frontend; the backend is `modules/mod-gm-api/` inside `worldserver`.
   HMAC-signed requests with nonce and timestamp, replay window, rate limit, localhost/VPN bind.
   Read-only endpoints first; safe writes next; admin writes last. No direct database writes.
5. **In-game addon.** `tools/gm-addon/` Lua addon wraps existing commands. The server remains the
   permission gate.
6. **No core patch unless necessary.** If a post-execute hook is required, open an RFC for a minimal
   hook. Do not patch `CommandMgr` silently.

## Alternatives considered

- **SOAP.** Built-in, but limited command surface, disabled by default, and a weaker auth model.
- **Direct DB writes from the panel.** Bypasses game logic and risks corrupt state.
- **No web panel.** Handbook and addon only; less convenient for remote support.
- **Broad `gmlevel` roles.** Simple, but violates least privilege.

## Consequences

- More work than broad GM accounts, but actions are attributable and reversible.
- The API adds attack surface and must be localhost/VPN only.
- The addon can be distributed with the client without server changes.
- Audit storage needs retention and access control.

## Amendments

[ADR-009](ADR-009-rbac-command-permission-precedence.md) permits one core patch in the command
loader so RBAC command permissions are not overwritten by legacy `command.security` values.

[ADR-010](ADR-010-website-as-visual-interface.md) makes the future server website the long-term
visual layer and removes the in-repo panel UI.
