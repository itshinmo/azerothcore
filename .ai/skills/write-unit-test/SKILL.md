---
name: write-unit-test
description: Use when adding pure logic, a parser, a calculation, a helper, or a regression that can be tested without a live world.
---

# write-unit-test

## Prerequisites

- The behavior is isolated or can be isolated with existing mocks.
- The relevant test directory: `src/test/` for C++, or `tools/dbadmin/test/` once the GUI exists
  (phase 3).

## Workflow

1. Find the closest existing test and fixture. Reuse the pattern.
2. Write one behavior per test. Name it after the behavior, not the function.
3. Cover the edge cases: empty, null, boundary, error path, and the regression that motivated the
   change.
4. Use existing mocks (`WorldMock`, `TestPlayer`, `TestCreature`, `TestMap`, `UnitStub`,
   `AuraStub`). Do not build a live world for a unit test.
5. Run only the new test first, then the suite.

   ```bash
   ./build/src/test/unit_tests --gtest_filter='<Suite>.*'
   ctest --test-dir build -R unit --output-on-failure
   ```

6. For Node:

   ```bash
   # once the GUI exists (phase 3)
   node --test tools/dbadmin/test/
   ```

## Constraints

- No real network, disk, clock, or randomness unless injected.
- No production data or credentials.
- Do not test a mock's behavior instead of the product's.
- Do not weaken an existing assertion.
- A test that cannot fail without the change is not evidence.

## Expected output

A focused test that fails before the change and passes after it, plus the exact command and result.

## References

- [.ai/memories/testing.md](../../memories/testing.md)
- [src/test](../../../src/test)
- [.agents/docs/cpp-guidelines.md](../../../.agents/docs/cpp-guidelines.md)
