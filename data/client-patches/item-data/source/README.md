# Frozen world-treasure inputs

Read-only input snapshot for the `items.json` generator and the `patch-X` validator. These files are
not applied by this branch and are not the authoritative copy; the world-treasures feature owns the
originals.

| File | Origin | SHA256 |
|------|--------|--------|
| `batch_01.csv` | `local-server-setup:specs/world-treasures/batch_01.csv` | `cdc5416b4942776d09d78504c6051ddaa65c81452a5634993052c6e31a75fba3` |
| `world_treasures_batch_01.sql` | `local-server-setup:data/sql/custom/db_world/world_treasures_batch_01.sql` | `6c1505b6bac14ec05fd62827a9f3aefd10e0fa3695d65d187e5f2f38191fe117` |
| `world_treasures_item_dbc.sql` | `local-server-setup:data/sql/custom/db_world/world_treasures_item_dbc.sql` | `c4baf35aa3b79e16c6cfb89d9fe8de3cd4b685e727ac39ac8ded05ccdf619504` |

Refresh all three together when the world-treasures batch changes, run
`python3 data/client-patches/item-data/generate_items.py --write`, then rebuild `patch-X`.
When the canonical paths exist in your checkout (after merging `local-server-setup`), compare against
them before refreshing the snapshot:

```bash
python3 data/client-patches/item-data/generate_items.py --check \
  --batch-csv specs/world-treasures/batch_01.csv \
  --batch-sql data/sql/custom/db_world/world_treasures_batch_01.sql \
  --item-dbc-sql data/sql/custom/db_world/world_treasures_item_dbc.sql
```

`world_treasures_item_dbc.sql` is the server mirror. It is separate from a full server
`DataDir/dbc/Item.dbc` replacement; see [../README.md](../README.md).
