# mod-gm-api

HTTP API inside `worldserver` for the future server website BFF and the committed Bruno test
collection (`tools/api-tests/bruno/`).

## Endpoints

Read (valid signature only, no actor, no RBAC):

- `GET /api/v1/status` — `{"status":"ok"}`
- `GET /api/v1/audit?limit=50` — recent `gm_audit_log` rows, limit 1–200
- `GET /api/v1/accounts/<name-or-id>` — `id`, `username`, `security`, `online`
- `GET /api/v1/characters/<name>` — `guid`, `name`, `account_id`, `account_name`, `level`, `race`,
  `class`, `online`
- `GET /api/v1/players/online?limit=100` — online players with map and zone, limit 1–500
- `GET /api/v1/instances?limit=100` — active instances, limit 1–100

Write (requires `GmApi.AllowWrites = 1` and a signed actor):

- `POST /api/v1/players/<name>/items` — needs `RBAC_PERM_COMMAND_ADDITEM` (488)
- `POST /api/v1/mail` — needs `RBAC_PERM_COMMAND_SEND_MAIL` (485), plus
  `RBAC_PERM_COMMAND_SEND_ITEMS` (484) for items and `RBAC_PERM_COMMAND_SEND_MONEY` (487) for money
- `POST /api/v1/accounts/<name>/ban` — needs `RBAC_PERM_COMMAND_BAN_ACCOUNT` (240)
- `POST /api/v1/accounts/<name>/permissions` — needs 203 grant, 204 deny, or 205 revoke
- `POST /api/v1/server/control` — needs `GmApi.AllowServerControl = 1` and 734 shutdown,
  727 restart, or 735 cancel
- `POST /api/v1/players/<name>/kick` — needs `RBAC_PERM_COMMAND_KICK` (510)
- `POST /api/v1/players/<name>/unstuck` — needs `RBAC_PERM_COMMAND_UNSTUCK` (534)

Request bodies are JSON. See `runbook/gm/gm-api.md` and `specs/gm-api.openapi.yaml` for bodies,
limits, and error codes.

## Security

- Localhost bind by default.
- HMAC-SHA256 over `timestamp\nnonce\nMETHOD\ntarget`, with `\nactor` appended when
  `X-GM-Actor` is sent. `target` includes the query string.
- The request body is not signed. Keep the API on loopback or a private channel.
- Headers: `X-GM-Timestamp`, `X-GM-Nonce`, `X-GM-Signature`.
- `X-GM-Actor` is the numeric game account id of the human on whose behalf the BFF calls. It is
  signed, required on writes, and optional on reads.
- The actor account must exist, have security above `SEC_PLAYER`, and hold the endpoint permission.
- Writes run on the world thread. The API waits up to 5 seconds, then returns `503`. The account,
  character, online-player, and instance reads also run on the world thread and can return `503`;
  `/status` and `/audit` answer on the API thread.
- Every authenticated write that passes security and RBAC inserts a `pending` `gm_audit_log` row
  before dispatch and exactly one terminal row after. `command` is one of `api.additem`, `api.mail`,
  `api.ban`, `api.rbac`, `api.server`, `api.kick`, or `api.unstuck`. Requests rejected before actor
  resolution are not audited; an RBAC denial writes a `denied` row. A failed pending insert aborts
  the action; a timeout claims `world_timeout` so the action cannot write a second outcome.
- Kick, unstuck, item grant, and mail refuse the actor's own account or a target with security at or
  above the actor's. Ban and RBAC writes refuse the actor's own account and a target with security
  at or above the actor's.
- Mail validates item templates, `MaxCount`, stack splitting to 12 attachments, and a mailbox count
  below 100.
- Server control is separately gated by `GmApi.AllowServerControl`, defaults to off, and only exits
  the process. A restart needs an external supervisor.
- RBAC changes invalidate an online target's session RBAC cache.
- Timestamp skew and nonce TTL are configurable.
- Replayed nonce returns `409`; bad signature, missing headers, or skew returns `401`.
- Per-IP rate limit: default 120 requests per minute; see `GmApi.RateLimit`.
- No direct SQL writes from clients; actions call game logic.

## Config

Add to `worldserver.conf`:

```text
GmApi.Enable = 1
GmApi.BindAddress = 127.0.0.1
GmApi.Port = 8090
GmApi.Secret = <at-least-32-characters>
GmApi.MaxClockSkew = 60
GmApi.NonceTtl = 120
GmApi.RateLimit = 120
GmApi.AllowWrites = 0
GmApi.AllowServerControl = 0
```

`GmApi.Secret` is required, at least 32 characters. The API does not start otherwise.
`GmApi.AllowWrites` defaults to `0`; enable it only on a local or test stack while testing writes.
`GmApi.AllowServerControl` defaults to `0` and gates shutdown, restart, and cancel.

## Test

The primary manual path is the Bruno collection ([README](../../tools/api-tests/bruno/README.md));
it signs each request. The curl recipe below is the headless fallback.

```bash
SECRET='<shared-secret>'
TS=$(date +%s)
NONCE=$(openssl rand -hex 16)
TARGET='/api/v1/status'
SIG=$(printf '%s\n%s\nGET\n%s' "$TS" "$NONCE" "$TARGET" | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $2}')

curl -s \
  -H "X-GM-Timestamp: $TS" \
  -H "X-GM-Nonce: $NONCE" \
  -H "X-GM-Signature: $SIG" \
  "http://127.0.0.1:8090$TARGET"
```

Expected:

```json
{"status":"ok"}
```

For the audit endpoint, sign the exact target including the query:

```text
TARGET='/api/v1/audit?limit=10'
```

Write example (actor account id is part of the signature):

```bash
TARGET='/api/v1/players/Thrall/kick'
ACTOR=1
SIG=$(printf '%s\n%s\nPOST\n%s\n%s' "$TS" "$NONCE" "$TARGET" "$ACTOR" \
  | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $2}')

curl -s -X POST \
  -H "X-GM-Timestamp: $TS" \
  -H "X-GM-Nonce: $NONCE" \
  -H "X-GM-Signature: $SIG" \
  -H "X-GM-Actor: $ACTOR" \
  "http://127.0.0.1:8090$TARGET"
```

Reuse the same nonce twice; the second request must return `409`.
