# ADR-014 — Bruno is the manual GM API test client

- Status: accepted
- Date: 2026-11-16
- Related: [ADR-005](ADR-005-gm-tools-and-rbac.md),
  [ADR-013](ADR-013-server-and-client-before-website.md)

## Context

GM API manual checks used shell `curl` recipes in `runbook/gm/gm-api.md`. The human operator finds
repeated shell signing impractical, so audited writes were postponed until a website dashboard
existed. That postponed server work behind a visual layer that ADR-013 now defers.

Bruno is an open-source, local-first API client. Collections are plain-text files in the repository,
a VS Code extension runs the same collection inside the editor, and pre-request JavaScript can sign
each request with the HMAC headers the GM API requires. It supports environments, assertions, and a
CLI runner.

## Decision

1. `tools/api-tests/bruno/` is the primary manual test path for the GM API on local and test stacks.
2. The collection is committed. Secrets are not. The local environment file is ignored and an
   example is committed; the HMAC secret never enters the repository, logs, or chat.
3. `curl` recipes stay in the runbook as the headless fallback and for reproducing failures without
   an editor.
4. Bruno is a test client, not a BFF. It talks to loopback or a private address only, holds no
   production credential, and is never exposed to players.
5. Bruno does not replace automated coverage. Unit tests stay the gate for signing and validation;
   the collection covers manual and exploratory checks and can later run in CI through the Bruno
   CLI.
6. The collection follows `specs/gm-api.openapi.yaml`. When an endpoint or header changes, both the
   contract and the collection change in the same review.

## Alternatives considered

- **Postman or Insomnia desktop clients.** Heavier, account-oriented, and collections are not
  plain-text by default. Rejected.
- **Keep curl only.** Blocks the human operator and keeps writes untested. Rejected.
- **Build a local GM panel for testing.** ADR-010 already rejected a second UI and a second security
  surface. Rejected.

## Consequences

- GM API writes and error branches are testable before the website exists.
- One ignored local file holds the secret; the committed example and README explain setup.
- The collection is a maintained artifact: endpoint changes must update it with the contract.
- No visual layer for players or GMs is added to the repository.
