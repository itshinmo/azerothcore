# ADR-006 — Shop policy

- Status: accepted for the product policy; the delivery trust model is open
- Date: 2026-11-12

## Context

The server may sell cosmetics and convenience items. The website is a separate repository. The game
server must not become pay-to-win, must not store payment credentials, and must deliver purchases
idempotently and auditably.

## Decision

1. **Allowed products.** Cosmetics and convenience only:
   - cosmetics: mounts, pets, tabards, toys, transmog, cosmetic effects
   - XP boosts
   - reputation boosts
   - respec / dual spec
   - bank / bag slots
   - character services (name, race, faction, appearance)
   - profession boosts
   - lockout resets
   - utility NPCs / teleports
2. **Excluded.** Gear, gold, direct combat power, items that bypass progression, and anything that
   creates pay-to-win.
3. **Delivery.** A purchase becomes an account entitlement. Delivery is idempotent by order id.
   Offline characters receive items by mail. Every grant and refund is audited.
4. **No implementation now.** The server-side shop is out of scope until the delivery trust model is
   decided.

## Open decision

The delivery trust model is not chosen. Options:

1. **Server API module (preferred in the plan).** HMAC-signed endpoint; the server writes the
   entitlement and mails the item. The website never holds MySQL credentials.
2. **Website writes DB.** Simpler, but the website holds write credentials and bypasses game logic.
3. **Manual GM grants.** Staff grants purchases by hand until automation exists.

Record the choice as an ADR before implementation. See
[OPEN-QUESTIONS.md](OPEN-QUESTIONS.md).

## Alternatives considered

- **Sell gear and gold.** Higher revenue, pay-to-win, balance and reputation damage. Rejected.
- **Sell only cosmetics.** Safest, but the project chose to allow convenience too.
- **No shop.** Out of scope, but the product goal includes monetization later.

## Consequences

- The policy is ready; implementation is blocked on the trust decision.
- Item and service design must fit the allowed list.
- The website contract must preserve idempotency and audit.
