---
name: gm-incident-response
description: Use when a GM action, exploit, crash, data corruption, or player report needs containment, diagnosis, restoration, and a written record.
---

# gm-incident-response

## Prerequisites

- Access to logs, the database, and the audit trail.
- A backup or the ability to take one now.
- The incident start time and the last known good state.

## Workflow

1. **Contain.**
   - Stop the harmful action: revoke the permission, kick the account, disable the command path, or
     stop writes.
   - If data is at risk, stop the server gracefully.
2. **Preserve.**
   - Copy `Server.log`, `Errors.log`, `Auth.log`, and the audit records.
   - Take a database backup before any repair.
   - Record the timeline.
3. **Diagnose.**
   - Identify the actor, action, target, and time.
   - Find the first error and the last known good state.
   - Determine whether the cause is a bug, a permission gap, a compromised account, or a data error.
4. **Restore.**
   - Restore the affected rows from the backup or apply a reviewed repair.
   - Never mass-edit without a backup and a `WHERE` review.
5. **Verify.**
   - Health check, login, affected feature, audit entry.
6. **Record.**
   - Write an incident note: timeline, root cause, fix, prevention, owner.
   - If the cause generalizes, update the runbook or spec.

## Constraints

- Do not delete evidence.
- Do not discuss the incident in public channels with player data or secrets.
- Do not blame an account without evidence.
- Do not restore production without human approval.
- Do not close the incident until the verification passes.

## Expected output

An incident note with timeline, evidence, root cause, restoration, verification, and prevention.

## References

- [runbook/gm/incident-response.md](../../../runbook/gm/incident-response.md)
- [runbook/operation/rollback.md](../../../runbook/operation/rollback.md)
- [runbook/operation/backup-restore.md](../../../runbook/operation/backup-restore.md)
