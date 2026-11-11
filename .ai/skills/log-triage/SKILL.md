---
name: log-triage
description: Use when the server fails to start, a command errors, a query fails, or a test reports a server-side problem. Finds the first decisive error and classifies it.
---

# log-triage

## Prerequisites

- The run's log directory (`env/dist/logs/` by default).
- The approximate time of the failure and the last change.

## Workflow

1. Find the first error, not the last symptom:

   ```bash
   tail -n 300 env/dist/logs/Errors.log
   grep -nE 'ERROR|FATAL|SQL|failed|Could not' env/dist/logs/Server.log | tail -n 80
   tail -n 80 env/dist/logs/Auth.log
   ```

2. Classify:
   - **SQL/schema:** missing table/column, failed update, duplicate key, bad `WHERE`.
   - **Config:** wrong DB string, `DataDir`, port, realm ID.
   - **Data:** missing DBC/map/vmap/mmap, unknown creature/item/spell ID.
   - **Code:** assertion, null dereference, unhandled packet, script registration.
   - **Environment:** MySQL down, disk full, permissions, port conflict.
3. Locate the first line that explains the failure. Quote the shortest decisive line.
4. Reproduce with the smallest command: `worldserver -d`, a single SQL file, a single unit test, or
   one in-game action.
5. Report the root cause and the evidence. Do not guess from the last line.

## Constraints

- Do not paste secrets or player data into a report.
- Do not delete or truncate logs before preserving the failure.
- Do not restart production to reproduce; use local/test.
- If the log is ambiguous, say what is unknown and what would distinguish the candidates.

## Expected output

A short report: first error with file/line, classification, reproduction, root cause or next
discriminating check.

## References

- [runbook/operation/logs-and-monitoring.md](../../../runbook/operation/logs-and-monitoring.md)
- [runbook/troubleshooting/server-wont-start.md](../../../runbook/troubleshooting/server-wont-start.md)
- [runbook/troubleshooting/database-errors.md](../../../runbook/troubleshooting/database-errors.md)
