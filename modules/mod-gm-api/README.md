# mod-gm-api

Read-only HTTP API inside `worldserver` for the future server website BFF.

## Endpoints

- `GET /api/v1/status` — `{"status":"ok"}`
- `GET /api/v1/audit?limit=50` — recent `gm_audit_log` rows, limit 1–200

## Security

- Localhost bind by default.
- HMAC-SHA256 over `timestamp\nnonce\nMETHOD\ntarget`, where `target` includes the query string.
- Headers: `X-GM-Timestamp`, `X-GM-Nonce`, `X-GM-Signature`.
- Timestamp skew and nonce TTL are configurable.
- Replayed nonce returns `409`; bad signature, missing headers, or skew returns `401`.
- Per-IP rate limit: default 120 requests per minute; see `GmApi.RateLimit`.
- No writes. No direct SQL writes from clients.

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
```

`GmApi.Secret` is required, at least 32 characters. The API does not start otherwise.

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

Reuse the same nonce twice; the second request must return `409`.
