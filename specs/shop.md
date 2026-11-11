# Shop

## Purpose

Record the shop policy and the open trust decision. No shop code is implemented in this phase.

## Scope

Future monetization: what may be sold, how a purchase is delivered, how it is audited.

## Boundary

Owns the server-side shop policy and delivery contract. The website is a separate repository and is
not specified here. Does not own payment processing.

## Contract

### Allowed products

Cosmetics and convenience only. Explicitly allowed, per the project decision:

- cosmetics: mounts, pets, tabards, toys, transmog, cosmetic effects
- XP boosts
- reputation boosts
- respec / dual spec
- bank / bag slots
- character services (name, race, faction, appearance)
- profession boosts
- lockout resets
- utility NPCs / teleports

Excluded: gear, gold, direct combat power, items that bypass progression, and anything that creates
pay-to-win.

### Delivery

- A purchase becomes an entitlement for an account.
- Delivery is idempotent: the same order cannot grant twice.
- Offline characters receive items by mail.
- Every grant records order id, account, character, item/service, quantity, reason, and actor.
- Refunds follow the same audit path.

### Trust decision (open)

<!-- TODO: choose before any shop implementation. -->

Options:

1. **Server API module (preferred in the plan).** The website calls an HMAC-signed endpoint; the
   server writes the entitlement and mails the item. The web app never gets MySQL credentials.
2. **Website writes DB.** The website writes entitlement rows directly. Simpler, but the web app holds
   write credentials and bypasses game logic.
3. **Manual GM grants.** Staff grants purchases by hand until automation exists.

The decision must be recorded as an ADR before implementation. Until then, no shop code.

### Idempotency and fraud

- One order id maps to at most one grant.
- A retry returns the existing result, never a second grant.
- A chargeback or refund revokes the entitlement only if the item/service is still recoverable;
  otherwise a human decides.
- Rate-limit account linking and delivery attempts.

## Errors and edge cases

- Duplicate order: return the existing grant, do not duplicate.
- Unknown account: fail with a clear error, no partial grant.
- Mailbox full: queue or retry; never drop the entitlement.
- Server offline: queue the entitlement for delivery at next login.
- Item removed by an update: map to a replacement or refund; human decision.

## Security

- No payment credentials on the game server.
- HMAC secret only on the server and the website backend.
- Least-privilege database user.
- Audit every grant and refund.
- No player data in logs beyond the account/character needed for the audit.

## Observability

- Grant/refund audit.
- Delivery queue status.
- Failed delivery alerts.

## References

- [decisions/ADR-006-shop-policy.md](../decisions/ADR-006-shop-policy.md)
- [decisions/OPEN-QUESTIONS.md](../decisions/OPEN-QUESTIONS.md)
- [specs/gm-tools.md](gm-tools.md)
