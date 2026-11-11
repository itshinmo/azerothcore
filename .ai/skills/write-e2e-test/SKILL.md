---
name: write-e2e-test
description: Use only when the user explicitly asked for live-stack coverage or an existing e2e test broke. Writes a deterministic AzerothGhost test against the test realm.
---

# write-e2e-test

## Prerequisites

- The user explicitly asked for e2e coverage, or an existing test broke.
- A running test realm with `Warden.Enabled=0`.
- Go 1.26+ and `e2e/` dependencies.
- Read `e2e/README.md` and `.agents/docs/e2e-policy.md`.

## Workflow

1. Search for an existing test with the same oracle before adding one.
2. Choose the smallest fixture: `NewSolo` or `NewScenario`.
3. Start with `meta.Begin(t, meta.TestMeta{...})`.
4. Flow: fixture → place → setup (GM is fine) → combat-ready if pulling → drive → assert.
5. Use waiters, not fixed sleeps. Arm → send → wait.
6. Assert behavior: protocol, object cache, or DB after `Save`. Not "no error".
7. Clean up spawned rows and summoned creatures.
8. Run:

   ```bash
   cd e2e
   go test -tags=e2e ./suites/<path> -run <TestName> -count=1 -v -timeout 30m -parallel 1
   ```

## Constraints

- Do not add a suite, test, or `e2e/local/` scratch test unless asked.
- Do not invent harness APIs.
- Do not use production data or accounts.
- Do not hide a failure with a retry or a soft pass.
- Do not test a GM command that is not on the player path unless the player-visible state is the
  oracle.

## Expected output

One deterministic test with a clear oracle, a pass on the fixed code, and a documented failure on the
unfixed code when applicable.

## References

- [e2e/README.md](../../../e2e/README.md)
- [.agents/docs/e2e-policy.md](../../../.agents/docs/e2e-policy.md)
- [specs/testing-and-release.md](../../../specs/testing-and-release.md)
