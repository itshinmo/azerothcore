---
description: Deferred live tests: BG pops, 3v3 solo queue, personal arena teams, queue-from-anywhere
owner: verifier
status: active
related: local-server-setup
created: 2026-11-21
---

# Group-content testing session

## Context

Tasks 8-11 of the RFC-003 slate (BG pops, 3v3 solo queue, personal arena teams, the full
queue-pop side of queue-from-anywhere) were deferred: with two clients the owner could not join a
battleground during the QoL sessions, so no live pop test happened.

## Findings / hypotheses

- Code paths verified by build, unit review, and the reviewer round only — no live pop test yet.
- WSG `MinPlayersPerTeam` currently 5 (test tweak reverted; revisit when pops are tested).
- Cross-faction BG test also deferred here (CFBG.conf live config required — see ADR-023).

## Open questions

- Can a second client actually join a BG on this setup; if not, GM-command staging for pops?
- Where do the pop-test results get recorded (ADR-024 test record vs a testing memory)?

## To promote on resolution

- Test evidence into the ADR-023/ADR-024 records or `.ai/memories/testing.md`.
