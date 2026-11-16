# GM API

HTTP API inside `worldserver`. It serves read endpoints and, when explicitly enabled, audited write
endpoints. The future server website calls it through a BFF in Phase 3
([ADR-013](../../decisions/ADR-013-server-and-client-before-website.md)); no in-repo web UI is built.

## When to use

Testing the API with the Bruno collection, reproducing a failure with curl, wiring the future
website BFF, or checking that HMAC authentication, RBAC, and audit work.

## Working with the API

The browser never calls the API. The admin BFF holds the secret and calls the API over loopback or a
private network.

1. Enable the API and set a secret in `worldserver.conf`. Restart `worldserver`.
2. Pick the actor: a game account with security above `SEC_PLAYER` and the endpoint permission.
   The actor is sent as `X-GM-Actor` and is part of the signature.
3. Sign the request. The canonical string is the timestamp, nonce, method, exact target, and the
   actor on writes. `target` includes the query string.
4. Send the request. Check the status and error code.
5. Check `acore_auth.gm_audit_log` for the pending and outcome rows.

Write requests go through the same gate: writes enabled, signed actor, actor security above
`SEC_PLAYER`, RBAC permission, `pending` audit row, world-thread action, outcome row. The HTTP thread
waits up to 5 seconds for the world thread. A timeout returns `503`; do not retry blindly.

Reads need only a valid signature and headers. The account, character, online-player, and instance
reads run on the world thread, so a stalled world thread returns `503`. `/status` and `/audit` answer
on the API thread. Reads do not require `X-GM-Actor` and do not write audit rows.

The HMAC covers the method, target, query string, and actor. It does not cover the request body.
Keep the channel private: loopback, a private VPN, or TLS at the BFF. A caller with the secret can
send any body for a signed target.

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
GmApi.AllowServerControl = 0
```

- `GmApi.Secret` is required, at least 32 characters. Empty or short secrets stop the API.
- `GmApi.NonceTtl` must be at least `2 * GmApi.MaxClockSkew`.
- `GmApi.AllowWrites` defaults to `0`. Keep it off for read-only checks. Enable it only on a local or
  test stack while testing writes.
- `GmApi.AllowServerControl` defaults to `0`. It gates shutdown, restart, and cancel even when writes
  are enabled. A restart exits the process; an external supervisor must start it again.
- Bind loopback or a private VPN address. Never expose it publicly.
- The local and test realm configs both default to `GmApi.Port = 8090`. Start only one stack, or give
  one config a different port. Otherwise the second worldserver logs `Could not bind GmApi` and its
  API is unreachable while the other stack answers.
- The secret is a credential. Keep it out of the repository, logs, and chat.
- Restart `worldserver` after changing the config.

## Endpoints

Wire contract: [`specs/gm-api.openapi.yaml`](../../specs/gm-api.openapi.yaml). This table is a
summary; the YAML is authoritative for bodies, parameters, and error codes.

| Method | Target | Permission | Returns |
|--------|--------|------------|---------|
| GET | `/api/v1/status` | none | `{"status":"ok"}` |
| GET | `/api/v1/audit?limit=50` | none | recent `gm_audit_log` rows; `limit` defaults to 50, values above 200 clamp to 200 |
| GET | `/api/v1/accounts/<name-or-id>` | none | account object |
| GET | `/api/v1/characters/<name>` | none | character object |
| GET | `/api/v1/players/online?limit=100` | none | online player array; `limit` defaults to 100, values above 500 clamp to 500 |
| GET | `/api/v1/instances?limit=100` | none | active instance array; `limit` defaults to 100 and clamps to 100 |
| POST | `/api/v1/players/<name>/items` | `RBAC_PERM_COMMAND_ADDITEM` (488) | `{"status":"ok"}`; body `{"itemId","count"}`, count 1-1000 |
| POST | `/api/v1/mail` | 485, plus 484 for items and 487 for money | `{"status":"ok"}`; body `recipient`, optional `subject` (max 64), `text` (max 5000), `money` (copper), `items` (max 12 after splitting) |
| POST | `/api/v1/accounts/<name>/ban` | `RBAC_PERM_COMMAND_BAN_ACCOUNT` (240) | `{"status":"ok"}`; body `durationSeconds` 0-315360000 (`0` permanent), optional `reason` (max 255) |
| POST | `/api/v1/accounts/<name>/permissions` | 203 grant, 204 deny, 205 revoke | `{"status":"ok"}`; body `action`, `permissionId`, optional `realmId` (current realm id or `-1`) |
| POST | `/api/v1/server/control` | 734 shutdown, 727 restart, 735 cancel | `{"status":"ok"}`; body `action` `shutdown`/`restart` (needs `delaySeconds` 1-3600) or `cancel` |
| POST | `/api/v1/players/<name>/kick` | `RBAC_PERM_COMMAND_KICK` (510) | `{"status":"ok"}` |
| POST | `/api/v1/players/<name>/unstuck` | `RBAC_PERM_COMMAND_UNSTUCK` (534) | `{"status":"ok"}` |

Writes require `GmApi.AllowWrites = 1`, a signed `X-GM-Actor`, and the permission above. Server
control also requires `GmApi.AllowServerControl = 1`. The actor account must exist and have security
above `SEC_PLAYER`. Kick, unstuck, item grant, and mail refuse to target the actor's own account or a
target with security at or above the actor's. Actions run on the world thread and call game logic; the
API does not write game tables directly.

## Bruno collection

[`tools/api-tests/bruno/`](../../tools/api-tests/bruno/README.md) is the primary manual test path. It
signs every request with `collection.bru`, so no shell signing is needed.

1. Install the Bruno VS Code extension `bruno-api-client.bruno` or the desktop app.
2. Copy `environments/local.bru.example` to `environments/local.bru`; the real file is ignored.
3. Set `gmApiSecret` to `GmApi.Secret`, `gmActor` to a GM account id, and `playerName` to an online
   character.
4. Open the collection, select the `local` environment, and send Status or Audit for reads. For
   writes, set `GmApi.AllowWrites = 1` and restart `worldserver`.

Every request in the collection carries a `docs` block; open the **Docs** tab to see what the
request does and which outcomes to expect. When you add an endpoint, add its request and its `docs`
block in the same change.

The collection holds no secret. Never commit `local.bru`, paste the secret into a request, or point
the collection at production. It runs in Safe Mode; no Developer Mode or external package is needed.

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

## Test with curl

Use this headless fallback when Bruno is unavailable or to replay a nonce deliberately.

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

Write example (the actor is part of the signature):

```bash
TARGET='/api/v1/players/Thrall/items'
ACTOR=1
BODY='{"itemId":19019,"count":1}'
SIG=$(printf '%s\n%s\nPOST\n%s\n%s' "$TS" "$NONCE" "$TARGET" "$ACTOR" \
  | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $2}')

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-GM-Timestamp: $TS" \
  -H "X-GM-Nonce: $NONCE" \
  -H "X-GM-Signature: $SIG" \
  -H "X-GM-Actor: $ACTOR" \
  -d "$BODY" \
  "http://127.0.0.1:8090$TARGET"
