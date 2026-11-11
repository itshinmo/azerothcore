# Item grant and refund

## When to use

Granting a purchase, mailing an item to an offline character, correcting a grant, or refunding a
purchase.

## Prerequisites

- The account, character, item ID, quantity, and reason.
- An economy-role GM account.
- A backup if the action writes to the database.

## Grant

1. Verify the target:
   - `.lookup player account <account>`
   - confirm the account and character.
2. Verify the item:
   - `.lookup item <id>`
   - confirm the exact item, not a lookalike.
3. Choose the path:
   - online character, simple grant: `.additem`
   - offline character or purchase: mail via `.send items`, or the GM panel when it lands (phase 4).
4. Record: order id (if any), account, character, item, quantity, reason, actor.
5. Perform the grant.
6. Verify the inventory or mailbox and the audit entry.

## Mail

```text
.send items <player> "<subject>" "<text>" <item>:<count>
```

Confirm exact syntax with `.help send items`.

## Refund

1. Verify the original grant from the audit log.
2. Confirm the item is still present and in the expected state.
3. If recoverable, remove the item and grant the compensation in one audited action.
4. If consumed, traded, or bound in a way that cannot be reversed, escalate to a human.
5. Record the refund reason and the original order.

## Rules

- Never duplicate a grant because of a retry; check the audit first.
- Never grant from a screenshot or a player's claim alone.
- Never grant gold or items to an account you cannot verify.
- High-value or bulk grants require human approval.
- Use the panel or a wrapped command; raw SQL bypasses game logic.

## Verification

- The target has exactly the intended item/quantity.
- No duplicate mail or inventory row.
- The audit entry names actor, target, reason, and result.

## References

- [.ai/skills/gm-item-grant-refund/SKILL.md](../../.ai/skills/gm-item-grant-refund/SKILL.md)
- [command-handbook.md](command-handbook.md)
- [specs/gm-tools.md](../../specs/gm-tools.md)
