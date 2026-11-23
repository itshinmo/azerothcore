-- mod-objectives: world definitions, launch tasks, reward offers and the two reward vendors.
-- Re-applicable. The worldserver applies this file on restart (data/sql/custom/db_world, CUSTOM).
--
-- Era values: 0 Classic, 1 The Burning Crusade, 2 Wrath of the Lich King. Only Classic rows are
-- seeded in this slice; the era and level columns are part of the schema so TBC and WotLK rows are
-- data-only additions later (ADR-030).
-- Task scopes: 1 board daily, 2 board weekly, 3 chronicle weekly.
-- Task types: 1 kill creature, 2 complete quest, 3 kill dungeon/raid boss, 4 win battleground.
-- Currency values: 1 Adventure Marks (account), 2 Mythic Coins (character), 3 Raider's
-- Commendations (character).

CREATE TABLE IF NOT EXISTS `mod_objectives_task` (
  `id` int unsigned NOT NULL,
  `name` varchar(96) NOT NULL,
  `task_type` tinyint unsigned NOT NULL,
  `scope` tinyint unsigned NOT NULL,
  `era` tinyint unsigned NOT NULL DEFAULT 0,
  `min_level` tinyint unsigned NOT NULL DEFAULT 1,
  `max_level` tinyint unsigned NOT NULL DEFAULT 0,
  `faction` tinyint unsigned NOT NULL DEFAULT 0,
  `zone_id` int unsigned NOT NULL DEFAULT 0,
  `target_id` int unsigned NOT NULL DEFAULT 0,
  `required_count` int unsigned NOT NULL,
  `reward_marks` int unsigned NOT NULL DEFAULT 0,
  `reward_coins` int unsigned NOT NULL DEFAULT 0,
  `reward_commendations` int unsigned NOT NULL DEFAULT 0,
  `weight` int unsigned NOT NULL DEFAULT 1,
  `enabled` tinyint unsigned NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_mod_objectives_task_pool` (`enabled`, `scope`, `era`, `min_level`, `max_level`),
  KEY `idx_mod_objectives_task_target` (`task_type`, `target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mod_objectives_offer` (
  `id` int unsigned NOT NULL,
  `name` varchar(96) NOT NULL,
  `category` tinyint unsigned NOT NULL,
  `currency` tinyint unsigned NOT NULL,
  `cost` int unsigned NOT NULL,
  `item_id` int unsigned NOT NULL,
  `item_count` int unsigned NOT NULL DEFAULT 1,
  `min_level` tinyint unsigned NOT NULL DEFAULT 1,
  `max_level` tinyint unsigned NOT NULL DEFAULT 0,
  `faction` tinyint unsigned NOT NULL DEFAULT 0,
  `era` tinyint unsigned NOT NULL DEFAULT 0,
  `sort` int unsigned NOT NULL DEFAULT 0,
  `enabled` tinyint unsigned NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_mod_objectives_offer_pool` (`enabled`, `era`, `min_level`, `max_level`),
  KEY `idx_mod_objectives_offer_category` (`category`, `sort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELETE FROM `mod_objectives_task` WHERE `id` BETWEEN 950300 AND 950324;
INSERT INTO `mod_objectives_task`
  (`id`, `name`, `task_type`, `scope`, `era`, `min_level`, `max_level`, `faction`,
   `zone_id`, `target_id`, `required_count`, `reward_marks`, `reward_coins`,
   `reward_commendations`, `weight`, `enabled`)
VALUES
  (950300, 'Defias Pillagers', 1, 1, 0, 5, 60, 1, 40, 589, 10, 20, 2, 0, 2, 1),
  (950301, 'Dustwind Savages', 1, 1, 0, 5, 30, 2, 14, 3117, 8, 20, 2, 0, 2, 1),
  (950302, 'Hogger', 1, 1, 0, 8, 60, 1, 12, 448, 1, 20, 3, 0, 2, 1),
  (950303, 'Edwin VanCleef', 3, 1, 0, 15, 60, 0, 0, 639, 1, 15, 5, 0, 2, 1),
  (950304, 'Westfall Quests', 2, 1, 0, 5, 60, 1, 40, 0, 3, 20, 2, 0, 2, 1),
  (950305, 'Durotar Quests', 2, 1, 0, 1, 60, 2, 14, 0, 3, 20, 2, 0, 2, 1),
  (950306, 'Warsong Gulch Victory', 4, 1, 0, 10, 60, 0, 0, 2, 1, 25, 3, 0, 2, 1),
  (950307, 'Dungeon and Raid Bosses', 3, 2, 0, 15, 80, 0, 0, 0, 5, 75, 15, 1, 1, 1),
  (950308, 'Battleground Victor', 4, 2, 0, 10, 80, 0, 0, 0, 3, 75, 10, 2, 1, 1),
  (950309, 'Chronicle Quests', 2, 3, 0, 1, 80, 0, 0, 0, 10, 50, 10, 0, 1, 1),
  (950310, 'Chronicle Bosses', 3, 3, 0, 15, 80, 0, 0, 0, 3, 50, 15, 2, 1, 1),
  (950311, 'Chronicle Battlegrounds', 4, 3, 0, 10, 80, 0, 0, 0, 2, 50, 10, 2, 1, 1),
  (950312, 'Ragefire Chasm Boss', 3, 1, 0, 15, 60, 2, 0, 11518, 1, 18, 4, 0, 2, 1),
  (950313, 'Mulgore Quests', 2, 1, 0, 1, 60, 2, 215, 0, 3, 20, 2, 0, 2, 1),
  (950314, 'Tirisfal Quests', 2, 1, 0, 1, 60, 2, 85, 0, 3, 20, 2, 0, 2, 1),
  (950315, 'Razormane Quilboars', 1, 1, 0, 5, 60, 2, 14, 3111, 10, 20, 2, 0, 2, 1),
  (950316, 'Burning Blade Thugs', 1, 1, 0, 5, 60, 2, 14, 3195, 10, 20, 2, 0, 2, 1),
  (950317, 'Elwynn Quests', 2, 1, 0, 1, 60, 1, 12, 0, 3, 20, 2, 0, 2, 1),
  (950318, 'Redridge Quests', 2, 1, 0, 15, 60, 1, 44, 0, 3, 20, 2, 0, 2, 1),
  (950319, 'Kobold Vermin', 1, 1, 0, 1, 30, 1, 12, 6, 10, 15, 2, 0, 2, 1),
  (950320, 'Frostmane Troll Whelps', 1, 1, 0, 1, 30, 1, 1, 706, 8, 15, 2, 0, 2, 1),
  (950321, 'Goldtooth', 1, 1, 0, 1, 30, 1, 12, 327, 1, 18, 3, 0, 2, 1),
  (950322, 'Dun Morogh Quests', 2, 1, 0, 1, 60, 1, 1, 0, 3, 15, 2, 0, 2, 1),
  (950323, 'Scorpid Workers', 1, 1, 0, 1, 30, 2, 14, 3124, 10, 15, 2, 0, 2, 1),
  (950324, 'Vile Familiars', 1, 1, 0, 1, 30, 2, 14, 3101, 10, 15, 2, 0, 2, 1);

DELETE FROM `mod_objectives_offer` WHERE `id` BETWEEN 950340 AND 950359;
INSERT INTO `mod_objectives_offer`
  (`id`, `name`, `category`, `currency`, `cost`, `item_id`, `item_count`, `min_level`,
   `max_level`, `faction`, `era`, `sort`, `enabled`)
VALUES
  (950340, 'Silver Defias Belt', 1, 1, 40, 832, 1, 10, 0, 0, 0, 10, 1),
  (950341, 'Smite''s Reaver', 1, 2, 25, 5196, 1, 17, 0, 0, 0, 11, 1),
  (950342, 'Emberstone Staff', 1, 2, 20, 5201, 1, 18, 0, 0, 0, 12, 1),
  (950343, 'Cruel Barb', 1, 3, 10, 5191, 1, 19, 0, 0, 0, 13, 1),
  (950344, 'Linen Cloth x20', 2, 1, 10, 2589, 20, 1, 0, 0, 0, 20, 1),
  (950345, 'Medium Leather x10', 2, 2, 8, 2319, 10, 1, 0, 0, 0, 21, 1),
  (950346, 'Silk Cloth x10', 2, 3, 4, 4306, 10, 1, 0, 0, 0, 22, 1),
  (950347, 'Red Ribbon Pet Leash', 3, 1, 60, 44820, 1, 1, 0, 0, 0, 30, 1),
  (950348, 'Tabard of the Scarlet Crusade', 3, 3, 15, 23192, 1, 1, 0, 0, 0, 31, 1);

-- Vendor NPCs: 910020 Stormwind, 910021 Orgrimmar. npcflag 1 = gossip; the module builds the menu.
-- Spawn GUID block 5400011-5400012 extends the collections block (5400001-5400010); keep future
-- objective spawns inside 5400011-5400099 so upstream spawn updates stay below.
-- REPLACE is used instead of DELETE + INSERT because the SQL linter forbids deleting
-- creature_template rows and REPLACE is idempotent for a custom entry.
REPLACE INTO `creature_template`
  (`entry`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`,
   `faction`, `npcflag`, `rank`, `dmgschool`, `BaseAttackTime`, `RangeAttackTime`, `unit_class`,
   `unit_flags`, `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `AIName`,
   `MovementType`, `HoverHeight`, `RacialLeader`, `movementId`, `RegenHealth`,
   `CreatureImmunitiesId`, `flags_extra`, `ScriptName`)
VALUES
  (910020, 'Adventure Quartermaster', 'Objective Rewards', NULL, 0, 80, 80, 2, 35, 1, 0, 0, 2000,
   0, 1, 0, 7, 138936390, 0, 0, 0, '', 0, 1, 0, 0, 1, 0, 0, 'npc_objectives_vendor'),
  (910021, 'Chronicle Quartermaster', 'Objective Rewards', NULL, 0, 80, 80, 2, 35, 1, 0, 0, 2000,
   0, 1, 0, 7, 138936390, 0, 0, 0, '', 0, 1, 0, 0, 1, 0, 0, 'npc_objectives_vendor');

REPLACE INTO `creature_template_model`
  (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
VALUES
  (910020, 0, 1434, 1, 1, 0),
  (910021, 0, 1371, 1, 1, 0);

REPLACE INTO `npc_text` (`ID`, `text0_0`)
VALUES
  (950200, 'The board remembers what you have done, $N. Spend what you earned.');

DELETE FROM `creature` WHERE `id` = 910020 AND `guid` BETWEEN 5400011 AND 5400099;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
  `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`,
  `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `VerifiedBuild`)
VALUES
  (5400011, 910020, 0, 1519, 0, 1, 1, 0, -8831.8, 596.4, 95.8, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0);

DELETE FROM `creature` WHERE `id` = 910021 AND `guid` BETWEEN 5400011 AND 5400099;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
  `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`,
  `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `VerifiedBuild`)
VALUES
  (5400012, 910021, 1, 1637, 0, 1, 1, 0, 1891.6, -4326.8, 23.5, 3.9270, 7200, 0, 0, 1, 0, 0, 0, 0, 0, 0);