```

Reusing the same nonce returns `409`. Use a fresh nonce and timestamp for every request.

Mail:

```json
{
  "recipient": "Thrall",
  "subject": "Compensation",
  "text": "Sorry for the downtime.",
  "money": 10000,
  "items": [{"itemId": 19019, "count": 2}]
}
```

Ban (duration `0` is permanent; the reason is not copied into the audit arguments):

```json
{"durationSeconds": 86400, "reason": "Exploit abuse"}
```

Permission (realm `-1` is all realms; the current realm id is also accepted; `0` and other ids are
rejected):

```json
{"action": "grant", "permissionId": 488, "realmId": -1}
```

Server control (`delaySeconds` is required for shutdown and restart; optional and unused for
`cancel`):

```json
{"action": "shutdown", "delaySeconds": 300, "reason": "Maintenance"}
```

Cancel takes no delay:

```json
{"action": "cancel"}
```

Reads:

```bash
TARGET='/api/v1/players/online?limit=100'
SIG=$(printf '%s\n%s\nGET\n%s' "$TS" "$NONCE" "$TARGET" \
  | openssl dgst -sha256 -hmac "$SECRET" -hex | awk '{print $2}')

curl -s \
  -H "X-GM-Timestamp: $TS" \
  -H "X-GM-Nonce: $NONCE" \
  -H "X-GM-Signature: $SIG" \
  "http://127.0.0.1:8090$TARGET"
