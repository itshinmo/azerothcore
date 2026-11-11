# Common queries

Read-only queries for support and content work. Replace `?` with a value. Never run a write from this
page without the procedure in [apply-sql-update.md](../operation/apply-sql-update.md).

## Accounts

```sql
-- by username
SELECT id, username, email, last_login FROM acore_auth.account WHERE username = ?;

-- GM access
SELECT aa.id, a.username, aa.gmlevel, aa.RealmID
FROM acore_auth.account_access aa
JOIN acore_auth.account a ON a.id = aa.id
WHERE a.username = ?;

-- active bans
SELECT * FROM acore_auth.account_banned
WHERE id = ? AND active = 1
ORDER BY unbandate DESC;
```

## Characters

```sql
-- by name
SELECT guid, account, name, race, class, level, online
FROM acore_characters.characters WHERE name = ?;

-- by account
SELECT guid, name, level, online
FROM acore_characters.characters WHERE account = ?;

-- online characters
SELECT guid, account, name, level, map, position_x, position_y, position_z
FROM acore_characters.characters WHERE online = 1;
```

## Inventory and mail

```sql
SELECT ci.bag, ci.slot, ii.itemEntry, ii.count
FROM acore_characters.character_inventory ci
JOIN acore_characters.item_instance ii ON ii.guid = ci.item
WHERE ci.guid = ?;

SELECT m.id, m.sender, m.subject, m.money, m.has_items
FROM acore_characters.mail m
WHERE m.receiver = ?;
```

## Quests

```sql
SELECT quest, status, rewarded
FROM acore_characters.character_queststatus
WHERE guid = ? AND quest = ?;
```

## Instances

```sql
SELECT instance, map, difficulty, completedEncounters, data
FROM acore_characters.instance
WHERE map = ?;

SELECT * FROM acore_characters.character_instance
WHERE guid = ?;
```

## Content

```sql
SELECT entry, name, minlevel, maxlevel, faction, npcflag, AIName, ScriptName
FROM acore_world.creature_template WHERE entry = ?;

SELECT guid, id1, map, position_x, position_y, position_z
FROM acore_world.creature WHERE id1 = ?;

SELECT ID, LogTitle, QuestLevel, MinLevel, RewardMoney
FROM acore_world.quest_template WHERE ID = ?;

SELECT entry, name, class, subclass, Quality, ItemLevel, RequiredLevel
FROM acore_world.item_template WHERE entry = ?;
```

## Updates

```sql
SELECT name, state, timestamp, speed
FROM acore_world.updates
ORDER BY timestamp DESC
LIMIT 20;

SELECT * FROM acore_world.updates_include;
```

## Counts

```sql
SELECT COUNT(*) AS creatures FROM acore_world.creature;
SELECT COUNT(*) AS quests FROM acore_world.quest_template;
SELECT COUNT(*) AS items FROM acore_world.item_template;
SELECT COUNT(*) AS accounts FROM acore_auth.account;
SELECT COUNT(*) AS characters FROM acore_characters.characters;
```

## Rules

- Use the primary key or a narrow indexed filter.
- Add `LIMIT` to exploratory queries.
- Do not run `SELECT *` on large tables without a filter.
- Do not paste results with player data into a public channel.
