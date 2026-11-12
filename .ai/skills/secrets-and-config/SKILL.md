---
name: secrets-and-config
description: Use when creating or changing local configuration, database credentials, tokens, or environment files. Keeps secrets out of the repository and logs.
---

# secrets-and-config

## Prerequisites

- Know which component reads the config: server, database client, GM panel, or scripts.
- Know whether the environment is local, test, or production.

## Workflow

1. Never put a secret in a tracked file. Commit only `.example` files with placeholders.
2. Server config lives in `env/dist/etc/*.conf` (ignored). Tool config lives in a `.env` next to the
   tool (ignored).
3. Restrict permissions:

   ```bash
   chmod 600 .env
   chmod 600 env/dist/etc/*.conf
   ```

4. Use separate database users:
   - local/test write user for DBeaver and scripts
   - production read-only user for DBeaver
   - server user for `worldserver`/`authserver`
   - never `root`
5. Verify the file is ignored:

   ```bash
   git check-ignore -v .env env/dist/etc/worldserver.conf
   ```

6. If a secret was committed or logged, stop, report it to the human, rotate it, and remove it from
   history only with human approval.

## Constraints

- No credentials, tokens, keys, connection strings, player data, or production hostnames in docs,
  tests, logs, chat, or commits.
- Do not print a secret to debug it. Print the variable name, not the value.
- Do not copy a production config into the repository.
- Do not weaken file permissions to make a tool run.

## Expected output

Working local config, ignored by git, with least-privilege credentials and a note of what was set
(never the values).

## References

- [.ai/memories/security.md](../../memories/security.md)
- [specs/security.md](../../../specs/security.md)
- [runbook/development/config-changes.md](../../../runbook/development/config-changes.md)