```

Other read targets: `/api/v1/accounts/ADMIN`, `/api/v1/accounts/1`,
`/api/v1/characters/Thrall`, `/api/v1/instances?limit=100`.

## Errors

| Status | Meaning |
|--------|---------|
| `400` | malformed JSON or body (`bad_request`), unknown item template or exceeded `MaxCount` (`invalid_item`), or too many attachments (`too_many_items`) |
| `401` | missing header, bad signature, timestamp outside the skew window, or unknown actor |
| `403` | writes disabled, server control disabled, actor is a player account, permission denied, or target security too high |
| `404` | unknown path (`not_found`), missing account/character (`target_not_found`), or unknown permission (`unknown_permission`) |
| `405` | wrong method for a known target |
| `409` | nonce already seen (replay), self-target, player busy, inventory full, mailbox full, longer ban exists, or an RBAC list conflict |
| `429` | more than `GmApi.RateLimit` requests per minute from one address |
| `500` | pending audit row could not be written (action not run), outcome row failed after it ran, or mail creation failed |
| `503` | world thread did not process the request within 5 seconds, or is shutting down |

RBAC list conflicts use `already_granted`, `already_denied`, `in_denied_list`, `in_granted_list`, and
`not_in_list`. A longer existing ban uses `longer_ban_exists`.

## Permissions

| Action | Permission |
|--------|------------|
| Add item | `RBAC_PERM_COMMAND_ADDITEM` (488) |
| Mail | `RBAC_PERM_COMMAND_SEND_MAIL` (485) |
| Mail with items | also `RBAC_PERM_COMMAND_SEND_ITEMS` (484) |
| Mail with money | also `RBAC_PERM_COMMAND_SEND_MONEY` (487) |
| Ban account | `RBAC_PERM_COMMAND_BAN_ACCOUNT` (240) |
| Grant permission | `RBAC_PERM_COMMAND_RBAC_ACC_PERM_GRANT` (203) |
| Deny permission | `RBAC_PERM_COMMAND_RBAC_ACC_PERM_DENY` (204) |
| Revoke permission | `RBAC_PERM_COMMAND_RBAC_ACC_PERM_REVOKE` (205) |
| Shutdown | `RBAC_PERM_COMMAND_SERVER_SHUTDOWN` (734) |
| Restart | `RBAC_PERM_COMMAND_SERVER_RESTART` (727) |
| Cancel shutdown/restart | `RBAC_PERM_COMMAND_SERVER_SHUTDOWN_CANCEL` (735) |
| Kick | `RBAC_PERM_COMMAND_KICK` (510) |
| Unstuck | `RBAC_PERM_COMMAND_UNSTUCK` (534) |

Grant the least-privilege role that includes the action. See [rbac-roles.md](rbac-roles.md).

## Audit

Each authenticated write that passes the security and RBAC checks inserts a `pending`
`acore_auth.gm_audit_log` row before it is dispatched. The action then runs and a second row records
the outcome. A denied write inserts one `denied` row. Requests rejected before actor resolution
(`writes_disabled`, missing or unknown actor) are not audited.

- `command`: `api.additem`, `api.mail`, `api.ban`, `api.rbac`, `api.server`, `api.kick`, or
  `api.unstuck`
- `account_id`, `account_name`: the actor from `X-GM-Actor`
- `player_name`, `player_guid`: the resolved target when there is one
- `arguments`: a short summary; mail bodies, ban reasons, and server-control reasons are not stored
- `result`: `pending`, `denied`, or one of the outcome values below

Outcome values:

```text
success
bad_request
invalid_item
inventory_full
too_many_items
mailbox_full
mail_failed
target_not_found
cannot_target_self
player_busy
forbidden_target_security
teleport_failed
unknown_permission
already_granted
already_denied
in_denied_list
in_granted_list
not_in_list
longer_ban_exists
server_control_disabled
world_unavailable
world_timeout
```

If the pending insert fails, the API returns `500` and does not run the action. If the outcome insert
fails, the API returns `500` and logs `module.gm-api`; the action has already run and the `pending`
row remains. A timed-out write is cancelled before it starts when possible. Exactly one terminal row
is written: the claimed outcome, or `world_timeout` when the wait expires first, even if the action
later completes. Command-hook rows still record the attempt before execution.

## Security notes

- HMAC is computed over the exact target, so query parameters are covered.
- The request body is not signed. Keep the API on loopback or a private channel and never publish
  the secret.
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
- Server control is a destructive action. Keep `GmApi.AllowServerControl = 0` until the BFF and an
  external supervisor are ready. A restart only exits the process with the restart exit code.
- Reads keep one shared HMAC secret. Writes add the signed actor, RBAC, and audit; they are still
  gated by the same shared secret, so protect it like a service credential.
- Audit search is newest-N only. Add filters, cursor paging, and indexes before the website audit page.

## References

- [audit.md](audit.md)
- [rbac-roles.md](rbac-roles.md)
- [Bruno collection](../../tools/api-tests/bruno/README.md)
- [modules/mod-gm-api/README.md](../../modules/mod-gm-api/README.md)
- [specs/gm-tools.md](../../specs/gm-tools.md)
- [ADR-014](../../decisions/ADR-014-bruno-api-test-client.md)
