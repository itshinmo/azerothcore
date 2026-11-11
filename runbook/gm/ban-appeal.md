# Ban appeal

## When to use

Reviewing a ban, answering an appeal, or reversing a mistaken ban.

## Prerequisites

- The account name, ban record, and evidence.
- The original reason and duration.
- The GM role with ban permission for a reversal.

## Steps

1. Look up the account:

   ```text
   .lookup player account <name>
   ```

2. Inspect active and historical bans:

   ```sql
   SELECT id, bandate, unbandate, bannedby, banreason, active
   FROM acore_auth.account_banned
   WHERE id = <account_id>
   ORDER BY bandate DESC;
   ```

3. Inspect the evidence: chat logs, IP actions, trade logs, and the original report.
4. Decide:
   - **Upheld:** explain the rule and the evidence; do not reveal another player's data.
   - **Reduced:** change the duration with a human approval and an audit note.
   - **Reversed:** unban only with evidence and a human approval.
5. Perform the action:

   ```text
   .unban account <name>
   ```

   Confirm exact syntax with `.help unban`.

6. Record: account, ban id, decision, evidence, actor, and time.
7. If the ban was automated or a bug, open a finding for the cause.

## Rules

- Never reverse a ban without evidence.
- Never share another player's personal data.
- Never ban or unban from a compromised GM account.
- High-impact or legal cases go to a human.
- Keep the appeal text and decision in the audit record.

## Verification

- `account_banned.active` is 0 for a reversed ban.
- The account can log in.
- The audit entry exists.

## References

- [specs/gm-tools.md](../../specs/gm-tools.md)
- [incident-response.md](incident-response.md)
- [common-queries.md](../database/common-queries.md)
