# GM API

HTTP API inside `worldserver`. It serves read endpoints and, when explicitly enabled, audited write
endpoints. The future server website calls it through a BFF; no in-repo web UI is built.

## When to use

Testing the API, wiring the future website BFF, or checking that HMAC authentication, RBAC, and audit
work.

## Config

Add to `worldserver.conf` (local or test only):

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

- `GmApi.Secret` is required, at least 32 characters. Empty or short secrets stop the API.
- `GmApi.NonceTtl` must be at least `2 * GmApi.MaxClockSkew`.
- `GmApi.AllowWrites` defaults to `0`. Keep it off until the BFF and the actor mapping are ready.
- Bind loopback or a private VPN address. Never expose it publicly.
- The secret is a credential. Keep it out of the repository, logs, and chat.
- Restart `worldserver` after changing the config.

## Endpoints

Wire contract: [`specs/gm-api.openapi.yaml`](../../specs/gm-api.openapi.yaml). This table is a
summary; the YAML is authoritative for bodies, parameters, and error codes.

| Method | Target | Permission | Returns |
|--------|--------|------------|---------|
| GET | `/api/v1/status` | none | `{"status":"ok"}` |
| GET | `/api/v1/audit?limit=50` | none | recent `gm_audit_log` rows, limit 1–200 |
| POST | `/api/v1/players/<name>/kick` | `RBAC_PERM_COMMAND_KICK` (510) | `{"status":"ok"}` |
| POST | `/api/v1/players/<name>/unstuck` | `RBAC_PERM_COMMAND_UNSTUCK` (534) | `{"status":"ok"}` |

Writes require `GmApi.AllowWrites = 1`, a signed `X-GM-Actor`, and the permission above. The actor
account must exist and have security above `SEC_PLAYER`. A write refuses to target the actor's own
account or a session with security at or above the actor's. Actions run on the world thread and call
game logic; the API does not write game tables directly.

Not built: item grant, mail, ban, RBAC, server control.

## Signing

Canonical string:

```text
<timestamp>\n<nonce>\n<METHOD>\n<target>
```

When `X-GM-Actor` is present, the actor is appended as one more line:

```text
<timestamp>\n<nonce>\n<METHOD>\n<target>\n<actor>
```

`target` includes the query string, for example `/api/v1/audit?limit=10`.

Headers:

```text
X-GM-Timestamp: <unix seconds>
X-GM-Nonce: <random, 8-128 chars>
X-GM-Signature: <hex HMAC-SHA256(secret, canonical)>
X-GM-Actor: <numeric game account id>   # required on writes
```

The server accepts a signature in upper or lower hex.

## Test

```bash
SECRET='<shared-secret>'
TS=$(date +%s)
NONCE=$(openssl rand -hex 16)
TARGET='/api/v1/status'
SIG=$(printf '%s\n%s\nGET\n%s' "$TS" "$NONCE" "$TARGET" \
  | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $2}')

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

Audit:

```text
TARGET='/api/v1/audit?limit=10'
```

Write:

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

Reusing the same nonce returns `409`.

## Errors

| Status | Meaning |
|--------|---------|
| `401` | missing header, bad signature, timestamp outside the skew window, or unknown actor |
| `403` | writes disabled, actor is a player account, permission denied, or target security too high |
| `404` | unknown target or invalid name (`not_found`), or player offline (`target_not_found`) |
| `405` | wrong method for a known target |
| `409` | nonce already seen (replay), self-target, or player busy (in flight or in combat) |
| `429` | more than `GmApi.RateLimit` requests per minute from one address |
| `500` | pending audit row could not be written (action not run), or outcome row failed after it ran |
| `503` | world thread did not process the write within 5 seconds, or is shutting down |

## Audit

Each authenticated write that passes RBAC inserts a `pending` `acore_auth.gm_audit_log` row before it
is dispatched. The action then runs and a second row records the outcome: `success`,
`target_not_found`, `player_busy`, `forbidden_target_security`, `cannot_target_self`,
`teleport_failed`, `world_unavailable`, or `world_timeout`. A denied write inserts one `denied` row.
Requests rejected before actor resolution (`writes_disabled`, missing or unknown actor) are not
audited.

- `command`: `api.kick` or `api.unstuck`
- `account_id`, `account_name`: the actor from `X-GM-Actor`
- `player_name`, `player_guid`: the target when it was resolved
- `arguments`: the requested player name
- `result`: `pending`, `denied`, or one of the outcome values above

If the pending insert fails, the API returns `500` and does not run the action. If the outcome insert
fails, the API returns `500` and logs `module.gm-api`; the action has already run and the `pending`
row remains. A timed-out write is cancelled before it starts when possible; if it already started,
its outcome row follows the `world_timeout` row. Command-hook rows still record the attempt before
execution.

## Security notes

- HMAC is computed over the exact target, so query parameters are covered.
- `X-GM-Actor` is signed, so the BFF cannot change the actor without the secret.
- Nonces are stored in memory until `GmApi.NonceTtl` expires.
- The server is single-threaded; a write blocks the API for up to 5 seconds while the world thread
  runs it. Keep concurrency low.
- The audit query, actor resolution, and RBAC checks use the shared synchronous login pool. A stalled
  login database can delay the API thread and, during shutdown, the server join. A dedicated
  connection is a future change.
- API audit writes also use that synchronous login pool, from the world thread. A stalled or dead
  login database blocks the world tick, not only the API. This matches the command audit hook's
  behavior; keep the auth database healthy and monitor `Errors.log`.
- The future website BFF shares one source address; all admin-dashboard users share one rate-limit
  bucket. Raise the limit or add caller identity before the website goes live.
- No CORS by design. The future website BFF calls the API server-side; browsers do not call it
  directly.
- A write that returns `503` is cancelled before it starts when possible; if it already started it
  may still complete. Do not retry blindly. Check the audit rows and the target's state first.
- Reads keep one shared HMAC secret. Writes add the signed actor, RBAC, and audit; they are still
  gated by the same shared secret, so protect it like a service credential.
- Audit search is newest-N only. Add filters, cursor paging, and indexes before the website audit page.

## References

- [audit.md](audit.md)
- [rbac-roles.md](rbac-roles.md)
- [modules/mod-gm-api/README.md](../../modules/mod-gm-api/README.md)
- [specs/gm-tools.md](../../specs/gm-tools.md)
