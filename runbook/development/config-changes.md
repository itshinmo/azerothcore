# Configuration changes

## When to use

Changing server settings, database connections, ports, rates, logging, or tool configuration.

## Prerequisites

- Know the environment: local, test, or production.
- Know which config the component reads.

## Server configuration

1. Server config templates live in `src/server/apps/{authserver,worldserver}/*.conf.dist`; do not edit
   them for local values. `conf/dist/` holds build and shell templates (`config.cmake`, `config.sh`,
   `env.ac`), not the server configs.
2. Local server configs live in `env/dist/etc/*.conf` and are ignored by git.
3. After an install, compare the local config with the new `.conf.dist` from
   `src/server/apps/{authserver,worldserver}/` and merge the new keys. The Python config merger lives
   in `apps/config-merger/python/`.
4. Restart the affected server. Some settings support `.reload config`, but restart is safer for
   connection strings and ports.

Key settings:

| Setting | Meaning |
|---------|---------|
| `LoginDatabaseInfo` / `WorldDatabaseInfo` / `CharacterDatabaseInfo` | DB host/port/user/password/name |
| `DataDir` | `dbc/`, `maps/`, `vmaps/`, `mmaps/` |
| `LogsDir` | log output |
| `RealmID` | realm row |
| `WorldServerPort` | 8085 default |
| `Updates.EnableDatabases` / `Updates.AutoSetup` | schema updater |
| `Warden.Enabled` | client integrity; off on e2e test realm |
| `SOAP.Enabled` / `Ra.Enable` | remote admin; off unless protected |
| `Console.Enable` | interactive console thread; 0 for a service with null stdin |

## Environment overrides

Every option can be overridden with `AC_<KEY>`: camelCase is split, and `.`, `-`, and spaces become
`_`. Examples: `AC_DATA_DIR`, `AC_WORLD_DATABASE_INFO`, `AC_SOAP_ENABLED`.

## Tool configuration

- Database client: DBeaver stores its own connection profiles; nothing in the repo. See
  [runbook/database/dbeaver.md](../database/dbeaver.md).
- GM API: `GmApi.*` in `worldserver.conf` (ignored). `GmApi.Secret` is a credential.
- Dev scripts: `tools/dev/config.env` (ignored) or environment variables.

## Rules

- Never commit a real config with credentials.
- Never copy a production config into the repository.
- Use `chmod 600` on files with credentials.
- Verify with `git check-ignore -v <file>`.
- Document a new setting in `specs/server.md` or the tool's spec.

## Verification

- The server starts and logs the expected values without printing secrets.
- The affected feature works.
- `git status` shows no tracked config change.

## References

- [specs/server.md](../../specs/server.md)
- [.ai/skills/secrets-and-config/SKILL.md](../../.ai/skills/secrets-and-config/SKILL.md)
- [doc/ConfigPolicy.md](../../doc/ConfigPolicy.md)
