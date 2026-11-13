# GM addon

## When to use

A GM wants common commands without typing full chat commands, while staying inside the server's RBAC
and audit rules.

## Install

Copy the addon folder into the 3.3.5a client:

```text
World of Warcraft/Interface/AddOns/GMHelper/
```

It must contain:

```text
GMHelper.toc
GMHelper.lua
```

Enable **GM Helper** on the character-select AddOns screen, then log in.

## Open

```text
/gmhelper
/gmh
```

## What it does

- `.server info`
- `.instance listbinds`
- `.gm on` / `.gm off` behind one **GM mode** toggle
- `.gm visible on` and `.gm visible off` as explicit **Visible to players** / **Hidden from players** buttons
- `.unstuck`
- `.pinfo <target>`, `.npc info`
- `.lookup item|creature|quest|spell|player account <text>`
- `.teleport <location>`

Every button sends the normal chat command. The addon does not call the database and does not add a
permission path.

The GM mode button tracks the request, not server confirmation. It starts at off after `/reload`; a
denied command, a chat-typed change, or a combat-blocked click can desync it, so click once to
resync. Combat clicks do not flip the label. Visibility stays as two explicit buttons because hiding
is security-sensitive and the client cannot reliably read the server state.

## Test

1. Log in with a role account on the test realm.
2. Run `/gmhelper`.
3. Click `.server info`; output appears in chat.
4. Click **GM mode** twice; chat shows `.gm on` then `.gm off`, and the label follows.
5. Enter combat and click **GM mode**; the label must stay unchanged.
6. Click **Visible to players**, then **Hidden from players**; run `.gm visible` to confirm each state.
7. Look up an item; it works for `support` and above.
8. Type into each lookup and teleport field; the full input box and text must be visible.
9. Try a command the role does not have, such as `.additem` from `support`; the server denies it.
10. Confirm attempts in `acore_test_auth.gm_audit_log` on the test realm (or `acore_auth` locally),
    or via the GM API.

Checked on the local realm on 2026-11-13: menu, GM mode toggle, visibility buttons, lookups,
teleport, and input rendering. Test realm client login remains unverified; use the local realm for
client checks.

## Security

- The server remains the permission gate.
- The addon stores no credentials.
- No destructive buttons. Bans, grants, RBAC, and shutdown stay on the CLI/API until the future
  website provides confirmation and audit flows.
- Command output can contain player data; do not paste it into public channels.

## Troubleshooting

- Addon not listed: check the folder name is `GMHelper`, not `gm-addon`.
- `/gmhelper` unknown: enable the addon and `/reload`.
- A button does nothing: the command was denied, the target is missing, or the player is in combat.
- Wrong role: check the role grant with `.rbac account list` or the RBAC runbook.

## References

- [command-handbook.md](command-handbook.md)
- [rbac-roles.md](rbac-roles.md)
- [audit.md](audit.md)
- [tools/gm-addon/README.md](../../tools/gm-addon/README.md)
