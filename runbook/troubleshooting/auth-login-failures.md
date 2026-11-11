# Auth and login failures

## Symptoms

The client cannot reach the realm, login fails, the realm list is empty, or the world rejects the
session.

## Checks

1. **authserver is listening:**

   ```bash
   lsof -nP -iTCP:3724 -sTCP:LISTEN
   tail -n 100 env/dist/logs/Auth.log
   ```

2. **Realm list:**

   ```sql
   SELECT id, name, address, localAddress, port, icon, flag, gamebuild
   FROM acore_auth.realmlist;
   ```

   `address` must be reachable by the client. `gamebuild` must match the client (12340 for 3.3.5a).

3. **Account:**

   ```sql
   SELECT id, username, last_login FROM acore_auth.account WHERE username = ?;
   ```

4. **Ban:**

   ```sql
   SELECT * FROM acore_auth.account_banned WHERE id = ? AND active = 1;
   ```

5. **World reachable:** the client connects to the realm `address:port` (8085 by default). Check
   firewall and bind IP.

6. **Build info:** `acore_auth.build_info` must contain the client build.

7. **Warden:** on a test realm with AzerothGhost, `Warden.Enabled=0`. On production, keep it on. A
   Warden OS mismatch can reject a valid login.

## Common causes

| Symptom | Cause |
|---------|-------|
| Realm list empty | `realmlist` empty or address wrong |
| Client stuck at "Connecting" | world port blocked or wrong address |
| "Invalid username/password" | wrong account or SRP6 verifier |
| "Account banned" | active ban |
| "Invalid client build" | `gamebuild`/`build_info` mismatch |
| Login then disconnect | worldserver down or realm address wrong |
| Warden rejection | client OS mismatch; test realm only |

## Verification

- `Auth.log` shows the login attempt and result.
- The client reaches the character list.
- The character enters the world.

## Rules

- Do not disable Warden on production to fix a login.
- Do not edit `account` password columns by hand; use the account command.
- Do not share account data.

## References

- [server-wont-start.md](server-wont-start.md)
- [health-check.md](../operation/health-check.md)
- [e2e/README.md](../../e2e/README.md)
