# ADR-010 — Server website as the long-term visual interface

- Status: accepted
- Date: 2026-11-13
- Amends: [ADR-005](ADR-005-gm-tools-and-rbac.md)

## Context

GMs need visual workflows. DBeaver solved database browsing, and a temporary local GM panel proved the
read-only API and HMAC model. Maintaining one-off UIs beside the CLI repeats work and creates multiple
security surfaces.

The project will have a server website. It is the natural home for account pages, server status, GM
tools, and future player services.

## Decision

1. The future server website is the long-term visual layer.
2. Every server or GM feature is API-first. Build the command/API path, contract, RBAC checks, and
   audit before any visual client.
3. Do not add one-off in-repo web UIs while the website is pending. The current local panel is removed;
   `modules/mod-gm-api` and its contract remain.
4. Browser architecture: browser -> website BFF -> GM API -> `worldserver`.
   - The browser never receives the GM API HMAC secret.
   - Only the admin BFF holds the secret. The public site does not.
   - The BFF calls the GM API over loopback, a private network, or TLS; never over plain HTTP
     across an untrusted network.
   - No direct database writes from the website or BFF.
5. Web auth is separate from game auth.
   - The game `account` table stores an SRP6 salt and verifier, not a web password hash.
   - The website uses its own identity: passkeys, OAuth, or an Argon2id password hash, linked to the
     game account.
   - MFA or re-authentication is required for destructive actions.
   - The website never reuses game session keys.
6. Public site, account/identity, and the GM dashboard are separate security zones. The GM dashboard
   is behind VPN/SSO or a separate admin origin. Public and admin sessions are not shared.
7. Server-side authorization is mandatory. The current read-only API has one shared HMAC secret and
   no caller identity. Before write endpoints ship, the API must accept a signed actor/service
   identity and enforce the linked account's RBAC roles plus audit. A website login alone grants no
   GM rights.
8. Visuals use basic HTML/CSS/JS first. No SPA framework unless a demonstrated need appears.
9. Runtime choice for the website is separate from the current tooling. New local JavaScript servers
   may use Bun after a pinned pilot; existing Node tooling stays until a deliberate migration.

## Alternatives considered

- **Keep the local GM panel.** Immediate value, but a second UI and no long-term home. Rejected as the
  primary direction; the API is kept instead.
- **Reuse game SRP6 for web login.** Requires a browser SRP6 implementation and couples web sessions
  to game auth. Rejected.
- **Public site and GM dashboard on one origin.** Simpler deployment, weaker isolation. Rejected.
- **Direct database access from the website.** Faster, but bypasses game logic, RBAC, and audit.
  Rejected.

## Consequences

- No visual GM features until the website starts. CLI and the GM API remain usable.
- The GM API is the stable contract; the removed panel is not.
- Website work must include identity, sessions, CSRF, RBAC, audit, and admin-zone isolation.
- Every future feature needs an API contract and tests before its website page.
