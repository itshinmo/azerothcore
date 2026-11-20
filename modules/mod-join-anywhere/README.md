# mod-join-anywhere

Queue-from-anywhere (RFC-003 Group D, ADR-024): player command `.queue bg <wsg|ab|av|eots|sota|ic|random>`
joins a battleground queue solo, from anywhere — no battlemaster walk. The command shape follows
RFC-003's ".join ab" reference, renamed `.queue` because `/join` is the client's reserved channel
command.

- The eligibility ladder mirrors the core battlemaster join path (deserter debuff, level access,
  queue-slot limits, LFG conflicts, arena-queue conflicts, DK starting-zone gate) and runs the
  same script hook (`OnPlayerCanJoinInBattlegroundQueue`) — group queueing stays NPC-only by
  design (a remote group join needs the leader co-located anyway).
- Permission: `Command: queue bg (project)` (RBAC 950150, project range), granted to the Player
  Commands role by `data/sql/custom/db_auth/queue_anywhere_command.sql` (self-applies).
- The command does not bypass any queue rule; it removes only the walk. Weekend bonuses, XP
  rates, and bracket rules all apply exactly as at a battlemaster.
