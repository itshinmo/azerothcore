# Schema guide

## When to use

Before querying or editing a table, designing content, or debugging a data problem.

## Databases

| Database | Holds |
|----------|-------|
| `acore_auth` | accounts, `account_access`, `realmlist`, bans, session keys, logs |
| `acore_characters` | characters, inventory, quests, mail, guilds, arena, achievements |
| `acore_world` | creature/item/quest/gameobject templates, spawns, loot, SmartAI, conditions |

## Auth tables

| Table | Purpose |
|-------|---------|
| `account` | username, salt, verifier, email, last login |
| `account_access` | GM level per account and realm (`RealmID = -1` for all) |
| `realmlist` | realm name, address, port, build |
| `account_banned` | active and historical bans |
| `ip_banned` | IP bans |
| `rbac_*` | permissions, linked permissions, account grants |
| `logs`, `logs_ip_actions` | server and IP action logs |

There is no `gmlevel` column on `account`; use `account_access`.

## Character tables

| Table | Purpose |
|-------|---------|
| `characters` | account, name, race, class, level, map, position, online flag |
| `character_inventory` | item ownership, bag, slot |
| `item_instance` | item data, durability, enchantments |
| `character_queststatus` | quest state per character |
| `character_queststatus_rewarded` | rewarded quests |
| `mail` / `mail_items` | mail and attached items |
| `guild` / `guild_member` | guilds |
| `character_instance` | instance binds |
| `character_achievement` | achievements |
| `character_skills`, `character_spell`, `character_talent` | progression |

## World tables

| Table | Purpose |
|-------|---------|
| `creature_template` | NPC stats, flags, AI, script, loot |
| `creature_template_model` | display models and probability |
| `creature` | spawn rows (`guid`, `id1`, map, position) |
| `creature_addon` | spawn addon: path, mount, auras |
| `creature_queststarter` / `creature_questender` | quest giver links |
| `npc_vendor` | vendor items and costs |
| `gossip_menu` / `gossip_menu_option` / `npc_text` | gossip |
| `quest_template` / `quest_template_addon` | quest definition and chain |
| `quest_details` / `quest_offer_reward` / `quest_request_items` | quest text |
| `item_template` | items, spells, stats, prices |
| `gameobject_template` / `gameobject` | gameobjects and spawns |
| `smart_scripts` | SmartAI event/action/target rows |
| `conditions` | polymorphic conditions |
| `instance_template` / `instance_encounters` | instance definition and boss credit |
| `creature_loot_template` / `gameobject_loot_template` / `reference_loot_template` | loot |
| `spell_script_names` | C++ spell/aura script binding |
| `spell_dbc` / `map_dbc` / `areatable_dbc` / `item_dbc` | server-side DBC overlays |
| `updates` / `updates_include` | schema updater state |

## Relationships

- `creature.id1` → `creature_template.entry`.
- `creature.guid` → `creature_addon.guid`.
- `creature_template.entry` → `creature_queststarter.id`, `creature_questender.id`.
- `creature_template.gossip_menu_id` → `gossip_menu.MenuID`.
- `gossip_menu.TextID` → `npc_text.ID`.
- `npc_vendor.entry` → `creature_template.entry`; `npc_vendor.item` → `item_template.entry`.
- `quest_template.ID` → `quest_template_addon.ID`, `quest_details.ID`, `quest_offer_reward.ID`.
- `creature_queststarter.quest` / `creature_questender.quest` → `quest_template.ID`.
- `gameobject_template.entry` → `gameobject.id1`.
- `gameobject_template.Data1` (chest) → `gameobject_loot_template.Entry`.
- `item_template.entry` → `item_dbc.ID`.
- `spell_script_names.spell_id` → `spell_dbc.ID` or a client spell.
- `instance_template.map` → `map_dbc.ID`.

## Rules

- Never edit `base/`, `archive/`, or `updates/db_*`.
- Project SQL in `custom/db_*` must be re-applicable.
- Back up before a write batch.
- Use the primary key or a narrow indexed filter.
- Do not infer a relationship from a name alone; check the loader code or the data.

## References

- [specs/database.md](../../specs/database.md)
- [common-queries.md](common-queries.md)
- [erd.md](erd.md)
- [data/sql/base/db_world](../../data/sql/base/db_world)
