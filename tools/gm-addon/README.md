# GM Helper addon

In-game command menu for GMs. It wraps existing chat commands; the server still enforces RBAC and
writes the audit record.

## Install

1. Copy `tools/gm-addon/` and rename the destination folder to `GMHelper` in the 3.3.5a client:

   ```text
   World of Warcraft/Interface/AddOns/GMHelper/
   ```

2. The folder must contain `GMHelper.toc` and `GMHelper.lua`.
3. Enable **GM Helper** on the character-select AddOns screen.

## Use

```text
/gmhelper
/gmh
```

The frame has:

- server status and instance binds
- GM mode toggle
- visible-to-players and hidden-from-players buttons
- unstuck
- target `pinfo` and `npc info`
- item, creature, quest, spell, and player-account lookup
- teleport by location name

Pair it with the role presets. A `support` account can use lookup and unstuck; `additem` and other
higher commands are still denied by the server.

## Limits

- The GM mode label tracks the button request, not server confirmation. It starts at off after
  `/reload`. A denied command, a chat-typed change, or a combat-blocked click can desync it; click
  it once to resync. Combat clicks do not flip the label.
- Visibility is two explicit buttons, not a toggle. Hiding is security-sensitive; the addon does not
  guess the server state.
- No destructive buttons. Bans, item grants, RBAC, and shutdown stay on the CLI/API until the future
  website provides confirmation and audit flows.
- The addon does not store credentials and does not bypass server checks.
- Command output still appears in the chat frame.
