# GM command handbook

## When to use

A GM needs a command, its permission, its side effects, or a safe example. In-game `.help <command>`
is authoritative for exact syntax; this handbook is the workflow and safety layer. The generated
[command-index.md](command-index.md) lists every command and its RBAC permission.

## Danger levels

| Level | Meaning | Approval |
|-------|---------|----------|
| read | lookup, inspect | none |
| low | teleport, GM mode, temporary spawn | none |
| medium | item/mail grant, quest state, instance reset | role permission |
| high | ban, mass mail, despawn, economy grant | human + audit |
| critical | shutdown, RBAC, character delete, database-wide | human + backup + audit |

## Lookup and inspection

```text
.lookup player account <account>
.lookup player ip <ip>
.lookup player email <email>
.lookup creature <name|id>
.lookup item <name|id>
.lookup object <name|id>
.lookup quest <name|id>
.lookup spell <name|id>
.lookup teleport <name>
.lookup map <id|name>
.lookup area <id|name>
.npc info
.npc guid
.quest status <quest> [player]
.character deleted list <name>   # deleted characters only; confirm with .help
```

## Player care

```text
.pinfo <player|#guid>              # blocked when target has higher security
.mute <player> <time> [reason]     # time like 1d15h33s
.unmute <player>
.mutehistory <account>             # account name, not character name
```

A support role cannot inspect or mute an admin character. Compare GM levels, not only RBAC
permissions, before acting on a target.

## Movement and testing

```text
.tele <location>
.tele name <player> <location>
.tele id <id>
.tele group <location>
.gm on
.gm off
.gm visible
.gm fly
.gm list
```

Do not use `.gm on` during combat to avoid a test. Use the e2e damage helpers.

## NPC and gameobject testing

```text
.npc add [temp] [formation|item|move]
.npc delete
.npc set <entry|faction|flag|level|model|phase|spawntime|wanderdistance|data|link>
.npc move
.npc say <text>
.npc yell <text>
.npc emote <emote>
.npc showloot
.npc spawngroup
.npc despawngroup
```

Temporary spawns must be removed after the test. Permanent spawns need tracked SQL, not `.npc add`.

## Quests

```text
.quest add <quest> [player]
.quest complete <quest> [player]
.quest remove <quest> [player]
.quest reward <quest> [player]
.quest status <quest> [player]
```

## Items and economy

```text
.additem <item> [count] [player]   # confirm with .help
.send items <player> "<subject>" "<text>" <item>:<count>
.send money <player> "<subject>" "<text>" <amount>
```

Use the future audited website or a wrapped command for purchases and refunds. Never grant from a screenshot alone.

## Instances

```text
.instance listbinds
.instance unbind <map|all> [difficulty] [player]
.instance setbossstate <encounter> <state> [player]
.instance getbossstate <encounter> [player]
.instance savedata
.instance stats
```

There is no `.instance reset`. A full reset is unbind plus boss-state reset, or a restart.

## Reload

```text
.reload all
.reload creature_template
.reload quest_template
.reload item_template
.reload npc_vendor
.reload spell_proc
.reload spell_scripts
.reload config
```

Reload re-reads a table; it does not apply SQL. Apply SQL first, then reload.

## Server and accounts

```text
.server info
.server shutdown <delay> [reason]
.server restart <delay> [reason]
.server set loglevel <n>
.server set motd <text>
.account create <user> <password> [email]
.account set gmlevel <user> <level> [realm]
.account password <user> <newpassword>
.account set addon <user> <0|1>
```

## Events and debug

```text
.event start <id>
.event stop <id>
.event activelist
.event info <id>
.debug threat
.debug threatinfo
.debug getvalue <field> [target]
.debug setvalue <field> <value> [target]
.debug cooldown
.debug play sound <id>
```

## Rules

- Use the smallest role.
- Confirm the target before a write.
- Record high/critical actions. Command attempts are audited in `acore_auth.gm_audit_log`; see
  [audit.md](audit.md).
- Remove temporary spawns and test items.
- Never share a GM account.
- Never run a mass command without approval.
- Never post player data or secrets.

## References

- [rbac-roles.md](rbac-roles.md)
- [audit.md](audit.md)
- [item-grant-refund.md](item-grant-refund.md)
- [incident-response.md](incident-response.md)
- [src/server/scripts/Commands](../../src/server/scripts/Commands)
