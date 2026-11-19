---
name: test-wow-addon
description: Use when creating, changing, deploying, or debugging any in-game addon (tools/gm-addon/**). Runs the offline addon harness before and after every change, and uses client screenshots instead of asking the human to describe what they see.
---

# test-wow-addon

## Prerequisites

- `brew install lua` (provides `lua` and `luac`).
- `python3 -m pip install --user mpyq` (only when regenerating the frame list).
- The client copy with the addon: `~/Games/wotlk-test/Interface/AddOns/GMHelper/`.
- Read [runbook/gm/addon.md](../../../runbook/gm/addon.md) — especially "Client FrameXML quirks".

## Workflow

1. Edit in the repository only: `tools/gm-addon/` is the source of truth. Bump `## Version:` in
   `GMHelper.toc` and the load banner in `GMHelper.lua` on every change.
2. Syntax check every `.lua` with `luac -p` before anything else.
3. Run the offline harness — this is the mandatory test gate, before and after every change:

   ```bash
   lua tools/dev/addon-harness/run.lua tools/gm-addon/GMHelper.toc
   ```

   It validates every `CreateFrame` template and font object name against the client's real
   FrameXML, registers the slash command, clicks tabs and instance rows, clicks every Self-tab
   button, requires the exact self-only command forms, and flags text wider than its button.
   Non-zero exit = fix before touching the client.
4. If the addon starts using a new API, extend `tools/dev/addon-harness/mock-wow.lua` first so the
   harness covers it, then re-run.
5. Refresh the client's template/font list only after a client update:

   ```bash
   python3 tools/dev/addon-harness/extract-client-frames.py
   ```

6. Deploy by copying the changed files from `tools/gm-addon/` into the client's
   `Interface/AddOns/GMHelper/`, then verify with `md5 -q` that both copies match.
7. Visual verification: never ask the human to describe the UI. Ask them to press PrintScreen in
   game and read the PNGs from `~/Games/wotlk-test/Screenshots/` directly. The harness cannot render
   pixels; the screenshot is the only ground truth for look.
8. If the human reports "nothing changed", check the chat banner version first — the addon loads
   only at login, so a `/reload` is the usual missing step. A missing banner means the file did not
   load; run `/console scriptErrors 1`, then `/reload`, and read the error text.

## Constraints

- The server stays the permission gate; the addon wraps chat commands only and adds no permission
  path.
- No destructive buttons: bans, item grants, RBAC, and shutdown stay on the CLI/API.
- Secrets never enter the addon or the harness (no credentials in the client env, no account data
  in fixtures).
- Never hardcode a FrameXML template or font name that the harness has not validated against
  `tools/dev/addon-harness/client-frames.txt`.

## Useful commands

```bash
luac -p tools/gm-addon/*.lua                                   # syntax
lua tools/dev/addon-harness/run.lua tools/gm-addon/GMHelper.toc # offline test gate
python3 tools/dev/addon-harness/extract-client-frames.py        # refresh frame list
md5 -q tools/gm-addon/GMHelper.lua ~/Games/wotlk-test/Interface/AddOns/GMHelper/GMHelper.lua
```

## Expected output

- Harness `PASS: addon loads, slash registered, clicks send commands` with zero template, font, or
  overflow warnings.
- Deployed copies hash-identical to the repository.
- For visual changes: a screenshot showing the new look, read from the Screenshots folder.

## References

- [runbook/gm/addon.md](../../../runbook/gm/addon.md) — install, test steps, client FrameXML quirks
- `tools/dev/addon-harness/` — extractor, mock API, runner, `client-frames.txt`
