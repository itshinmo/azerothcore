---
name: gm-item-grant-refund
description: Use when granting an item, mailing a purchase, refunding a purchase, or correcting an item-related mistake.
---

# gm-item-grant-refund

## Prerequisites

- The account, character, item ID, quantity, and reason.
- The GM role with economy permission.
- A backup if the action writes to the database.

## Workflow

1. Verify the target: `.lookup player account <account>`, account ID, character GUID, online state.
2. Verify the item: `.lookup item <id>`; confirm it is the intended item and not a lookalike.
3. Prefer the audited path:
   - in-game `.additem` for a simple grant, or
   - mail for an offline character or a purchase; the future website will use the audited API.
4. For a purchase, record the order ID (if any), account, character, item, quantity, and reason.
5. Grant or mail the item. For mail, set a subject and a short reason.
6. Verify: inventory or mailbox query, item count, and the audit entry.
7. For a refund, verify the item is still present and bound as expected; remove it and grant the
   compensation in one audited action. Never refund an item that was already consumed or traded
   without a human decision.

## Constraints

- Never grant from untrusted input or a screenshot alone.
- Never grant gold or items to an account you cannot verify.
- Never duplicate a grant because of a retry; check the audit log first.
- Never use raw SQL for a grant when a command or audited API action exists.
- High-value or bulk grants require human approval.

## Expected output

A grant/refund record: account, character, item, quantity, reason, command or API action, audit
reference, and verification.

## References

- [runbook/gm/item-grant-refund.md](../../../runbook/gm/item-grant-refund.md)
- [runbook/gm/command-handbook.md](../../../runbook/gm/command-handbook.md)
- [specs/gm-tools.md](../../../specs/gm-tools.md)
