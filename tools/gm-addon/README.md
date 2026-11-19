# GM Helper addon

In-game command menu for GMs. It wraps existing chat commands; the server still enforces RBAC and
writes the audit record.

## Install

1. Copy `tools/gm-addon/` and rename the destination folder to `GMHelper` in the 3.3.5a client:

   ```text
   World of Warcraft/Interface/AddOns/GMHelper/
   ```

2. The folder must contain `GMHelper.toc`, `GMHelper.lua`, and `GMHelperInstances.lua`.
3. Enable **GM Helper** on the character-select AddOns screen.

## Use

```text
/gmhelper
/gmh
```

The frame has three tabs.

### Commands

- server status and instance binds
- GM mode toggle
- visible-to-players and hidden-from-players buttons
- unstuck
- target `pinfo` and `npc info`
- item, creature, quest, spell, and player-account lookup
- teleport by location name

### Instances

Every dungeon and raid in the game, in two scrollable columns: Dungeons on the left, Raids on the
right, each grouped by expansion separators. Click an instance to teleport to its entrance (`.go
xyz` with the entrance coordinates from `areatrigger_teleport`). The tooltip shows the map id and
level range. The list comes from `GMHelperInstances.lua`; regenerate it after client-data or
database changes with:

```bash
python3 tools/dev/gen-instance-manifest.py
```

### Self

Every command acts on the GM's own character, even with another player targeted.

- cheat toggles: `.cheat god`, `.cheat power`, `.cheat cooldown`, `.cheat casttime`,
  `.cheat explore 1/0`
- `.combatstop`
- `.character level <own name> 80`, `.revive <own name>`
- `.modify speed 2` and back to 1 (walk, run, swim, and flight speed; this core has no `run`
  subcommand)
- `.modify money 1000g` — 1k gold
- `.additem <own name> 51809 4` — four Portable Hole 24-slot normal bags
- `.instance unbind all <own name>` and `.instance listbinds`

Pair it with the role presets. A `support` account can use lookup and unstuck; `additem` and other
higher commands are still denied by the server.

## Limits

- The GM mode label tracks the button request, not server confirmation. It starts at off after
  `/reload`. A denied command, a chat-typed change, or a combat-blocked click can desync it; click
  it once to resync. Combat clicks do not flip the label.
- Visibility is two explicit buttons, not a toggle. Hiding is security-sensitive; the addon does not
  guess the server state.
- The Self tab cheat buttons have no state label on purpose: they are server-side toggles and the
  addon cannot read the server state. Click once to flip, click again to flip back.
- Give-to-self buttons are limited to the two the owner asked for (gold, bags); other grants stay
  on the CLI/API until the future website provides confirmation and audit flows.
- The addon does not store credentials and does not bypass server checks.
- Command output still appears in the chat frame.
