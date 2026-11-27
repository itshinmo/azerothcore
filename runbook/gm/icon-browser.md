# Icon Browser addon

## When to use

You need the exact `Interface\Icons\...` path for a custom item, spell, map pin, or quest reward, and
you want to see the artwork before choosing. The addon shows every icon texture the client can load
and copies the path.

## Install

Copy the addon folder into the 3.3.5a client:

```text
World of Warcraft/Interface/AddOns/IconBrowser/
```

It must contain:

```text
IconBrowser.toc
IconBrowser.lua
IconBrowserIcons.lua
```

Enable **Icon Browser** on the character-select AddOns screen, then log in. This is a plain addon
folder, not an MPQ: it displays data the client already ships and adds no game content, the same
rule the GM Helper follows.

## Open

```text
/icons
/iconbrowser
```

`/icons` toggles the frame; Escape also closes it.

## Use

- Type in the search box to filter by substring, case-insensitive, live as you type.
- The source button cycles **All sources**, **Stock only**, **Reforged only**.
- `< Prev` and `Next >` page through the 8x6 grid. The label shows the page and the match count.
- Hover an icon for its name, its source, and the copy hint.
- Click an icon and its path is placed in the path box already selected. Press Ctrl+C.

Reforged icons come from `Data/patch-I.MPQ` and only render on a client that has that archive. An
icon that shows a question mark is listed in an archive but cannot be loaded; the entry stays
visible on purpose, so a broken patch order shows up instead of hiding.

## Regenerate

The list comes from the client archives:

```bash
python3 tools/icon-browser/gen_icon_list.py
python3 tools/icon-browser/gen_icon_list.py --check
```

Run it after a client or patch change and commit the regenerated `IconBrowserIcons.lua`. An
unreadable archive or an empty result is an error, not a partial list.

## Limits

- It reads the archives through StormLib, so it needs the same environment as the rest of
  `tools/client-patch/`.
- The data file is about 1 MB and is parsed at login, but the entries are only indexed the first
  time the frame opens.
- It is a lookup tool. It does not validate that an icon suits a use, and it does not change the
  client, the database, or any patch.

## References

- [tools/icon-browser/README.md](../../tools/icon-browser/README.md)
- [addon.md](addon.md) — the GM Helper addon, same install rule
- [client-patch.md](../operation/client-patch.md) — when an icon needs to ship in an MPQ instead
