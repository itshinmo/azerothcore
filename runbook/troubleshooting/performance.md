# Performance

## Symptoms

High world update time, lag, slow logins, slow map loads, high memory, or database stalls.

## Measure first

1. Update-time summary in `Server.log`:

   ```bash
   grep -nE 'Update time diff|Last 500 diffs|Mean|Percentiles' env/dist/logs/Server.log | tail -n 40
   ```

2. Process resources:

   ```bash
   ps -o pid,pcpu,pmem,rss,etime,command -p "$(pgrep -f worldserver)"
   top -pid "$(pgrep -f worldserver)"
   ```

3. Disk and MySQL:

   ```bash
   df -h
   mysql -u acore -p -e "SHOW GLOBAL STATUS LIKE 'Threads_connected'; SHOW GLOBAL STATUS LIKE 'Slow_queries';"
   ```

4. Slow query log, if enabled. Use `EXPLAIN` on the suspect query.

## Common causes

| Symptom | Cause | Action |
|---------|-------|--------|
| High update time | too many creatures/maps, expensive AI, DB stalls | profile map/creature counts, slow queries |
| One core pegged at 100% with no players | console thread spinning on EOF | run under screen/tty or set `Console.Enable=0` |
| Slow login | large character data, DB latency, addon queries | check DB and character rows |
| Slow map load | missing/fragmented mmaps, disk | move data to NVMe, re-extract |
| Memory growth | leak, unbounded cache, many instances | reproduce, inspect, restart as mitigation |
| DB CPU high | missing index, bad query, large table scan | `EXPLAIN`, add index |
| Network lag | bandwidth, packet loss, host overload | check host and network |

## Rules

- Do not tune blindly; measure before and after.
- Do not add an index without checking the query plan and write cost.
- Do not raise map/network thread counts without evidence.
- Do not restart production as a "fix" without recording the state.
- A performance change is T2 or T3 and needs before/after numbers.

## Verification

- Update-time mean and p99 are within the previous baseline or better.
- Login and the affected feature are normal.
- No new errors.
- The measurement method and numbers are recorded.

## References

- [logs-and-monitoring.md](../operation/logs-and-monitoring.md)
- [specs/server.md](../../specs/server.md)
- [.agents/docs/cpp-guidelines.md](../../.agents/docs/cpp-guidelines.md)
