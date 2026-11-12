# GM API

Read-only HTTP API inside `worldserver`. The future server website calls it through a BFF; no
in-repo web UI is built.

## When to use

Testing the API, wiring the future website BFF, or checking that HMAC authentication works.

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
```

- `GmApi.Secret` is required, at least 32 characters. Empty or short secrets stop the API.
- `GmApi.NonceTtl` must be at least `2 * GmApi.MaxClockSkew`.
- Bind loopback or a private VPN address. Never expose it publicly.
- The secret is a credential. Keep it out of the repository, logs, and chat.
- Restart `worldserver` after changing the config.

## Endpoints

| Method | Target | Returns |
|--------|--------|---------|
| GET | `/api/v1/status` | `{"status":"ok"}` |
| GET | `/api/v1/audit?limit=50` | recent `gm_audit_log` rows, limit 1–200 |

No write endpoints. No direct database writes from clients.

## Signing

Canonical string:

```text
<timestamp>\n<nonce>\n<METHOD>\n<target>
```

`target` includes the query string, for example `/api/v1/audit?limit=10`.

Headers:

```text
X-GM-Timestamp: <unix seconds>
X-GM-Nonce: <random, 8-128 chars>
X-GM-Signature: <hex HMAC-SHA256(secret, canonical)>
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

Reusing the same nonce returns `409`.

## Errors

| Status | Meaning |
|--------|---------|
| `401` | missing header, bad signature, or timestamp outside the skew window |
| `405` | method other than GET |
| `409` | nonce already seen within `GmApi.NonceTtl` |
| `429` | more than `GmApi.RateLimit` requests per minute from one address |
| `404` | unknown target |

## Security notes

- HMAC is computed over the exact target, so query parameters are covered.
- Nonces are stored in memory until `GmApi.NonceTtl` expires.
- The server is single-threaded; a slow audit query delays other requests. Keep limits small.
- The audit query uses the shared synchronous login pool. A stalled login database can delay the API
  thread; a dedicated connection is a future change.
- The future website BFF shares one source address; all admin-dashboard users share one rate-limit bucket.
  Raise the limit or add caller identity before the website goes live.
- No CORS by design. The future website BFF calls the API server-side; browsers do not call it
  directly.
- The API is read-only and uses one shared HMAC secret; it has no caller identity or RBAC yet.
  Write endpoints must add a signed actor/service identity plus RBAC and audit before shipping.
- Audit search is newest-N only. Add filters, cursor paging, and indexes before the website audit page.

## References

- [audit.md](audit.md)
- [rbac-roles.md](rbac-roles.md)
- [modules/mod-gm-api/README.md](../../modules/mod-gm-api/README.md)
- [specs/gm-tools.md](../../specs/gm-tools.md)
