# Incident response

## When to use

A crash, exploit, data corruption, compromised GM account, bad deploy, or a player report with
security or data implications.

## Steps

1. **Contain.**
   - Revoke the permission or disable the command path.
   - Kick the account or stop writes.
   - If data is at risk, stop `worldserver` gracefully.
2. **Preserve.**
   - Copy `Server.log`, `Errors.log`, `Auth.log`, and audit records.
   - Take a database backup before any repair.
   - Start a timeline with times, actors, and actions.
3. **Diagnose.**
   - Find the first error and the last known good state.
   - Identify actor, action, target, and time.
   - Classify: bug, permission gap, compromised account, data error, environment.
4. **Restore.**
   - Restore from the pre-incident backup or apply a reviewed repair.
   - Never mass-edit without a backup and a narrow `WHERE`.
5. **Verify.**
   - Health check, login, affected feature, audit entry.
6. **Record.**
   - Timeline, root cause, fix, prevention, owner.
   - Update a runbook or spec if the cause generalizes.

## Severity

- **SEV-1:** data loss, account compromise, server-wide exploit, production down.
- **SEV-2:** a class of players affected, economy exploit, repeated crash.
- **SEV-3:** single-player issue, non-security bug, cosmetic error.

## Rules

- Do not delete evidence.
- Do not discuss player data or secrets in public channels.
- Do not restore production without human approval.
- Do not close before verification passes.
- A secret exposed in a log is rotated, not just deleted.

## Expected output

An incident note: severity, timeline, evidence, root cause, restoration, verification, prevention,
owner.

## References

- [.ai/skills/gm-incident-response/SKILL.md](../../.ai/skills/gm-incident-response/SKILL.md)
- [rollback.md](../operation/rollback.md)
- [backup-restore.md](../operation/backup-restore.md)
- [logs-and-monitoring.md](../operation/logs-and-monitoring.md)
