# mod-gm-api

HTTP API inside `worldserver` for the future server website BFF.

## Endpoints

Read:

- `GET /api/v1/status` — `{"status":"ok"}`
- `GET /api/v1/audit?limit=50` — recent `gm_audit_log` rows, limit 1–200

Write (requires `GmApi.AllowWrites = 1` and a signed actor):

- `POST /api/v1/players/<name>/kick` — needs `RBAC_PERM_COMMAND_KICK` (510)
- `POST /api/v1/players/<name>/unstuck` — needs `RBAC_PERM_COMMAND_UNSTUCK` (534)

## Security

- Localhost bind by default.
- HMAC-SHA256 over `timestamp\nnonce\nMETHOD\ntarget`, with `\nactor` appended when
  `X-GM-Actor` is sent. `target` includes the query string.
- Headers: `X-GM-Timestamp`, `X-GM-Nonce`, `X-GM-Signature`.
- `X-GM-Actor` is the numeric game account id of the human on whose behalf the BFF calls. It is
  signed, required on writes, and optional on reads.
- The actor account must exist, have security above `SEC_PLAYER`, and hold the endpoint permission.
- Writes run on the world thread. The API waits up to 5 seconds, then returns `503`.
- Every authenticated write that passes RBAC inserts a `pending` `gm_audit_log` row before dispatch
  and an outcome row after: `command` is `api.kick` or `api.unstuck`, `result` is `success`, `denied`,
  `target_not_found`, `player_busy`, `forbidden_target_security`, `cannot_target_self`,
  `teleport_failed`, `world_unavailable`, or `world_timeout`. Requests rejected before actor
  resolution are not audited. A failed pending insert aborts the action.
- A write refuses to target the actor's own account or a session with security at or above the
  actor's.
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
```

`GmApi.Secret` is required, at least 32 characters. The API does not start otherwise.
`GmApi.AllowWrites` defaults to `0`; keep it off unless the BFF and the actor mapping are ready.

## Test

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
