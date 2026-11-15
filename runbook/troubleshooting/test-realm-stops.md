# Test realm stops after the client exits

## Symptoms

After quitting the game, `make test-realm CMD=status` reports both test servers stopped.
`screen -ls` shows dead `ac-test-<repo>-authserver` and `ac-test-<repo>-worldserver` sessions.

## What the repository does

`tools/dev/test-realm.sh start` starts `worldserver` and `authserver` in detached `screen -dmS`
sessions. `stop` sends SIGTERM, then SIGKILL. Nothing in the repository stops the test realm when a
game client logs out. The test realm is meant to stay up across client sessions.

Each server runs under a small wrapper that appends its start, signals, and exit status to
`env/test/logs/<name>.supervisor.log` (see below).

## Checks

1. Status, ports, and processes:

   ```bash
   make test-realm CMD=status
   screen -ls
   lsof -nP -iTCP:3824 -sTCP:LISTEN
   lsof -nP -iTCP:8185 -sTCP:LISTEN
   ```

2. Logs:

   ```bash
   tail -n 100 env/test/logs/worldserver.console.log
   tail -n 100 env/test/logs/Server.log
   tail -n 100 env/test/logs/Auth.log
   cat env/test/logs/Errors.log
   cat env/test/logs/worldserver.supervisor.log
   cat env/test/logs/authserver.supervisor.log
   ```

3. How the realm and the client were started. The repository does not tie them together. A wrapper
   or launcher that runs `make test-realm CMD=stop` on client exit, or a supervisor or OS event that
   kills the `screen` sessions, will stop them. The sessions are detached from the terminal.

4. If the logs show a crash or a shutdown line at logout, capture the full tail and treat it as a
   server bug. If `Errors.log` is empty and the console log ends at startup, the process may have
   been killed by SIGKILL or an external supervisor; that is not proof of a crash.

## Observed on 2026-11-14

- Started with `make test-realm CMD=start`; the client was launched with the WoWSilicon wrapper.
- After quitting the client, both test servers were stopped.
- `screen -ls` showed dead auth and world sessions.
- `Errors.log` was empty. `Server.log` reached "ready"; `worldserver.console.log` ended during
  startup, consistent with buffered output and a process kill.
- Root cause not confirmed. The start script does not stop on client logout.

## Supervisor log

`start_one` runs each server under a wrapper that writes to `env/test/logs/<name>.supervisor.log`:

```text
2026-11-15T16:13:54 worldserver start pid=21900
2026-11-15T16:14:04 worldserver exit=0
```

- `start pid=` is the wrapper PID. The server is its child, a few PIDs higher.
- `signal=HUP|INT|TERM` means the wrapper received that signal and forwarded SIGTERM to the server.
- `exit=N` is the recorded server status. `0` is a clean stop, including
  `make test-realm CMD=stop`: both servers install a SIGTERM handler that exits 0. `129`, `137`, and
  `143` mean the server ended on SIGHUP, SIGKILL, or SIGTERM without that handler running. When a
  `signal=` line is followed by `143`, either the server died before the handler ran or the wrapper's
  interrupted `wait` recorded the signal; treat the `signal=` line as the cause and confirm with the
  console log.
- A missing line after `start` has two causes: the wrapper was killed too (group signal or SIGKILL),
  or `cd` into the binary directory failed (the wrapper exits 1 before the server starts). Capture
  `screen -ls`, `ps`, and the unified log described in the checks above.

## Investigated 2026-11-15

- One full client session (login 14:19:58, back to character list 14:52:51, quit) left both
  servers running, ports 3824 and 8185 bound, for 40+ minutes. The supervisor log had `start` as its
  last line for both. The 2026-11-14 death did not repeat.
- `wineserver -k` against the CrossOver bottle while the game was running did not stop the realm.
  No supervisor line was written.
- The WoWSilicon force quit does not target native processes. In the upstream source
  (`Sources/WoWSiliconSwift/Services/LaunchService.swift`, `forceQuitWine()`) it runs
  `wineserver -k`; only if a Wine application process is still alive after 2 seconds does it SIGKILL
  the PIDs matched by `WineProcessMonitor` (Wine host binaries, the Wine service executables,
  `rosettax87`, `x87sidecar`, and command lines containing a Windows path). That predicate does not
  match `worldserver`, `authserver`, their `bash` wrappers, or the `screen` daemons.
- Conclusion: the force quit is not the cause. The 2026-11-14 death is still unexplained; capture the
  supervisor log on the next occurrence.

## Workarounds

- Start with `make test-realm CMD=start`. If a custom launcher starts both the realm and the client,
  remove the cleanup that stops the realm on client exit.
- For a fully detached service, use a `launchd` job (macOS) or a `systemd` unit (Linux), or a
  persistent `tmux`/`screen` session. `screen -dmS` is already detached from the terminal; check for
  an external killer.
- Remove stale screen sockets with `screen -wipe`; a dead session is not a running server.

## Verification

After quitting the client:

```bash
make test-realm CMD=status
```

Both servers must still be running and ports 3824 and 8185 must still be listening. `Server.log` should
show the player login and logout; `Auth.log` should show the account authentication, not a shutdown.

## References

- [runbook/operation/test-realm.md](../operation/test-realm.md)
- [tools/dev/test-realm.sh](../../tools/dev/test-realm.sh)
- [specs/testing-and-release.md](../../specs/testing-and-release.md)
