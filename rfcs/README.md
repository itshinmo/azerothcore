# RFCs

Proposals before they become accepted behavior. An RFC is for a significant, cross-cutting, or
contested change; a small change goes straight to a spec or runbook.

## Conventions

- File name `RFC-NNN-<slug>.md`, numbered in order.
- Status: `draft`, `discussion`, `accepted`, `rejected`, `withdrawn`. An accepted RFC whose
  implementation is gated (downloads, phase gate, owner go) stays in `active/` until its durable
  content is folded into `specs/` or `decisions/` at implementation time.
- Start from [the RFC template](../.ai/templates/rfc.md).
- On acceptance, fold the durable content into `specs/` or `decisions/`, then move the RFC to
  `archived/`.
- An unaccepted RFC never overrides an accepted spec or ADR.

## Index

### Active

- [RFC-001-client-modernization.md](active/RFC-001-client-modernization.md) — accepted (gated on
  downloads + owner go) — Reforged + Ascension customization pack (replaces Patch-A) +
  mod-forever-ui; spell-animation findings; owner download bundle.
- [RFC-002-collections-transmog.md](active/RFC-002-collections-transmog.md) — accepted (gated on
  Phase 1 gate) — account-wide appearances, mounts, pets; toys per character, via the
  buildthehomelab stack.
- [RFC-003-qol-social-slate.md](active/RFC-003-qol-social-slate.md) — accepted (gated on Phase 1
  gate) — QoL/social slate with small-balance bonus XP and extended cross-faction scope.

### Archived

None.
