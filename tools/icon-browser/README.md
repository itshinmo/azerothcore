# Icon Browser addon

In-game browser for every icon texture the 3.3.5a client ships. Search an icon, see whether it is
stock or Reforged, and copy its path for use in SQL, DBC, or addon work.

## Install

1. Copy `tools/icon-browser/` and rename the destination folder to `IconBrowser` in the 3.3.5a
   client:

   ```text
   World of Warcraft/Interface/AddOns/IconBrowser/
   ```

2. The folder must contain `IconBrowser.toc`, `IconBrowser.lua`, and `IconBrowserIcons.lua`.
3. Enable **Icon Browser** on the character-select AddOns screen.

## Use

```text
/icons
/iconbrowser
```

- Type in the search box to filter by substring, case-insensitive, live as you type.
- Click the source button to cycle `All sources` / `Stock only` / `Reforged only`.
- Page through the 8x6 grid with `< Prev` and `Next >`; the label shows the page and the match count.
- Hover an icon for its name, its source tag, and the copy hint.
- Click an icon to put `Interface\Icons\<name>` in the path box. It is selected; press Ctrl+C.
- Escape or the close button closes the frame.
- The 1 MB data file is parsed at login but the 30,830 entries are only ingested, sorted and
  indexed the first time you open the frame. That keeps the addon off the login budget.

A question-mark icon means the client cannot find that texture. The entry stays listed on purpose;
the list comes from the archives, so a broken patch load order shows up as question marks instead of
hiding the problem.

## Regenerate

The icon list is generated from the client archives:

```bash
python3 tools/icon-browser/gen_icon_list.py
python3 tools/icon-browser/gen_icon_list.py --check
```

- `--client` defaults to `~/Games/wotlk-clean`; `--out` defaults to `IconBrowserIcons.lua` next to
  the script.
- The generator reads `Data/*.MPQ` and `Data/enUS/*.MPQ` through `tools/client-patch/mpq.py`
  (StormLib, see `tools/client-patch/README.md`).
- An icon found in any archive other than `patch-I.MPQ` is `stock`; an icon found only in
  `patch-I.MPQ` is `reforged`.
- `--check` exits non-zero when the committed file is stale.
- A full run lists every archive (about a minute for the stock client).
- Current list: 30,830 icons, 6,308 stock and 24,522 Reforged.
- An unreadable archive, or a run that finds no icons at all, is an error rather than a partial
  list: skipping a stock archive would silently drop icons or relabel shared ones as Reforged, and
  `--check` would then call the lossy file up to date.

## Why a plain addon, not an MPQ

The addon only displays client data that is already installed. It adds no game content: no items, no
creatures, no spells, no client DBC rows, no textures. Same rule as the GM Helper addon, which is
also copied into `Interface/AddOns/` instead of packed. A client patch MPQ is for content the stock
client cannot load; browsing existing textures is not that.

## Files

| File | Purpose |
| --- | --- |
| `IconBrowser.toc` | Addon manifest, interface 30300, load order. |
| `IconBrowser.lua` | Frame, search, paging, source filter, tooltip, path copy. |
| `IconBrowserIcons.lua` | Generated icon list, one entry per line; 1.0 MB, not edited by hand. |
| `gen_icon_list.py` | Walks the client MPQs and writes the icon list. |
| `tests/test_addon.lua` | Offline addon test with mocked 3.3.5 widgets. |
| `tests/test_generate.py` | Generator parsing and staleness tests. |

## Tests

```bash
luajit tools/icon-browser/tests/test_addon.lua
python3 -m unittest discover -s tools/icon-browser/tests -v
```

The Lua test mocks only the widget surface the addon uses. It does not replace an in-client check of
layout, texture rendering, or Ctrl+C.
