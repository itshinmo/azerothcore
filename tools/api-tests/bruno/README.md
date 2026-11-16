# GM API Bruno collection

Manual test collection for the GM API in `modules/mod-gm-api`. It signs every request with the
HMAC headers the API requires, so no shell signing is needed.

Contract: [`specs/gm-api.openapi.yaml`](../../../specs/gm-api.openapi.yaml). Procedure:
[`runbook/gm/gm-api.md`](../../../runbook/gm/gm-api.md). Decision:
[ADR-014](../../../decisions/ADR-014-bruno-api-test-client.md).

## Install

1. Install the Bruno VS Code extension `bruno-api-client.bruno`, or the Bruno desktop app.
2. Open this directory as a collection (`bruno.json` marks the root).
3. Copy `environments/local.bru.example` to `environments/local.bru` and select the `local`
   environment. The real environment file is ignored by Git.
4. Fill `gmApiSecret` with `GmApi.Secret` from `worldserver.conf`, `gmActor` with a GM account id,
   and `playerName` with an online character name.

Start `worldserver` with `GmApi.Enable = 1` and loopback binding. See the runbook for the full config
and the audit behavior.

## Requests

| Request | Method and target | Notes |
|---------|-------------------|-------|
| Status | `GET /api/v1/status` | Read, no actor needed. Expects `200` and `{"status":"ok"}`. |
| Audit | `GET /api/v1/audit?limit={{auditLimit}}` | Read, newest-N rows. Limit is 1-200. |
| Unstuck | `POST /api/v1/players/{{playerName}}/unstuck` | Write. Same target rules. Runs before Kick so a full run can succeed. |
| Kick | `POST /api/v1/players/{{playerName}}/kick` | Write. Target must be online and below the actor's security. Kicks last. |
| Items | `POST /api/v1/players/{{playerName}}/items` | Write. Grants the item in the JSON body to the online target. |
| Mail | `POST /api/v1/mail` | Write. Text mail with money; the body also accepts `items` attachments. |
| Ban | `POST /api/v1/accounts/{{targetAccount}}/ban` | Tagged `danger`. Bans the account for 60 seconds. |
| Permissions | `POST /api/v1/accounts/{{targetAccount}}/permissions` | Tagged `danger`. Grants permission 488 on the target account. |
| Server cancel | `POST /api/v1/server/control` | Write. Cancels a pending shutdown/restart timer; safe to send. |
| Server shutdown | `POST /api/v1/server/control` | Tagged `danger`. Schedules shutdown in 30 seconds; `make start` afterwards. |
| Account read | `GET /api/v1/accounts/1` | Read. Change the numeric id or use an account name. |
| Character read | `GET /api/v1/characters/{{playerName}}` | Read. |
| Online players | `GET /api/v1/players/online?limit=100` | Read. |
| Instances | `GET /api/v1/instances?limit=100` | Read. |

The Ban and Permissions requests carry the `danger` tag. Run them deliberately, one request at a
time, and do not include them in a full collection run.

Every request carries a `docs` block. Open the **Docs** tab in Bruno to see what the request does,
what it needs, and which outcomes to expect. When you add a request, add its `docs` block in the same
change.

Writes need `GmApi.AllowWrites = 1`. With writes disabled they return `403`. Self-target returns
`409`; an offline target returns `404`; a higher-security target returns `403`.

Each run produces `pending` and outcome rows in `acore_auth.gm_audit_log`. Check them with the Audit
request or the queries in `runbook/gm/audit.md`.

## How signing works

`collection.bru` runs a pre-request script for every request:

1. Build the target from `req.getPath()` and `req.getQueryString()`.
2. Build the canonical string `<timestamp>\n<nonce>\n<METHOD>\n<target>`.
3. For non-GET requests, append `\n<actor>` and send `X-GM-Actor`.
4. Sign with HMAC-SHA256 and set `X-GM-Timestamp`, `X-GM-Nonce`, and `X-GM-Signature`.

The nonce is fresh per request, so collection runs do not trip the replay check. A deliberate replay
test needs the same nonce twice; do that with the curl recipe in the runbook.

## VS Code extension note

The Bruno VS Code extension has a known bug where pre-request scripts may not run and variables may
not interpolate, producing `401` responses. If a request returns `401` in VS Code but succeeds with
the CLI, use the CLI (or the Bruno desktop app) until the extension is fixed.

Reference: usebruno/bruno-vscode issue 73.

## CLI

From this directory:

```bash
npx @usebruno/cli@latest run --env local
```

The CLI uses the same signing script and Safe Mode by default. Keep the target on loopback or a
private address.

## Security

- `environments/local.bru` holds the HMAC secret and is ignored; never commit it or paste it into a
  request.
- Do not point this collection at production. Production writes are human-only and the website, when
  it exists, will use its own BFF.
- Treat a saved response as potentially sensitive: audit rows contain account and player names.
- No test in this collection mutates database tables directly; writes go through the API, RBAC, and
  audit.
