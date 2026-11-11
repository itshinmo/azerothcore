# Production deploy

## When to use

After the provider is chosen and the server is ready to go live. The provider decision is still open;
this runbook records the target contract.

## Target

- Ubuntu 24.04 LTS x86_64
- 4 vCPU / 16 GB RAM / NVMe (2 vCPU / 8 GB minimum)
- Native `authserver` and `worldserver` binaries
- MySQL 8.4 on the same host
- systemd units
- Firewall: 3724 and 8085 open; SSH restricted; no database port exposed
- Backups and monitoring configured before launch

## Provider comparison

| Provider | Strength | Tradeoff |
|----------|----------|----------|
| Hetzner Cloud CCX | dedicated AMD EPYC, best single-core price/performance | EU/US regions, account verification |
| OVHcloud Rise | good EU/NA network | slightly higher price |
| DigitalOcean Premium | simple, global | higher cost for the same CPU |
| AWS Lightsail | easy | weaker CPU per dollar |

Single-core clock speed matters more than core count for `worldserver`.

## Build on Linux

```bash
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSCRIPTS=static -DMODULES=static \
  -DCMAKE_INSTALL_PREFIX=/opt/azerothcore
cmake --build build -j"$(nproc)"
cmake --install build
```

Install MySQL 8.4, create the databases, import, and configure `DataDir` with extracted client data.

## systemd

Create `azerothcore-auth.service` and `azerothcore-world.service`:

```ini
[Unit]
Description=AzerothCore authserver
After=network.target mysql.service

[Service]
Type=simple
User=acore
WorkingDirectory=/opt/azerothcore/bin
ExecStart=/opt/azerothcore/bin/authserver
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Repeat for `worldserver`. Start `worldserver` first, then `authserver`.

The worldserver console reads stdin. With `StandardInput=null` and `Console.Enable=1` it spins on EOF
and writes `AC> ` forever. In a systemd unit, either set `Console.Enable = 0` and manage the server
through SOAP/RA or `systemctl`, or run it under `screen`/`tmux` with a pty. Do not leave
`Console.Enable=1` with a null stdin.

## Deploy procedure

1. Announce the maintenance window.
2. Back up the three databases.
3. Stop `authserver`, then `worldserver`.
4. Deploy the new binaries and configs.
5. Start `worldserver`, then `authserver`.
6. Run the health check.
7. Verify login and the affected feature.
8. Watch `Errors.log` for 15 minutes.
9. Record the deploy: commit, backup path, health result.

## Rollback

Use [rollback.md](rollback.md). Keep the previous binaries and the pre-deploy backup until the deploy
is accepted.

## Rules

- Production writes are human-only.
- Never expose MySQL, SOAP, or RA to the internet without a VPN/firewall and strong auth.
- Keep Warden enabled.
- Do not deploy from an agent session.
- Do not skip the backup.

## Open items

- Provider, region, domain, TLS/edge setup.
- Off-host backup storage.
- Monitoring and alerting.

## References

- [decisions/ADR-003-runtime-topology.md](../../decisions/ADR-003-runtime-topology.md)
- [decisions/OPEN-QUESTIONS.md](../../decisions/OPEN-QUESTIONS.md)
- [backup-restore.md](backup-restore.md)
- [health-check.md](health-check.md)
