# Client DBC patch: whole-file replacement

## When to use

A feature needs the **client** to change a DBC table, and server data alone cannot do it. Example:
`CharBaseInfo.dbc` controls which race/class buttons the creation screen enables; the server never
reads it.

This procedure builds one MPQ v1 archive with whole-file DBC replacements. It does not patch the
executable, DLLs, or vendor archives. It is data-only and reversible by deleting the archive.

## Prerequisites

- the supported client in a scratch copy, never the live play client;
- `stormlib` (`brew install stormlib`) and the client-patch tool from the client-patch branch
  (`tools/client-patch/client_patch.py`, or its merged equivalent);
- Python 3;
- the effective source archive resolved with `client_patch.py which`.

Branch status: the tooling and ADR-027 are merged into `local-server-setup`. This runbook is the
recipe for that pipeline; do not create a competing tool. If the
tooling is not available, use StormLib directly for list/read/pack; the DBC rewrite steps below are
unchanged.

## Source resolution

The source is the **highest-priority archive below the project archive that will carry the file**.
Do not assume the locale archive is stock: an Ascension-modified locale archive can add rows.

```bash
python3 tools/client-patch/client_patch.py which "$CLIENT/Data" 'DBFilesClient\CharBaseInfo.dbc'
python3 tools/client-patch/client_patch.py which "$CLIENT/Data" 'DBFilesClient\CharStartOutfit.dbc'
```

Record every archive in the chain, the winner, the row count, the byte size, and the SHA256. A file
that is only in a modified locale archive is based on that modified file, not on a clean stock table.

## Rewrite the DBC

Work on extracted files under a scratch directory. Keep the header fields and record size; change
only the row count and, for new rows, the row bytes.

```python
import struct

def read_dbc(path):
    data = open(path, "rb").read()
    magic, rows, fields, record_size, string_size = struct.unpack("<4sIIII", data[:20])
    body = data[20:20 + rows * record_size]
    strings = data[20 + rows * record_size:]
    return magic, rows, fields, record_size, string_size, body, strings

def write_dbc(path, magic, fields, record_size, string_size, rows, strings):
    out = magic + struct.pack("<IIII", len(rows), fields, record_size, string_size)
    out += b"".join(rows) + strings
    open(path, "wb").write(out)
```

For a pair table such as `CharBaseInfo` (2 fields, 2-byte rows), append two bytes per new pair, sort
by the key, and rewrite the header row count:

```python
magic, rows, fields, record_size, string_size, body, strings = read_dbc(src)
new_rows = [body[i * record_size:(i + 1) * record_size] for i in range(rows)]
new_rows += [bytes([race, cls]) for race, cls in [(2, 8), (3, 8), (7, 5), (8, 9), (10, 1)]]
new_rows.sort()
write_dbc(dst, magic, fields, record_size, string_size, new_rows, strings)
```

For `CharStartOutfit` (77 declared fields, **296-byte physical rows**), copy the **full source row**
and change only the ID, RaceID, ClassID, and SexID. Copying only the item columns loses the display
IDs and inventory slots the client preview uses:

```python
row = bytearray(source_row)
struct.pack_into("<I", row, 0, new_id)  # ID
row[4], row[5], row[6] = race, cls, gender  # RaceID, ClassID, SexID
```

Record-size warning: do **not** compute `record_size = field_count * 4` for this table. The format is
`dbbbX` + 24 `i` + 48 `x`; `b` and `X` are one byte, `d` is the sort field, and `x` is four bytes:
4 + 3×1 + 1 + 24×4 + 48×4 = **296**. The source header says 296; 20 + 126×296 + 1 = 37,317 bytes. A
308-byte stride misaligns every row. Assert before packing:

```python
assert fields == 77 and record_size == 296
assert len(data) == 20 + rows * record_size + string_size
```

Verify before packing:

- the header still says `WDBC`;
- the field count and record size are unchanged;
- the row count is the expected total;
- the string block is unchanged;
- the new rows are present exactly once;
- the SHA256 is recorded.

## Pack the archive

Put the files under a scratch root so the archive paths are exact:

```text
root/DBFilesClient/CharBaseInfo.dbc
root/DBFilesClient/CharStartOutfit.dbc
```

Pack MPQ v1 with zlib, listfile, and attributes:

```bash
python3 tools/client-patch/client_patch.py pack /tmp/patch-V.MPQ /tmp/root --force
python3 tools/client-patch/client_patch.py inspect /tmp/patch-V.MPQ
python3 tools/client-patch/client_patch.py list /tmp/patch-V.MPQ
```

The archive loads as a base alphabetic patch on the English client. It must be the highest-priority
archive that carries each file. Check with `which` after installing into a scratch Data tree:

```bash
python3 tools/client-patch/client_patch.py which "$CLIENT/Data" 'DBFilesClient\CharBaseInfo.dbc'
python3 tools/client-patch/client_patch.py which "$CLIENT/Data" 'DBFilesClient\CharStartOutfit.dbc'
```

Both winners must be `patch-V.MPQ`. If a locale alphabetic patch or a later project archive wins,
move the file to that archive; never ship two carriers.

## Store the artifact

Store the patch in the repository, not only on the client, under the client-patch ledger contract
([data/client-patches/README.md](../../data/client-patches/README.md)):

```text
data/client-patches/<feature>/
  build.py
  dist/patch-<letter>.MPQ
  manifest.json
  README.md      # source, hashes, install, test, rollback
```

Add the ledger row in the same change. Keep the archive and DBC files binary in `.gitattributes`
(`*.MPQ`, `*.mpq`, `*.dbc`, `*.DBC`, `*.blp`, `*.m2`, `*.skin`, `*.anim`,
`data/client-patches/** -text`) and verify `git hash-object --path=<file>` equals
`--no-filters` before committing.

## Server side

Some DBCs are also server data. For `CharStartOutfit.dbc`, place the **same bytes** in
`DataDir/dbc/CharStartOutfit.dbc` and restart the worldserver, so the server starting kit and the
client preview use one table. `CharBaseInfo.dbc` is client-only; the server never reads it.

## Verification

- `client_patch.py verify /tmp/patch-V.MPQ` passes;
- `inspect` shows MPQ v1, zlib, listfile, attributes, the expected file count and sizes;
- `which` shows the intended winner and a single carrier;
- the client creation screen shows the new state (class button, preview);
- the server log has no `sql.sql` or DBC load errors;
- the owner tests on a scratch client before the live bundle is updated.

## Rollback

Delete the archive from the client `Data/` directory. If a server `DataDir` DBC was replaced, restore
the backup and restart. No registry state remains.

## Security and licensing

- No executable content, no `Wow.exe`/DLL edits, no vendor archive edits.
- No vendor assets without a recorded license, source, and hash; the project ships only
  project-authored changes.
- No secrets, player data, or internal hostnames in the archive or manifest.
- Agents never install into the live client; the owner installs and tests.

## References

- [client bundle](../operation/client-bundle.md)
- [content pipeline](../../specs/content-pipeline.md)
- [ADR-027](../../decisions/ADR-027-client-patch-pipeline.md)
- [RFC-007](../../rfcs/active/RFC-007-race-class-combos.md)
