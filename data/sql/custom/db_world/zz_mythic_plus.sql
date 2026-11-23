-- First playable Mythic+ slice: Ragefire Chasm (map 389), keys 1-5.
-- Re-applicable: static definition tables are dropped and recreated; character state tables use
-- CREATE TABLE IF NOT EXISTS in the characters database. Data uses REPLACE or narrow UPDATEs.
-- Module: modules/mod-mythic-plus. Contract: RFC-004 (proposed).
-- Derived from silviu20092/mod-mythic-plus (MIT), commit e2a487d.

-- Migration from the previous slice: item 5373 was renamed and made bind-on-pickup by SQL.
-- Restore only while the row still carries the old slice's marker; a stock row is a no-op.
UPDATE `item_template` SET `name` = 'Lucky Charm', `Quality` = 1, `bonding` = 0, `stackable` = 5, `maxcount` = 0, `BuyPrice` = 290, `SellPrice` = 72, `description` = '', `ScriptName` = '' WHERE `entry` = 5373 AND (`name` = 'Mythic Keystone' OR `ScriptName` = 'mythic_plus_keystone');

DROP TABLE IF EXISTS `mythic_plus_capable_dungeon`;
CREATE TABLE `mythic_plus_capable_dungeon` (
    `map` smallint unsigned NOT NULL,
    `era` tinyint unsigned NOT NULL DEFAULT '0',
    `mapdifficulty` smallint unsigned NOT NULL DEFAULT '0',
    `final_boss_entry` int unsigned NOT NULL,
    PRIMARY KEY (`map`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `mythic_plus_boss`;
CREATE TABLE `mythic_plus_boss` (
    `map_id` smallint unsigned NOT NULL,
    `entry` int unsigned NOT NULL,
    `is_final` tinyint unsigned NOT NULL DEFAULT '0',
    PRIMARY KEY (`map_id`, `entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `mythic_plus_level`;
CREATE TABLE `mythic_plus_level` (
    `lvl` int unsigned NOT NULL,
    `timelimit` int unsigned NOT NULL,
    PRIMARY KEY (`lvl`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `mythic_plus_affix`;
CREATE TABLE `mythic_plus_affix` (
    `lvl` int unsigned NOT NULL,
    `affixtype` smallint unsigned NOT NULL,
    `val1` float NOT NULL DEFAULT '0',
    `val2` float NOT NULL DEFAULT '0',
    PRIMARY KEY (`lvl`, `affixtype`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- The previous slice shipped affix type 4 (explosions). The drop removes it; this is an explicit
-- idempotent cleanup for a database that skipped the drop.
DELETE FROM `mythic_plus_affix` WHERE `affixtype` = 4;

DROP TABLE IF EXISTS `mythic_plus_level_rewards`;
CREATE TABLE `mythic_plus_level_rewards` (
    `lvl` int unsigned NOT NULL,
    `rewardtype` smallint unsigned NOT NULL,
    `val1` int unsigned NOT NULL DEFAULT '0',
    `val2` int unsigned NOT NULL DEFAULT '0',
    PRIMARY KEY (`lvl`, `rewardtype`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `mythic_plus_creature_scale`;
CREATE TABLE `mythic_plus_creature_scale` (
    `map_id` smallint unsigned NOT NULL,
    `key_level` tinyint unsigned NOT NULL,
    `is_boss` tinyint unsigned NOT NULL,
    `level` tinyint unsigned NOT NULL,
    `health_multiplier` float NOT NULL,
    `damage_multiplier` float NOT NULL,
    PRIMARY KEY (`map_id`, `key_level`, `is_boss`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

REPLACE INTO `mythic_plus_capable_dungeon` (`map`, `era`, `mapdifficulty`, `final_boss_entry`) VALUES
(389, 0, 0, 11520);

REPLACE INTO `mythic_plus_boss` (`map_id`, `entry`, `is_final`) VALUES
(389, 11517, 0),
(389, 11518, 0),
(389, 11519, 0),
(389, 11520, 1);

REPLACE INTO `mythic_plus_level` (`lvl`, `timelimit`) VALUES
(1, 1800),
(2, 1800),
(3, 1800),
(4, 1800),
(5, 1800);

REPLACE INTO `mythic_plus_affix` (`lvl`, `affixtype`, `val1`, `val2`) VALUES
(1, 0, 0.15, 0),
(2, 0, 0.15, 0),
(2, 1, 0.10, 0),
(2, 3, 10, 0),
(3, 0, 0.20, 0),
(3, 1, 0.15, 0),
(3, 2, 15, 0),
(3, 3, 20, 0),
(4, 0, 0.20, 0),
(4, 1, 0.15, 0),
(4, 2, 30, 0),
(4, 3, 30, 0),
(5, 0, 0.20, 0),
(5, 1, 0.15, 0),
(5, 2, 30, 0),
(5, 3, 30, 0);

REPLACE INTO `mythic_plus_level_rewards` (`lvl`, `rewardtype`, `val1`, `val2`) VALUES
(1, 0, 10000, 0),
(2, 0, 20000, 0),
(3, 0, 30000, 0),
(4, 0, 40000, 0),
(5, 0, 50000, 0);

REPLACE INTO `mythic_plus_creature_scale` (`map_id`, `key_level`, `is_boss`, `level`,
    `health_multiplier`, `damage_multiplier`) VALUES
(389, 1, 0, 80, 4.0, 1.0),
(389, 1, 1, 82, 20.0, 1.0),
(389, 2, 0, 80, 4.2, 1.05),
(389, 2, 1, 82, 21.0, 1.05),
(389, 3, 0, 81, 4.4, 1.1),
(389, 3, 1, 82, 22.0, 1.1),
(389, 4, 0, 81, 4.6, 1.15),
(389, 4, 1, 82, 23.0, 1.15),
(389, 5, 0, 81, 4.8, 1.2),
(389, 5, 1, 82, 24.0, 1.2);

-- Mythic+ NPC: creature 910013 outside the Ragefire Chasm entrance in Orgrimmar.
REPLACE INTO `creature_template` (`entry`, `difficulty_entry_1`, `difficulty_entry_2`, `difficulty_entry_3`,
    `KillCredit1`, `KillCredit2`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`,
    `exp`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `speed_swim`, `speed_flight`, `detection_range`,
    `rank`, `dmgschool`, `DamageModifier`, `BaseAttackTime`, `RangeAttackTime`, `BaseVariance`,
    `RangeVariance`, `unit_class`, `unit_flags`, `unit_flags2`, `dynamicflags`, `family`, `type`,
    `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `PetSpellDataId`, `VehicleId`, `mingold`,
    `maxgold`, `AIName`, `MovementType`, `HoverHeight`, `HealthModifier`, `ManaModifier`, `ArmorModifier`,
    `ExperienceModifier`, `RacialLeader`, `movementId`, `RegenHealth`, `CreatureImmunitiesId`,
    `flags_extra`, `ScriptName`, `VerifiedBuild`)
VALUES
(910013, 0, 0, 0, 0, 0, 'Mythic Plus', 'Mythic+ Guide', NULL, 0, 80, 80, 2, 35, 1, 1, 1.14286, 1, 1,
    20, 0, 0, 1, 2000, 0, 1, 1, 1, 0, 0, 0, 0, 7, 138936390, 0, 0, 0, 0, 0, 0, 0, '', 0, 1, 1, 1, 1, 1,
    0, 0, 1, 0, 0, 'mod_mythic_plus_npc', NULL);

REPLACE INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`,
    `Probability`, `VerifiedBuild`)
VALUES
(910013, 0, 19646, 1, 1, 0);

DELETE FROM `creature` WHERE `id` = 910013 AND `guid` IN (5400020, 5400021);

INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`,
    `equipment_id`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`,
    `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`,
    `unit_flags`, `dynamicflags`, `ScriptName`, `VerifiedBuild`, `CreateObject`, `Comment`)
VALUES
(5400020, 910013, 1, 1637, 1637, 1, 1, 0, 1811.78, -4410.5, -18.47, 5.20165, 300, 0, 0, 1, 0, 0,
    1, 0, 0, '', NULL, 0, 'Mythic+ guidance NPC: Orgrimmar'),
(5400021, 910013, 389, 0, 0, 1, 1, 0, 5.81, -14.82, -17.84, 4.39, 300, 0, 0, 1, 0, 0,
    1, 0, 0, '', NULL, 0, 'Mythic+ start NPC: Ragefire Chasm entrance');

DELETE FROM `command` WHERE `name` IN ('mythic', 'mythic info', 'mythic status', 'mythic reload');

INSERT INTO `command` (`name`, `security`, `help`) VALUES
('mythic', 0, 'Syntax: .mythic $subcommand'),
('mythic info', 0, 'Show the current Mythic+ run.'),
('mythic status', 3, 'Show Mythic+ load state and active runs.'),
('mythic reload', 3, 'Reload Mythic+ configuration, key levels, scales and affixes when no run is active.');
