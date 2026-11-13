# 2026-11-12 — foundation audit

Scope: the new agent layer, dev tooling, local server lifecycle, test realm, backup flow, and fork CI.
This is a one-shot audit, not a contract. Fixes go through the strict gate.

## Summary

- P0: 0
- P1: 2
- P2: 7
- P3: 2

## Findings

### P1 — C++ verification was not executed end to end

- Evidence: `build-verify` was configured with `BUILD_TESTING=ON` and `-Werror`. On 2026-11-12 the
  full `unit_tests` target compiled and `./build-verify/src/test/unit_tests` exited 0. At audit time
  `cppcheck` was not installed on this Mac (`command -v cppcheck` empty). It was installed later
  (2.22) and `make verify-cpp` passes.
- Impact: the build and unit-test half of the T2 gate has evidence; the static-analysis half is now
  covered too.
- Fix: keep `cppcheck` installed and run `make verify-cpp`, or rely on fork CI's `cpp-lint` job.
- Status: fixed 2026-11-13.

### P1 — Fork CI is written but not observed on GitHub

- Evidence: `.github/workflows/fork-ci.yml` parses as YAML and pins checkout/setup-node/setup-python
  by SHA; no run exists yet.
- Impact: the first run may reveal a package name, Node version, or `-Werror` issue.
- Fix: push the workflow on a branch/PR and watch the four jobs. Adjust only with a reviewed change.
- Status: open.

### P2 — Smoke prints port warnings during its own run

- Evidence: `make verify-smoke` now calls `doctor.sh --expect-running`, so the ports it just started
  report `ok` instead of a warning.
- Impact: none; output is clean.
- Fix: done.
- Status: fixed.

### P2 — SQL gate creates a 308 MB test backup per SQL run

- Evidence: `var/backups/verify/20261112-020706/test.sql` is 308 MB; `tools/dev/verify.sh` keeps 7
  days.
- Impact: repeated SQL work can consume several GB.
- Fix: retention is implemented; monitor disk before large runs. A future improvement is a schema-only
  or per-table backup for small changes.
- Status: monitored.

### P2 — Test realm has no seeded GM account

- Evidence: `acore_test_auth.account` is empty after bootstrap; the e2e harness creates its own
  accounts, but manual GM checks need one.
- Impact: a human must create an account before manual test-realm verification.
- Fix: add an optional `seed-admin` step to `tools/dev/test-realm.sh`, or document the console command
  sequence.
- Status: open.

### P2 — `bin/acore-db-export` points at a missing script

- Evidence: `bin/acore-db-export` sources `apps/db_exporter/db_export.sh`, which is absent; the current
  build uses `TOOLS_BUILD=none`.
- Impact: a documented helper fails.
- Fix: remove or repair the wrapper; decide whether `dbimport`/exporter tools are needed locally.
- Status: open.

### P2 — Build output and client data are large

- Evidence: `build/` ~703 MB, `env/dist/bin/worldserver` ~34 MB, `Data/` has thousands of map/vmap/
  mmap files, and local backups reached 1.2 GB.
- Impact: disk pressure on a laptop; CI builds are expensive.
- Fix: keep the 14-day backup retention, prune old verify backups, and avoid committing or copying
  client data.
- Status: monitored.

### P2 — Worldserver idle CPU is normal after startup

- Evidence: a sampled `top -l 1` after startup showed 0.0% CPU; earlier `ps` averages included the
  startup burst.
- Impact: no issue. Do not chase the startup average as an idle leak.
- Fix: none.
- Status: closed.

### P2 — Console EOF spin is fixed in the wrapper

- Evidence: `tools/dev/server.sh` runs under `screen`; `Console.Enable=0` is documented for services
  with null stdin. The old 128 MB `AC> ` log was removed.
- Impact: no runaway log or busy loop under `make start`.
- Fix: keep the screen/tty requirement in `runbook/operation/start-stop.md`.
- Status: fixed.

### P3 — `tools/dev/config.env.example` was not mentioned in setup

- Evidence: `tools/dev/config.env.example` exists; `runbook/development/setup-macos.md` now points to it.
- Impact: none now; a new developer can find the overrides.
- Fix: done.
- Status: fixed.

### P3 — Audit index has no report rows yet

- Evidence: `runbook/audits/README.md` index is empty.
- Impact: reports are harder to find.
- Fix: add this report to the index.
- Status: fixed in this change.

## What was checked

- Agent roles, skills, templates, and adapters.
- Markdown links across `.ai`, `specs`, `decisions`, `rfcs`, `runbook`, `.agents`, `.github`, `tools`,
  and `data/sql/custom`.
- `make doctor`, `make verify-docs`, `make verify-sql`, `make verify-smoke`, `make start`, `make stop`.
- Test realm setup, start, status, stop, and SQL apply/backup.
- Backup permissions and retention.
- Fork CI YAML parse and action pins.
- Local worldserver CPU sample and console behavior.

## What was not checked

- Full `make verify-cpp` build and unit tests.
- An actual GitHub Actions run.
- Production deployment.
- Player-client login.
