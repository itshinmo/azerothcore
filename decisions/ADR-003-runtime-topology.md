# ADR-003 — Runtime topology

- Status: accepted
- Date: 2026-11-12

## Context

The team develops on macOS. Production will be a Linux VPS, but the provider and region are not
chosen yet. The server is latency-sensitive; `worldserver` map updates use worker threads, but
single-core clock speed, RAM, and NVMe matter more than raw core count. Docker on macOS runs a Linux
VM and is slower for builds and MySQL.

## Decision

1. **Development.** Native macOS build in `build/`, install prefix `env/dist/`, Homebrew MySQL 8.4.
2. **Production.** Ubuntu 24.04 LTS x86_64, native `authserver`/`worldserver` binaries, MySQL on the
   same host, systemd, firewall. 4 vCPU / 16 GB / NVMe is the target; 2 vCPU / 8 GB is the minimum.
3. **Windows later.** If a Windows developer joins, use WSL2 or Docker. Do not make native Visual
   Studio the primary path.
4. **Docker.** Optional for cross-OS parity and CI. Not the production performance baseline, not the
   macOS development baseline.
5. **Provider.** Deferred. The comparison is in `runbook/operation/production-deploy.md`. Hetzner
   Cloud CCX is the current performance-first candidate; OVHcloud Rise and DigitalOcean Premium are
   alternatives.
6. **Database placement.** Same host as `worldserver` for latency. A separate managed DB is a
   documented option if the provider makes it cheaper or more reliable.

## Alternatives considered

- **Docker everywhere.** Best parity, but slower macOS loop and extra volume/network tuning.
- **macOS-only.** No production path.
- **Windows-native primary.** Fragile toolchain for a C++/MySQL server.
- **Kubernetes.** Unneeded for one realm and a small team.

## Consequences

- Fast local loop; production differs from development in OS and service management.
- Linux verification is required before production.
- The provider decision stays open without blocking the foundation.
